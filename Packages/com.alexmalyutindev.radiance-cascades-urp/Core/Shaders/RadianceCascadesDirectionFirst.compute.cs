using UnityEngine;
using UnityEngine.Rendering;

namespace AlexMalyutinDev.RadianceCascades
{
    public class RadianceCascadesDirectionFirstCS
    {
        private readonly ComputeShader _compute;
        private readonly int _renderAndMergeKernel;

        public RadianceCascadesDirectionFirstCS(ComputeShader compute)
        {
            _compute = compute;
            _renderAndMergeKernel = _compute.FindKernel("RenderAndMergeCascade");
        }

        public void RenderMerge(
            CommandBuffer cmd,
            RTHandle color,
            RTHandle depth,
            RTHandle normals,
            RTHandle minMaxDepth,
            RTHandle smoothedDepth,
            RTHandle blurredColor,
            ref RTHandle target
        )
        {
            var kernel = _renderAndMergeKernel;
            cmd.BeginSample("RadianceCascade.RenderMerge");

            cmd.SetRenderTarget(target);
            cmd.ClearRenderTarget(false, true, Color.clear);

            var colorRT = color.rt;
            var colorTexelSize = new Vector4(
                1.0f / colorRT.width,
                1.0f / colorRT.height,
                colorRT.width,
                colorRT.height
            );
            cmd.SetComputeVectorParam(_compute, ShaderIds.ColorTextureTexelSize, colorTexelSize);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.ColorTexture, color);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.DepthTexture, depth);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.NormalsTexture, normals);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.MinMaxDepth, minMaxDepth);
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.SmoothedDepth, smoothedDepth);
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
            cmd.SetComputeTextureParam(_compute, kernel, ShaderIds.UpperCascade, target);

            for (int cascadeLevel = 5; cascadeLevel >= 0; cascadeLevel--)
            {
                Vector4 probesCount = new Vector4(
                    Mathf.FloorToInt(cascadeBufferSize.x / (8 * 1 << cascadeLevel)),
                    Mathf.FloorToInt(cascadeBufferSize.y / (8 * 1 << cascadeLevel))
                );
                cmd.SetComputeVectorParam(_compute, "_ProbesCount", probesCount);

                cmd.SetComputeIntParam(_compute, "_CascadeLevel", cascadeLevel);

                _compute.GetKernelThreadGroupSizes(kernel, out var x, out var y, out _);
                cmd.DispatchCompute(
                    _compute,
                    kernel,
                    Mathf.CeilToInt(cascadeBufferSize.x / x),
                    Mathf.CeilToInt(cascadeBufferSize.y / (y * (1 << cascadeLevel))),
                    1
                );
            }

            cmd.EndSample("RadianceCascade.RenderMerge");
        }
    }
}
