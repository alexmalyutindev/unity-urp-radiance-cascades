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
        private RTHandle _intermediateBuffer;
        private RTHandle _intermediateBuffer2;
        private Material _blitMaterial;
        private RadianceCascadesRenderingData _renderingData;

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
            int cascadeWidth = 1024 * 2; // cameraTextureDescriptor.width; // 2048; // 
            int cascadeHeight = 512 * 2; // cameraTextureDescriptor.height; // 1024; // 
            var desc = new RenderTextureDescriptor(cascadeWidth, cascadeHeight)
            {
                colorFormat = RenderTextureFormat.ARGBFloat,
                sRGB = false,
                enableRandomWrite = true,
            };
            RenderingUtils.ReAllocateIfNeeded(ref _cascade0, desc, name: "RadianceCascades");

            desc = new RenderTextureDescriptor(cameraTextureDescriptor.width / 2, cameraTextureDescriptor.height / 2)
            {
                colorFormat = RenderTextureFormat.ARGBFloat,
                sRGB = false,
            };
            RenderingUtils.ReAllocateIfNeeded(ref _intermediateBuffer, desc, name: "RadianceBuffer");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var renderer = renderingData.cameraData.renderer;
            var colorBuffer = renderer.cameraColorTargetHandle;
            var depthBuffer = renderer.cameraDepthTargetHandle;

            var cmd = CommandBufferPool.Get();

            using (new ProfilingScope(cmd, profilingSampler))
            {
                // _compute.Render(
                //     cmd,
                //     colorBuffer,
                //     depthBuffer,
                //     renderer.GetGBuffer(2),
                //     _renderingData.MinMaxDepth,
                //     ref _cascade0
                // );

                // TODO: Fix merge
                _compute.RenderMerge(
                    cmd,
                    colorBuffer,
                    depthBuffer,
                    renderer.GetGBuffer(2),
                    _renderingData.MinMaxDepth,
                    ref _cascade0
                );

                // _compute.Merge(cmd, ref _cascade0);

                cmd.BeginSample("RadianceCascade.Combine");
                {
                    cmd.SetRenderTarget(_intermediateBuffer);
                    cmd.SetGlobalTexture("_GBuffer3", renderer.GetGBuffer(3));
                    BlitUtils.BlitTexture(cmd, _cascade0, _blitMaterial, 2);

                    cmd.SetRenderTarget(colorBuffer);
                    BlitUtils.BlitTexture(cmd, _intermediateBuffer, _blitMaterial, 3);
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
