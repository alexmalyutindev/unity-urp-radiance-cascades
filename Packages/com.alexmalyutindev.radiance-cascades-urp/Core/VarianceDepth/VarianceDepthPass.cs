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
        private static readonly int InputMipLevel = Shader.PropertyToID("_InputMipLevel");
        private static readonly int InputTexelSize = Shader.PropertyToID("_InputTexelSize");
        private static readonly int BlurDirection = Shader.PropertyToID("_BlurDirection");

        private const int DepthToMomentsPass = 0;
        private const int BlurHorizontalPass = 1;
        private const int BlurVerticalPass = 2;
        private const int BlurDirectionalPass = 3;
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

            var desc = new TextureDesc(frameDesc.width, frameDesc.height)
            {
                name = "VarianceDepth",
                colorFormat = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.ARGBFloat, false),
                wrapMode = TextureWrapMode.Clamp,
                filterMode = FilterMode.Bilinear,
                useMipMap = true,
                autoGenerateMips = false,
            };
            passData.TargetResolution = new Vector2Int(desc.width, desc.height);
            passData.TargetMipsCount = Mathf.Max(1, (int)Mathf.Log(desc.height, 2) - 1);

            passData.VarianceDepth = renderGraph.CreateTexture(desc);
            builder.UseTexture(passData.VarianceDepth, AccessFlags.Write);
            varianceDepthData.VarianceDepth = passData.VarianceDepth;
            
            var intermediateDesc = desc;
            intermediateDesc.name = "IntermediateDownsampleBuffer";
            passData.IntermediateDownsampleBuffer = builder.CreateTransientTexture(intermediateDesc);

            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
                var width = data.TargetResolution.x;
                var height = data.TargetResolution.y;

                cmd.SetRenderTarget(data.VarianceDepth, 0);
                BlitUtils.BlitTexture(cmd, data.FrameDepth, data.Material, DepthToMomentsPass);
                cmd.GenerateMips(data.VarianceDepth);

                for (int mipLevel = 0; mipLevel < data.TargetMipsCount; mipLevel++)
                {
                    cmd.SetGlobalVector(InputTexelSize, new Vector4(1.0f / width, 1.0f / height, width, height));

                    cmd.SetGlobalVector(BlurDirection, new Vector4(1.0f, 0.0f));

                    cmd.SetRenderTarget(data.IntermediateDownsampleBuffer, mipLevel);
                    cmd.SetGlobalInteger(InputMipLevel, mipLevel);
                    BlitUtils.BlitTexture(cmd, data.VarianceDepth, data.Material, BlurDirectionalPass);

                    cmd.SetGlobalVector(BlurDirection, new Vector4(0.0f, 1.0f));

                    cmd.SetRenderTarget(data.VarianceDepth, mipLevel);
                    cmd.SetGlobalInteger(InputMipLevel, mipLevel);
                    BlitUtils.BlitTexture(cmd, data.IntermediateDownsampleBuffer, data.Material, BlurDirectionalPass);
                    width /= 2;
                    height /= 2;
                }
            });
        }
    }
}
