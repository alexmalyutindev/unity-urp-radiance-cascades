using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace AlexMalyutinDev.RadianceCascades.BlurredColorBuffer
{
    public class BlurredColorBufferPass : ScriptableRenderPass
    {
        private static readonly int InputMipLevel = Shader.PropertyToID("_InputMipLevel");
        private static readonly int InputResolution = Shader.PropertyToID("_InputResolution");

        private readonly Material _material;
        private readonly RadianceCascadesRenderingData _radianceCascadesRenderingData;
        private RTHandle _tempBlurBuffer;

        public BlurredColorBufferPass(
            Material material,
            RadianceCascadesRenderingData radianceCascadesRenderingData
        )
        {
            profilingSampler = new ProfilingSampler(nameof(BlurredColorBufferPass));
            _material = material;
            _radianceCascadesRenderingData = radianceCascadesRenderingData;
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            // TODO: Use resolution from settings.
            var desc = new RenderTextureDescriptor(
                2048 / 4, // cameraTextureDescriptor.width >> 1,
                1024 / 4 // cameraTextureDescriptor.height >> 1
            )
            {
                colorFormat = cameraTextureDescriptor.colorFormat,
                sRGB = cameraTextureDescriptor.sRGB,
                depthStencilFormat = GraphicsFormat.None,
                useMipMap = true,
                autoGenerateMips = false,
            };
            RenderingUtils.ReAllocateIfNeeded(
                ref _radianceCascadesRenderingData.BlurredColorBuffer,
                desc,
                FilterMode.Bilinear,
                TextureWrapMode.Clamp,
                name: "BlurredColorBuffer"
            );

            desc.width >>= 1;
            desc.height >>= 1;
            desc.useMipMap = false;
            RenderingUtils.ReAllocateIfNeeded(
                ref _tempBlurBuffer,
                desc,
                FilterMode.Bilinear,
                TextureWrapMode.Clamp,
                name: "BlurredColorBuffer2"
            );
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (_material == null) return;

            var cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, profilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                var colorBuffer = renderingData.cameraData.renderer.cameraColorTargetHandle;
                int width = colorBuffer.rt.width;
                int height = colorBuffer.rt.height;
                var mipsCount = _radianceCascadesRenderingData.BlurredColorBuffer.rt.mipmapCount;

                cmd.SetRenderTarget(_radianceCascadesRenderingData.BlurredColorBuffer, 0, CubemapFace.Unknown);
                cmd.SetGlobalInteger(InputMipLevel, 0);
                cmd.SetGlobalVector(InputResolution, new Vector4(width, height) * 0.25f);
                BlitUtils.BlitTexture(cmd, colorBuffer, _material, 0);

                
                width = _radianceCascadesRenderingData.BlurredColorBuffer.rt.width;
                height = _radianceCascadesRenderingData.BlurredColorBuffer.rt.height;
                
                // NOTE: Can't render into MipLevel+1 and read from MipLevel of the same image on DX!
                // Work around is to render blur in two taps:
                // horizontal blur into _tempBlurBuffer, then vertical blur into BlurredColorBuffer
                for (int mipLevel = 1; mipLevel < mipsCount; mipLevel++)
                {
                    cmd.SetGlobalVector(InputResolution, new Vector4(width, height));

                    cmd.SetRenderTarget(_tempBlurBuffer, mipLevel - 1);
                    cmd.SetGlobalInteger(InputMipLevel, mipLevel - 1);
                    cmd.SetGlobalVector("_OffsetDirection", new Vector4(1, 0));
                    BlitUtils.BlitTexture(cmd, _radianceCascadesRenderingData.BlurredColorBuffer, _material, 3);

                    cmd.SetRenderTarget(_radianceCascadesRenderingData.BlurredColorBuffer, mipLevel);
                    cmd.SetGlobalInteger(InputMipLevel, mipLevel - 1);
                    cmd.SetGlobalVector("_OffsetDirection", new Vector4(0, 1));
                    BlitUtils.BlitTexture(cmd, _tempBlurBuffer, _material, 3);

                    width >>= 1;
                    height >>= 1;
                }
            }

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }
    }
}
