using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace AlexMalyutinDev.RadianceCascades
{
    public class DirectionFirstRCPass : ScriptableRenderPass, IDisposable
    {
        private readonly RadianceCascadesDirectionFirstCS _compute;
        private RTHandle _cascade0;
        private RTHandle _intermediateBuffer;

        private readonly Material _blitMaterial;
        private readonly RadianceCascadesRenderingData _renderingData;
        private readonly MaterialPropertyBlock _props;

        public DirectionFirstRCPass(
            RadianceCascadeResources resources,
            RadianceCascadesRenderingData renderingData
        )
        {
            profilingSampler = new ProfilingSampler("RadianceCascades.DirectionFirst");
            _compute = new RadianceCascadesDirectionFirstCS(resources.RadianceCascadesDirectionalFirstCS);
            // TODO: Make proper C# wrapper for Blit/Combine shader!
            _blitMaterial = resources.BlitMaterial;
            _renderingData = renderingData;
            _props = new MaterialPropertyBlock();
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            Vector2 renderSize = new Vector2(cameraTextureDescriptor.width, cameraTextureDescriptor.height);
            // TODO: Allocate texture with dimension (screen.width, screen.height) * 2 
            var minCascadeDim = 2 << 6;
            int cascadeWidth = 2 * minCascadeDim * Mathf.CeilToInt(renderSize.x / minCascadeDim);
            int cascadeHeight = 2 * minCascadeDim * Mathf.CeilToInt(renderSize.y / minCascadeDim);
            var desc = new RenderTextureDescriptor(cascadeWidth, cascadeHeight)
            {
                colorFormat = RenderTextureFormat.ARGBFloat,
                sRGB = false,
                enableRandomWrite = true,
            };
            RenderingUtils.ReAllocateIfNeeded(ref _cascade0, desc, name: "RadianceCascades");

            // TODO:
            desc = new RenderTextureDescriptor(cascadeWidth / 2, cascadeHeight / 2)
            {
                colorFormat = RenderTextureFormat.ARGBFloat,
                sRGB = false,
                enableRandomWrite = true,
            };
            RenderingUtils.ReAllocateIfNeeded(ref _intermediateBuffer, desc, name: "RadianceBuffer");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var rc = VolumeManager.instance.stack.GetComponent<RadianceCascades>();

            var renderer = renderingData.cameraData.renderer;
            var colorBuffer = renderer.cameraColorTargetHandle;
            var depthBuffer = renderer.cameraDepthTargetHandle;

            var cmd = CommandBufferPool.Get();

            using (new ProfilingScope(cmd, profilingSampler))
            {
                _compute.RenderMerge(
                    cmd,
                    ref renderingData.cameraData,
                    colorBuffer,
                    depthBuffer,
                    _renderingData.MinMaxDepth,
                    _renderingData.SmoothedDepth,
                    _renderingData.BlurredColorBuffer,
                    ref _cascade0
                );

                _compute.CombineCascades(cmd, _cascade0, _intermediateBuffer);

                cmd.BeginSample("RadianceCascade.Combine");
                {
                    // cmd.SetRenderTarget(_intermediateBuffer);
                    // _props.SetTexture(ShaderIds.GBuffer3, renderer.GetGBuffer(3));
                    // BlitUtils.BlitTexture(cmd, _cascade0, _blitMaterial, 2, _props);

                    cmd.SetRenderTarget(colorBuffer, depthBuffer);

                    _props.SetTexture(ShaderIds.MinMaxDepth, _renderingData.MinMaxDepth);
                    _props.SetFloat("_UpsampleTolerance", rc.UpsampleTolerance.value);
                    _props.SetFloat("_NoiseFilterStrength", rc.NoiseFilterStrength.value);
                    BlitUtils.BlitTexture(cmd, _intermediateBuffer, _blitMaterial, 3, _props);
                }
                cmd.EndSample("RadianceCascade.Combine");

                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
            }

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public void Dispose()
        {
            _cascade0?.Release();
        }
    }
}
