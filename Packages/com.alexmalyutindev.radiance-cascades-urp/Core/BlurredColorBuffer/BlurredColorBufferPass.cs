using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

namespace AlexMalyutinDev.RadianceCascades
{
    public class BlurredColorData : ContextItem
    {
        public TextureHandle BlurredColor;

        public override void Reset()
        {
            BlurredColor = TextureHandle.nullHandle;
        }
    }

    public class BlurredColorBufferPass : ScriptableRenderPass
    {
        private static readonly int InputMipLevelId = Shader.PropertyToID("_InputMipLevel");
        private static readonly int InputTexelSizeId = Shader.PropertyToID("_InputTexelSize");
        private static readonly int OffsetDirectionId = Shader.PropertyToID("_OffsetDirection");

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

        private class PassData
        {
            public TextureHandle FrameColor;
            public TextureHandle BlurredColorBuffer;
            public TextureHandle TempBuffer;
            public Material Material;

            public Vector4 InputSizeTexel;
            public Vector4 TargetResolution;
            public int TargetMipsCount;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var cameraData = frameData.Get<UniversalCameraData>();
            var resourceData = frameData.Get<UniversalResourceData>();
            var blurredColorData = frameData.Create<BlurredColorData>();

            var frameDesc = cameraData.cameraTargetDescriptor;

            using var builder = renderGraph.AddUnsafePass<PassData>(nameof(BlurredColorBufferPass), out var passData);
            builder.AllowPassCulling(false);

            passData.Material = _material;

            passData.InputSizeTexel = new Vector4(frameDesc.width, frameDesc.height, 1.0f / frameDesc.width, 1.0f / frameDesc.height);
            passData.FrameColor = resourceData.activeColorTexture;
            builder.UseTexture(passData.FrameColor);

            var targetWidth = frameDesc.width >> 1;
            var targetHeight = frameDesc.height >> 1;
            passData.TargetResolution = new Vector4(targetWidth, targetHeight);
            passData.TargetMipsCount = (int)Mathf.Log(targetHeight, 2);

            var desc = new TextureDesc(targetWidth, targetHeight)
            {
                name = "BlurredColorBuffer",
                format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.RGB111110Float, false),
                wrapMode = TextureWrapMode.Clamp,
                filterMode = FilterMode.Point,
                useMipMap = true,
                autoGenerateMips = false,
            };
            passData.BlurredColorBuffer = renderGraph.CreateTexture(desc);
            builder.UseTexture(passData.BlurredColorBuffer, AccessFlags.ReadWrite);
            blurredColorData.BlurredColor = passData.BlurredColorBuffer;

            desc.name = "Temp_BlurredColorBuffer";
            passData.TempBuffer = builder.CreateTransientTexture(desc);

            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
                var width = (int)data.TargetResolution.x;
                var height = (int)data.TargetResolution.y;

                cmd.SetRenderTarget(data.BlurredColorBuffer);
                BlitUtils.BlitTexture(cmd, data.FrameColor, data.Material, 1);
                cmd.BeginSample("GenMips");
                // BlitUtils.GenerateMips(cmd, data.BlurredColorBuffer, data.TempBuffer, data.Material, width, height, data.TargetMipsCount);
                cmd.GenerateMips(data.BlurredColorBuffer);
                cmd.EndSample("GenMips");

                cmd.BeginSample("ApplyBlur");
                for (int mipLevel = 0; mipLevel < data.TargetMipsCount; mipLevel++)
                {
                    cmd.SetGlobalVector(InputTexelSizeId, new Vector4(1.0f / width, 1.0f / height, width, height));

                    cmd.SetRenderTarget(data.TempBuffer, mipLevel);
                    cmd.SetGlobalInteger(InputMipLevelId, mipLevel);
                    cmd.SetGlobalVector(OffsetDirectionId, new Vector4(2, 0));
                    BlitUtils.BlitTexture(cmd, data.BlurredColorBuffer, data.Material, 2);

                    // NOTE: Blur current color buffer in to current mip chain
                    cmd.SetRenderTarget(data.BlurredColorBuffer, mipLevel);
                    cmd.SetGlobalInteger(InputMipLevelId, mipLevel);
                    cmd.SetGlobalVector(OffsetDirectionId, new Vector4(0, 2));
                    BlitUtils.BlitTexture(cmd, data.TempBuffer, data.Material, 2);

                    width >>= 1;
                    height >>= 1;
                }
                cmd.EndSample("ApplyBlur");
            });
        }
    }
}
