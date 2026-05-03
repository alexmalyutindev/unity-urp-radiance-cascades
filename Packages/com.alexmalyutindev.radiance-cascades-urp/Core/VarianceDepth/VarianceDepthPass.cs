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
        private const int BlurHorizontalPass = 1;
        private const int BlurVerticalPass = 2;
        private readonly Material _material;
        private readonly RadianceCascadesRenderingData _radianceCascadesRenderingData;

        public VarianceDepthPass(Material material, RadianceCascadesRenderingData radianceCascadesRenderingData)
        {
            profilingSampler = new ProfilingSampler(nameof(VarianceDepthPass));
            _material = material;
            _radianceCascadesRenderingData = radianceCascadesRenderingData;
        }

        private class PassData
        {
            public TextureHandle FrameDepth;
            public TextureHandle IntermediateDownsampleBuffer;
            public TextureHandle VarianceDepth;
            public Material Material;

            public int TargetMipsCount;
            public Vector2Int TargetResolution;
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
                useMipMap = true,
                autoGenerateMips = false,
            };
            passData.TargetResolution = new Vector2Int(desc.width, desc.height);
            passData.TargetMipsCount = (int)Mathf.Log(desc.height, 2);

            passData.VarianceDepth = renderGraph.CreateTexture(desc);
            builder.UseTexture(passData.VarianceDepth, AccessFlags.Write);
            varianceDepthData.VarianceDepth = passData.VarianceDepth;
            
            var intermediateDesc = desc;
            intermediateDesc.name = "IntermediateDownsampleBuffer";
            passData.IntermediateDownsampleBuffer = builder.CreateTransientTexture(intermediateDesc);

            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);

                cmd.SetRenderTarget(data.VarianceDepth, 0);
                BlitUtils.BlitTexture(cmd, data.FrameDepth, data.Material, DepthToMomentsPass);
                cmd.GenerateMips(data.VarianceDepth);

                var width = data.TargetResolution.x;
                var height = data.TargetResolution.y;
                for (int mipLevel = 0; mipLevel < data.TargetMipsCount; mipLevel++)
                {
                    cmd.SetRenderTarget(data.IntermediateDownsampleBuffer, mipLevel);
                    cmd.SetGlobalInteger("_InputMipLevel", mipLevel);
                    cmd.SetGlobalVector("_InputTexelSize", new Vector4(1.0f / width, 1.0f / height, width, height));
                    BlitUtils.BlitTexture(cmd, data.VarianceDepth, data.Material, BlurHorizontalPass);

                    cmd.SetRenderTarget(data.VarianceDepth, mipLevel);
                    BlitUtils.BlitTexture(cmd, data.IntermediateDownsampleBuffer, data.Material, BlurVerticalPass);
                    width /= 2;
                    height /= 2;
                }
            });
        }
    }
}
