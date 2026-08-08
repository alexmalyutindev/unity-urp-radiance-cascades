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

        public void RenderMerge(ComputeCommandBuffer cmd, ref RenderMergeArgs args)
        {
            var kernel = _renderAndMergeKernel;
            if (kernel < 0) return;

            cmd.BeginSample("RadianceCascade.RenderMerge");

            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.DepthTexture, args.Depth);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.MinMaxDepth, args.MinMaxDepth);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.BlurredColor, args.BlurredColor);

            cmd.SetComputeVectorParam(_compute, ShaderIds.VarianceDepthSize, args.VarianceDepthSizeTexel);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.VarianceDepth, args.VarianceDepth);

            var cascadeBufferSize = new Vector4(8.0f * args.Cascade0Size.x, 8.0f * args.Cascade0Size.y);
            cascadeBufferSize.z = 1.0f / cascadeBufferSize.x;
            cascadeBufferSize.w = 1.0f / cascadeBufferSize.y;
            cmd.SetComputeVectorParam(_compute, ShaderIds.CascadeBufferSize, cascadeBufferSize);
            cmd.SetComputeTextureParam(_compute, kernel, "_RadianceCascades", args.Target);

            var viewMatrix = args.CameraData.GetViewMatrix();
            var projectionMatrix = args.CameraData.camera.nonJitteredProjectionMatrix;
            cmd.SetComputeMatrixParam(_compute, "_WorldToView", viewMatrix);
            cmd.SetComputeMatrixParam(_compute, "_ViewToWorld", viewMatrix.inverse);
            cmd.SetComputeMatrixParam(_compute, "_ViewToHClip", projectionMatrix);
            cmd.SetComputeMatrixParam(_compute, "_InvProjectionMatrix", projectionMatrix.inverse);

            cmd.SetComputeFloatParam(_compute, "_RayScale", args.RayScale);

            const int maxCascadeLevel = 4;
            var cascadeSizes = new Vector2Int[maxCascadeLevel + 2];
            var probesCounts = new Vector2Int[maxCascadeLevel + 2];
            
            cascadeSizes[0] = new Vector2Int((int)args.Cascade0Size.x, (int)args.Cascade0Size.y);
            probesCounts[0] = new Vector2Int((int)args.Cascade0ProbesCount.x, (int)args.Cascade0ProbesCount.y);
            for (int i = 1; i < probesCounts.Length; i++)
            {
                cascadeSizes[i] = new Vector2Int(
                    Mathf.RoundToInt(cascadeSizes[i - 1].x * 0.5f),
                    Mathf.RoundToInt(cascadeSizes[i - 1].y * 0.5f)
                );
                probesCounts[i] = new Vector2Int(
                    Mathf.RoundToInt(probesCounts[i - 1].x * 0.5f),
                    Mathf.RoundToInt(probesCounts[i - 1].y * 0.5f)
                );
            }
            
            for (int cascadeLevel = maxCascadeLevel; cascadeLevel >= 0; cascadeLevel--)
            {
                cmd.SetComputeFloatParam(_compute, "_CascadeLevel", cascadeLevel);

                // TODO: Check probes count sizes, possibly mismatch with MinMaxDepth mipmaps sizes!
                var (cascadeSize, probesCount) = GetCascadeSizeAndProbesCount(
                    args.Cascade0Size, 
                    args.Cascade0ProbesCount,
                    args.ScreenSize,
                    cascadeLevel
                );

                var (upperCascadeSize, upperProbesCount) = GetCascadeSizeAndProbesCount(
                    args.Cascade0Size, 
                    args.Cascade0ProbesCount, 
                    args.ScreenSize,
                    cascadeLevel + 1
                );

                cascadeSize = ToSizeTexel(cascadeSizes[cascadeLevel]);
                probesCount = ToSizeTexel(probesCounts[cascadeLevel]);
                upperCascadeSize = ToSizeTexel(cascadeSizes[cascadeLevel + 1]);
                upperProbesCount = ToSizeTexel(probesCounts[cascadeLevel + 1]);

                cmd.SetComputeVectorParam(_compute, "_CascadeSize", cascadeSize);
                cmd.SetComputeVectorParam(_compute, "_ProbesCount", probesCount);

                cmd.SetComputeVectorParam(_compute, "_UpperCascadeSize", upperCascadeSize);
                cmd.SetComputeVectorParam(_compute, "_UpperProbesCount", upperProbesCount);

                _compute.GetKernelThreadGroupSizes(kernel, out var groupSizeX, out var groupSizeY, out _);
                cmd.DispatchCompute(
                    _compute,
                    kernel,
                    Mathf.CeilToInt(8 * args.Cascade0Size.x / (2 * groupSizeX)),
                    Mathf.CeilToInt(args.Cascade0Size.y / ((1 << cascadeLevel) * groupSizeY)),
                    1
                );
            }

            cmd.EndSample("RadianceCascade.RenderMerge");
        }

        public void CombineSH(ComputeCommandBuffer cmd, ref CombineSHArgs args)
        {
            var kernel = _combineSHKernel;
            if (kernel < 0) return;

            cmd.BeginSample("RadianceCascade.CombineSH");

            cmd.SetComputeVectorParam(_compute, "_ProbesCount", args.CascadeProbesCount * 2.0f);
            cmd.SetComputeVectorParam(_compute, "_CascadeSize", args.CascadeProbesCountWithPadding * 2.0f);
            cmd.SetComputeVectorParam(_compute, "_UpperCascadeSize", args.CascadeProbesCountWithPadding);

            cmd.SetComputeMatrixParam(_compute, "_ViewToWorld", args.CameraData.GetViewMatrix().inverse);

            cmd.SetComputeTextureParam(_compute, kernel, "_RadianceCascades", args.Cascades);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.MinMaxDepth, args.MinMaxDepth);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.VarianceDepth, args.VarianceDepth);
            cmd.SetComputeTextureParam(_compute, kernel, "_RadianceSH", args.RadianceSH);

            int width = Mathf.FloorToInt(args.CascadeProbesCountWithPadding.x) * 2;
            int height = Mathf.FloorToInt(args.CascadeProbesCountWithPadding.y) * 2;
            cmd.DispatchCompute(_compute, kernel, width / 8, height / 4, 1);

            cmd.EndSample("RadianceCascade.CombineSH");
        }

        private (Vector4, Vector4) GetCascadeSizeAndProbesCount(
            Vector4 cascade0Size,
            Vector4 cascade0ProbesCount,
            Vector2Int screenSize,
            int cascadeLevel
        )
        {
            var size = new Vector4(
                Mathf.CeilToInt((int)cascade0Size.x >> cascadeLevel),
                Mathf.CeilToInt((int)cascade0Size.y >> cascadeLevel)
            );
            var probesCountX = Mathf.CeilToInt((int)cascade0ProbesCount.x >> cascadeLevel); // Mathf.Max(1, screenSize.x >> (cascadeLevel + 2)); // Mathf.FloorToInt(cascade0ProbesCount.x / (1 << cascadeLevel));
            var probesCountY = Mathf.CeilToInt((int)cascade0ProbesCount.y >> cascadeLevel); // Mathf.Max(1, screenSize.y >> (cascadeLevel + 2)); // Mathf.FloorToInt(cascade0ProbesCount.y / (1 << cascadeLevel));
            Vector4 probesCount = new Vector4(
                probesCountX, probesCountY,
                1.0f / probesCountX, 1.0f / probesCountY
            );
            return (size, probesCount);
        }

        private static Vector4 ToSizeTexel(Vector2Int size)
        {
            return new Vector4(size.x, size.y, 1.0f / size.x, 1.0f / size.y);
        }

        public struct RenderMergeArgs
        {
            public UniversalCameraData CameraData;
            public TextureHandle Depth;
            public TextureHandle MinMaxDepth;
            public TextureHandle VarianceDepth;
            public Vector4 VarianceDepthSizeTexel;
            public TextureHandle BlurredColor;
            public float RayScale;
            public TextureHandle Target;
            public Vector4 Cascade0Size;
            public Vector4 Cascade0ProbesCount;
            public Vector2Int ScreenSize;
        }

        public struct CombineSHArgs
        {
            public UniversalCameraData CameraData;
            public TextureHandle Cascades;
            public Vector4 CascadesSizeTexel;
            public TextureHandle MinMaxDepth;
            public TextureHandle VarianceDepth;
            public TextureHandle RadianceSH;
            public Vector4 CascadeProbesCountWithPadding;
            public Vector4 CascadeProbesCount;
        }
    }
}