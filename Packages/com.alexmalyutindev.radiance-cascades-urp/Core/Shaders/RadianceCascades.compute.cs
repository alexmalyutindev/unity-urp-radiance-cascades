using System.Buffers;
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

        private readonly ProfilingSampler _renderMergeSampler;
        private readonly ProfilingSampler _combineShSampler;
        
        private readonly LocalKeyword _bilinearKw;
        private readonly LocalKeyword _bilateralKw;
        private readonly ArrayPool<Vector2Int> _vector2IntPool;

        public RadianceCascadesDirectionFirstCS(ComputeShader compute)
        {
            _compute = compute;
            _vector2IntPool = ArrayPool<Vector2Int>.Create();
            _renderAndMergeKernel = _compute.FindKernel("RenderAndMergeCascade");
            _combineSHKernel = _compute.FindKernel("CombineSH");

            _renderMergeSampler = new ProfilingSampler("RadianceCascade.RenderMerge");
            _combineShSampler = new ProfilingSampler("RadianceCascade.CombineSH");
        }

        public void RenderMerge(ComputeCommandBuffer cmd, ref RenderMergeArgs args)
        {
            var kernel = _renderAndMergeKernel;
            if (kernel < 0) return;

            using var _ = new ProfilingScope(cmd, _renderMergeSampler);

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
            var cascadeSizes = _vector2IntPool.Rent(maxCascadeLevel + 2);
            var probesCounts = _vector2IntPool.Rent(maxCascadeLevel + 2);
            FillCascadePyramid(args.Cascade0Size, args.Cascade0ProbesCount, ref cascadeSizes, ref probesCounts);

            _compute.GetKernelThreadGroupSizes(kernel, out var groupSizeX, out var groupSizeY, out var _);
            var threadGroupsX = Mathf.CeilToInt(8 * args.Cascade0Size.x / (2 * groupSizeX));

            for (int cascadeLevel = maxCascadeLevel; cascadeLevel >= 0; cascadeLevel--)
            {
                cmd.SetComputeFloatParam(_compute, "_CascadeLevel", cascadeLevel);

                var cascadeSize = ToSizeTexel(cascadeSizes[cascadeLevel]);
                var probesCount = ToSizeTexel(probesCounts[cascadeLevel]);
                var upperCascadeSize = ToSizeTexel(cascadeSizes[cascadeLevel + 1]);
                var upperProbesCount = ToSizeTexel(probesCounts[cascadeLevel + 1]);

                cmd.SetComputeVectorParam(_compute, "_CascadeSize", cascadeSize);
                cmd.SetComputeVectorParam(_compute, "_ProbesCount", probesCount);

                cmd.SetComputeVectorParam(_compute, "_UpperCascadeSize", upperCascadeSize);
                cmd.SetComputeVectorParam(_compute, "_UpperProbesCount", upperProbesCount);

                var threadGroupsY = Mathf.CeilToInt(args.Cascade0Size.y / ((1 << cascadeLevel) * groupSizeY));
                cmd.DispatchCompute(_compute, kernel, threadGroupsX, threadGroupsY, 1);
            }

            _vector2IntPool.Return(probesCounts);
            _vector2IntPool.Return(cascadeSizes);
        }

        private static void FillCascadePyramid(
            Vector4 cascade0Size, Vector4 cascade0ProbesCount, 
            ref Vector2Int[] cascadeSizes, ref Vector2Int[] probesCounts)
        {
            cascadeSizes[0] = new Vector2Int((int)cascade0Size.x, (int)cascade0Size.y);
            probesCounts[0] = new Vector2Int((int)cascade0ProbesCount.x, (int)cascade0ProbesCount.y);
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
        }

        public void CombineSH(ComputeCommandBuffer cmd, ref CombineSHArgs args)
        {
            var kernel = _combineSHKernel;
            if (kernel < 0) return;

            using var _ = new ProfilingScope(cmd, _combineShSampler);

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
            // NOTE: Hardcoded groupSize!
            cmd.DispatchCompute(_compute, kernel, width / 8, height / 4, 1);
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