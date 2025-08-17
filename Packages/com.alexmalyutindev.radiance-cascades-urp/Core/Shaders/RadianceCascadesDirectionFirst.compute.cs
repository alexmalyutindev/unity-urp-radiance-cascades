using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
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
        }

        public void RenderMerge(
            ComputeCommandBuffer cmd,
            ref UniversalCameraData cameraData,
            TextureHandle depth,
            TextureHandle minMaxDepth,
            TextureHandle varianceDepth,
            Vector4 varianceDepthSizeTexel,
            TextureHandle blurredColor,
            float rayScale,
            ref TextureHandle target,
            Vector4 targetSizeTexel
        )
        {
            var kernel = _renderAndMergeKernel;
            if (kernel < 0) return;

            cmd.BeginSample("RadianceCascade.RenderMerge");

            // TODO: Remove! Only for debug purpose!
            // cmd.SetRenderTarget(target);
            // cmd.ClearRenderTarget(false, true, Color.clear);

            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.DepthTexture, depth);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.MinMaxDepth, minMaxDepth);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.BlurredColor, blurredColor);


            cmd.SetComputeVectorParam(_compute, ShaderIds.VarianceDepthSize, varianceDepthSizeTexel);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.VarianceDepth, varianceDepth);

            cmd.SetComputeVectorParam(_compute, ShaderIds.CascadeBufferSize, targetSizeTexel);
            cmd.SetComputeTextureParam(_compute, kernel, "_RadianceCascades", target);

            var viewMatrix = cameraData.GetViewMatrix();
            var projectionMatrix = cameraData.camera.nonJitteredProjectionMatrix;
            cmd.SetComputeMatrixParam(_compute, "_WorldToView", viewMatrix);
            cmd.SetComputeMatrixParam(_compute, "_ViewToWorld", viewMatrix.inverse);
            cmd.SetComputeMatrixParam(_compute, "_ViewToHClip", projectionMatrix);
            cmd.SetComputeMatrixParam(_compute, "_InvProjectionMatrix", projectionMatrix.inverse);

            cmd.SetComputeFloatParam(_compute, "_RayScale", rayScale);

            for (int cascadeLevel = 5; cascadeLevel >= 0; cascadeLevel--)
            {
                Vector4 probesCount = new Vector4(
                    Mathf.FloorToInt(targetSizeTexel.x / (8 * 1 << cascadeLevel)),
                    Mathf.FloorToInt(targetSizeTexel.y / (8 * 1 << cascadeLevel))
                );
                probesCount.z = 1.0f / probesCount.x;
                probesCount.w = 1.0f / probesCount.y;
                cmd.SetComputeVectorParam(_compute, "_ProbesCount", probesCount);

                cmd.SetComputeIntParam(_compute, "_CascadeLevel", cascadeLevel);

                _compute.GetKernelThreadGroupSizes(kernel, out var groupSizeX, out var groupSizeY, out _);
                // TODO: Spawn only one cascade size Y groups, make all latitudinal ray in one thread?
                cmd.DispatchCompute(
                    _compute,
                    kernel,
                    Mathf.CeilToInt(targetSizeTexel.x / (2 * groupSizeX)),
                    Mathf.CeilToInt(targetSizeTexel.y / (groupSizeY * (8 << cascadeLevel))),
                    1
                );
            }

            cmd.EndSample("RadianceCascade.RenderMerge");
        }

        public void CombineSH(
            ComputeCommandBuffer cmd,
            ref UniversalCameraData cameraData,
            TextureHandle cascades,
            Vector4 cascadesSizeTexel,
            TextureHandle minMaxDepth,
            TextureHandle varianceDepth,
            ref TextureHandle radianceSH,
            Vector4 radianceSHSizeTexel
        )
        {
            var kernel = _combineSHKernel;
            if (kernel < 0) return;

            cmd.BeginSample("RadianceCascade.CombineSH");

            // TODO: Remove! Only for debug purpose!
            // cmd.SetRenderTarget(radianceSH);

            Vector4 probesCount = new Vector4(
                Mathf.FloorToInt(cascadesSizeTexel.x / 4),
                Mathf.FloorToInt(cascadesSizeTexel.y / 4)
            );
            // TODO: Replace props names with ids!
            cmd.SetComputeVectorParam(_compute, "_ProbesCount", probesCount);
            cmd.SetComputeMatrixParam(_compute, "_ViewToWorld", cameraData.GetViewMatrix().inverse);

            cmd.SetComputeTextureParam(_compute, kernel, "_RadianceCascades", cascades);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.MinMaxDepth, minMaxDepth);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.VarianceDepth, varianceDepth);
            cmd.SetComputeTextureParam(_compute, kernel, "_RadianceSH", radianceSH);

            int width = Mathf.FloorToInt(radianceSHSizeTexel.x) / 2;
            int height = Mathf.FloorToInt(radianceSHSizeTexel.y) / 2;
            cmd.DispatchCompute(_compute, kernel, width / 8, height / 4, 1);
            cmd.EndSample("RadianceCascade.CombineSH");
        }
    }
}
