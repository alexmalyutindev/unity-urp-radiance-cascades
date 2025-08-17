using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

namespace AlexMalyutinDev.RadianceCascades
{
    public class VarianceDepthData : ContextItem
    {
        public TextureHandle VarianceDepth;

        public override void Reset()
        {
            VarianceDepth = TextureHandle.nullHandle;
        }
    }

    public class VarianceDepthPass : ScriptableRenderPass
    {
        private const int DepthToMomentsPass = 0;
        private const int BlurVerticalPass = 1;
        private const int BlurHorizontalPass = 2;
        private readonly Material _material;
        private readonly RadianceCascadesRenderingData _radianceCascadesRenderingData;
        private RTHandle _tempBuffer;

        public VarianceDepthPass(Material material, RadianceCascadesRenderingData radianceCascadesRenderingData)
        {
            profilingSampler = new ProfilingSampler(nameof(VarianceDepthPass));
            _material = material;
            _radianceCascadesRenderingData = radianceCascadesRenderingData;
        }

        private class PassData
        {
            public TextureHandle FrameDepth;
            public TextureHandle TempBuffer;
            public TextureHandle VarianceDepth;
            public Material Material;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var varianceDepthData = frameData.Create<VarianceDepthData>();

            var cameraData = frameData.Get<UniversalCameraData>();
            var resourceData = frameData.Get<UniversalResourceData>();

            var frameDesc = cameraData.cameraTargetDescriptor;

            using var builder = renderGraph.AddUnsafePass<PassData>(nameof(VarianceDepthPass), out var passData);
            builder.AllowPassCulling(false);

            passData.Material = _material;

            passData.FrameDepth = resourceData.activeDepthTexture;
            builder.UseTexture(passData.FrameDepth);

            var desc = new TextureDesc(frameDesc.width >> 1, frameDesc.height >> 1)
            {
                name = "VarianceDepth",
                colorFormat = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.RGFloat, false),
                wrapMode = TextureWrapMode.Clamp,
                filterMode = FilterMode.Bilinear,
            };
            passData.VarianceDepth = renderGraph.CreateTexture(desc);
            builder.UseTexture(passData.VarianceDepth, AccessFlags.Write);
            varianceDepthData.VarianceDepth = passData.VarianceDepth;

            desc.name = "Temp";
            passData.TempBuffer = builder.CreateTransientTexture(desc);

            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);

                cmd.SetRenderTarget(data.VarianceDepth);
                BlitUtils.BlitTexture(cmd, data.FrameDepth, data.Material, DepthToMomentsPass);

                cmd.SetRenderTarget(data.TempBuffer);
                BlitUtils.BlitTexture(cmd, data.VarianceDepth, data.Material, BlurVerticalPass);

                cmd.SetRenderTarget(data.VarianceDepth);
                BlitUtils.BlitTexture(cmd, data.TempBuffer, data.Material, BlurHorizontalPass);
                
                // TODO: Add mipmaps!
                // int width = _radianceCascadesRenderingData.VarianceDepth.rt.width;
                // int height = _radianceCascadesRenderingData.VarianceDepth.rt.height;
                // for (int mipLevel = 0; mipLevel < _radianceCascadesRenderingData.VarianceDepth.rt.mipmapCount; mipLevel++)
                // {
                //     cmd.SetGlobalInteger("_InputMipLevel", mipLevel);
                //     cmd.SetGlobalVector("_InputTexelSize", new Vector4(1.0f / width, 1.0f / height, width, width));
                //
                //     cmd.SetRenderTarget(_tempBuffer, mipLevel);
                //     BlitUtils.BlitTexture(cmd, _radianceCascadesRenderingData.VarianceDepth, _material, BlurVerticalPass);
                //
                //     cmd.SetRenderTarget(_radianceCascadesRenderingData.VarianceDepth, mipLevel);
                //     BlitUtils.BlitTexture(cmd, _tempBuffer, _material, BlurHorizontalPass);
                //
                //     width /= 2;
                //     height /= 2;
                // }
            });
        }
    }
}
