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
            Vector4 cascade0Size,
            Vector4 cascade0ProbesCount
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

            cmd.SetComputeVectorParam(_compute, ShaderIds.CascadeBufferSize, cascade0Size * 8);
            cmd.SetComputeTextureParam(_compute, kernel, "_RadianceCascades", target);

            var viewMatrix = cameraData.GetViewMatrix();
            var projectionMatrix = cameraData.camera.nonJitteredProjectionMatrix;
            cmd.SetComputeMatrixParam(_compute, "_WorldToView", viewMatrix);
            cmd.SetComputeMatrixParam(_compute, "_ViewToWorld", viewMatrix.inverse);
            cmd.SetComputeMatrixParam(_compute, "_ViewToHClip", projectionMatrix);
            cmd.SetComputeMatrixParam(_compute, "_InvProjectionMatrix", projectionMatrix.inverse);

            cmd.SetComputeFloatParam(_compute, "_RayScale", rayScale);

            const int maxCascadeLevel = 5;
            for (int cascadeLevel = maxCascadeLevel; cascadeLevel >= 0; cascadeLevel--)
            {
                cmd.SetComputeFloatParam(_compute, "_CascadeLevel", cascadeLevel);

                var (cascadeSize, probesCount) = GetCascadeSizeAndProbesCount(cascade0Size, cascade0ProbesCount, cascadeLevel);
                cmd.SetComputeVectorParam(_compute, "_CascadeSize", cascadeSize);
                cmd.SetComputeVectorParam(_compute, "_ProbesCount", probesCount);

                var (upperCascadeSize, upperProbesCount) = GetCascadeSizeAndProbesCount(cascade0Size, cascade0ProbesCount, cascadeLevel + 1);
                cmd.SetComputeVectorParam(_compute, "_UpperCascadeSize", upperCascadeSize);
                cmd.SetComputeVectorParam(_compute, "_UpperProbesCount", upperProbesCount);

                _compute.GetKernelThreadGroupSizes(kernel, out var groupSizeX, out var groupSizeY, out _);
                // TODO: Spawn only one cascade size Y groups, make all latitudinal ray in one thread?
                cmd.DispatchCompute(
                    _compute,
                    kernel,
                    Mathf.CeilToInt(8 * cascade0Size.x / (2 * groupSizeX)),
                    Mathf.CeilToInt(cascade0Size.y / ((1 << cascadeLevel) * groupSizeY)),
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
            Vector4 cascadeProbesCountWithPadding,
            Vector4 cascadeProbesCount
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
            cmd.SetComputeVectorParam(_compute, "_ProbesCount", cascadeProbesCount * 2.0f);
            cmd.SetComputeVectorParam(_compute, "_CascadeSize", cascadeProbesCountWithPadding * 2.0f);

            cmd.SetComputeMatrixParam(_compute, "_ViewToWorld", cameraData.GetViewMatrix().inverse);

            cmd.SetComputeTextureParam(_compute, kernel, "_RadianceCascades", cascades);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.MinMaxDepth, minMaxDepth);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.VarianceDepth, varianceDepth);
            cmd.SetComputeTextureParam(_compute, kernel, "_RadianceSH", radianceSH);

            // NOTE: This pass uses cascades buffer, and upscales it x2.
            int width = Mathf.FloorToInt(cascadeProbesCountWithPadding.x) * 2;
            int height = Mathf.FloorToInt(cascadeProbesCountWithPadding.y) * 2;
            cmd.DispatchCompute(_compute, kernel, width / 8, height / 4, 1);
            cmd.EndSample("RadianceCascade.CombineSH");
        }

        private (Vector4, Vector4) GetCascadeSizeAndProbesCount(Vector4 cascade0Size, Vector4 cascade0ProbesCount, int cascadeLevel)
        {
            var size = new Vector4(
                Mathf.FloorToInt(cascade0Size.x / (1 << cascadeLevel)),
                Mathf.FloorToInt(cascade0Size.y / (1 << cascadeLevel))
            );
            Vector4 probesCount = new Vector4(
                Mathf.FloorToInt(cascade0ProbesCount.x / (1 << cascadeLevel)),
                Mathf.FloorToInt(cascade0ProbesCount.y / (1 << cascadeLevel))
            );
            return (size, probesCount);
        }
    }
}
