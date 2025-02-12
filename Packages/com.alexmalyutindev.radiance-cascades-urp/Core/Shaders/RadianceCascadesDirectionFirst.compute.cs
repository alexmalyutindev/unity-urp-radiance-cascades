using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace AlexMalyutinDev.RadianceCascades
{
    public class RadianceCascadesDirectionFirstCS
    {
        private readonly ComputeShader _compute;
        private readonly int _renderAndMergeKernel;
        private readonly int _combineSHKernel;
        private readonly LocalKeyword _bilinearKw;
        private readonly LocalKeyword _bilateralKw;

        public RadianceCascadesDirectionFirstCS(ComputeShader compute)
        {
            _compute = compute;
            _renderAndMergeKernel = _compute.FindKernel("RenderAndMergeCascade");
            _combineSHKernel = _compute.FindKernel("CombineSH");
            // TODO: Fix keywords.
            // _bilinearKw = new LocalKeyword(_compute, "_UPSCALE_MODE_BILINEAR");
            // _bilateralKw = new LocalKeyword(_compute, "_UPSCALE_MODE_BILATERAL");
        }

        public void RenderMerge(
            CommandBuffer cmd,
            ref CameraData cameraData,
            RTHandle depth,
            RTHandle minMaxDepth,
            RTHandle varianceDepth,
            RTHandle blurredColor,
            float rayScale,
            ref RTHandle target
        )
        {
            var kernel = _renderAndMergeKernel;
            cmd.BeginSample("RadianceCascade.RenderMerge");

            // TODO: Remove! Only for debug purpose!
            cmd.SetRenderTarget(target);
            cmd.ClearRenderTarget(false, true, Color.clear);

            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.DepthTexture, depth);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.MinMaxDepth, minMaxDepth);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.VarianceDepth, varianceDepth);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.BlurredColor, blurredColor);

            var targetRT = target.rt;
            var cascadeBufferSize = new Vector4(
                targetRT.width,
                targetRT.height,
                1.0f / targetRT.width,
                1.0f / targetRT.height
            );
            cmd.SetComputeVectorParam(_compute, ShaderIds.CascadeBufferSize, cascadeBufferSize);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.OutCascade, target);

            cmd.SetComputeMatrixParam(_compute, "_WorldToView", cameraData.GetViewMatrix());
            cmd.SetComputeMatrixParam(_compute, "_ViewToHClip", cameraData.GetGPUProjectionMatrix());
            
            cmd.SetComputeFloatParam(_compute, "_RayScale", rayScale);

            // TODO: Fix keywords.
            // cmd.SetKeyword(_compute, _bilinearKw, settings.UpscaleMode.value == UpscaleMode.Bilinear);
            // cmd.SetKeyword(_compute, _bilateralKw, settings.UpscaleMode.value == UpscaleMode.Bilateral);

            for (int cascadeLevel = 5; cascadeLevel >= 0; cascadeLevel--)
            {
                Vector4 probesCount = new Vector4(
                    Mathf.FloorToInt(cascadeBufferSize.x / (8 * 1 << cascadeLevel)),
                    Mathf.FloorToInt(cascadeBufferSize.y / (8 * 1 << cascadeLevel))
                );
                cmd.SetComputeVectorParam(_compute, "_ProbesCount", probesCount);

                cmd.SetComputeIntParam(_compute, "_CascadeLevel", cascadeLevel);

                _compute.GetKernelThreadGroupSizes(kernel, out var x, out var y, out _);
                // TODO: Spawn only one cascade size Y groups, make all latitudinal ray in one thread?
                cmd.DispatchCompute(
                    _compute,
                    kernel,
                    Mathf.CeilToInt(cascadeBufferSize.x / 2 / x),
                    Mathf.CeilToInt(cascadeBufferSize.y / (y * (1 << cascadeLevel))),
                    1
                );
            }

            cmd.EndSample("RadianceCascade.RenderMerge");
        }

        public void CombineSH(CommandBuffer cmd, RTHandle cascades, RTHandle radianceSH)
        {
            cmd.BeginSample("RadianceCascade.CombineSH");
            
            // TODO: Remove! Only for debug purpose!
            cmd.SetRenderTarget(radianceSH);

            Vector4 probesCount = new Vector4(
                Mathf.FloorToInt(cascades.rt.width / 4),
                Mathf.FloorToInt(cascades.rt.height / 4)
            );
            cmd.SetComputeVectorParam(_compute, "_ProbesCount", probesCount);
            
            cmd.SetComputeTextureParam(_compute, _combineSHKernel, ShaderIds.OutCascade, cascades);
            cmd.SetComputeTextureParam(_compute, _combineSHKernel, "_RadianceSH", radianceSH);

            
            int width = radianceSH.rt.width / 2;
            int height = radianceSH.rt.height / 2;
            cmd.DispatchCompute(_compute, _combineSHKernel, width / 8, height / 4, 1);
            cmd.EndSample("RadianceCascade.CombineSH");
        }
    }
}
