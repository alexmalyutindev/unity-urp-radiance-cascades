using System;
using InternalBridge;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace AlexMalyutinDev.RadianceCascades
{
    public class DirectionFirstRCPass : ScriptableRenderPass, IDisposable
    {
        private readonly RadianceCascadesDirectionFirstCS _compute;
        private RTHandle _cascade0;
        private RTHandle _radianceSH;
        private RTHandle _intermediateBuffer;
        private RTHandle _intermediateBuffer2;

        private readonly Material _blitMaterial;
        private readonly RadianceCascadesRenderingData _renderingData;

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
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            // 512 => 512 / 8 = 64 probes in row
            // TODO: Allocate texture with dimension (screen.width, screen.height) * 2 
            int cascadeWidth = 2048; // cameraTextureDescriptor.width; // 2048; // 
            int cascadeHeight = 1024; // cameraTextureDescriptor.height; // 1024; // 
            var desc = new RenderTextureDescriptor(cascadeWidth, cascadeHeight)
            {
                colorFormat = RenderTextureFormat.ARGBFloat,
                sRGB = false,
                enableRandomWrite = true,
            };
            RenderingUtils.ReAllocateIfNeeded(ref _cascade0, desc, name: "RadianceCascades");

            desc = new RenderTextureDescriptor(cascadeWidth / 2, cascadeHeight / 2)
            {
                colorFormat = RenderTextureFormat.ARGBFloat,
                sRGB = false,
                enableRandomWrite = true,
            };
            RenderingUtils.ReAllocateIfNeeded(ref _radianceSH, desc, name: "RadianceSH");

            desc = new RenderTextureDescriptor(cameraTextureDescriptor.width, cameraTextureDescriptor.height)
            {
                colorFormat = RenderTextureFormat.ARGBFloat,
                sRGB = false,
            };
            RenderingUtils.ReAllocateIfNeeded(ref _intermediateBuffer, desc, name: "RadianceBuffer");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var radianceCascades = VolumeManager.instance.stack.GetComponent<RadianceCascades>();

            var renderer = renderingData.cameraData.renderer;
            var colorBuffer = renderer.cameraColorTargetHandle;
            var depthBuffer = renderer.cameraDepthTargetHandle;

            var cmd = CommandBufferPool.Get();

            using (new ProfilingScope(cmd, profilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                _compute.RenderMerge(
                    cmd,
                    ref renderingData.cameraData,
                    colorBuffer,
                    depthBuffer,
                    _renderingData.MinMaxDepth,
                    _renderingData.SmoothedDepth,
                    _renderingData.VarianceDepth,
                    _renderingData.BlurredColorBuffer,
                    ref _cascade0
                );

                if (!radianceCascades.UseSH.value)
                {
                    cmd.BeginSample("RadianceCascade.Combine");
                    {
                        cmd.SetRenderTarget(_intermediateBuffer);
                        cmd.SetGlobalTexture(ShaderIds.GBuffer3, renderer.GetGBuffer(3));
                        cmd.SetGlobalTexture(ShaderIds.MinMaxDepth, _renderingData.MinMaxDepth);
                        BlitUtils.BlitTexture(cmd, _cascade0, _blitMaterial, 2);
                        
                        cmd.SetRenderTarget(colorBuffer, depthBuffer);
                        BlitUtils.BlitTexture(cmd, _intermediateBuffer, _blitMaterial, 3);
                    }
                    cmd.EndSample("RadianceCascade.Combine");
                }
                else
                {
                    // TODO: Combine into SH.
                    _compute.CombineSH(cmd, _cascade0, _radianceSH);

                    cmd.BeginSample("RadianceCascade.BlitSH");
                    cmd.SetRenderTarget(colorBuffer, depthBuffer);
                    BlitUtils.BlitTexture(cmd, _radianceSH, _blitMaterial, 4);
                    cmd.EndSample("RadianceCascade.BlitSH");
                }
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
