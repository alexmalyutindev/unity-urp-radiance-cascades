using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

namespace AlexMalyutinDev.RadianceCascades
{
    public class MinMaxDepthData : ContextItem
    {
        public TextureHandle MinMaxDepth;

        public override void Reset()
        {
            MinMaxDepth = TextureHandle.nullHandle;
        }
    }

    public class MinMaxDepthPass : ScriptableRenderPass, IDisposable
    {
        private const int MinMaxOriginalDepthPass = 0;
        private const int MinMaxDepthMipPass = 1;
        private const int CopyLevelPass = 2;
        private const int DepthToMinMaxDepth = 3;

        private static readonly int InputMipLevelId = Shader.PropertyToID("_InputMipLevel");
        private static readonly int TargetResolutionId = Shader.PropertyToID("_TargetResolution");
        private static readonly int InputResolutionId = Shader.PropertyToID("_InputResolution");
        private static readonly int ScaleId = Shader.PropertyToID("_Scale");

        private readonly Material _material;
        private readonly RadianceCascadesRenderingData _renderingData;

        public MinMaxDepthPass(Material minMaxDepthMaterial, RadianceCascadesRenderingData renderingData)
        {
            profilingSampler = new ProfilingSampler(nameof(MinMaxDepthPass));
            _material = minMaxDepthMaterial;
            _renderingData = renderingData;
        }

        private class PassData
        {
            public TextureHandle MinMaxDepth;
            public TextureHandle IntermediateDownsampleBuffer;

            public TextureHandle FrameDepth;
            public Material Material;

            public Vector4 InputResolution;
            public Vector4 TargetResolution;
            public int TargetMipsCount;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var cameraData = frameData.Get<UniversalCameraData>();
            var resourceData = frameData.Get<UniversalResourceData>();
            var minMaxDepthData = frameData.Create<MinMaxDepthData>();

            var frameDesc = cameraData.cameraTargetDescriptor;

            using var builder = renderGraph.AddUnsafePass<PassData>(nameof(MinMaxDepthPass), out var passData);
            builder.AllowPassCulling(false);

            passData.Material = _material;

            passData.InputResolution = new Vector4(frameDesc.width, frameDesc.height);
            passData.FrameDepth = resourceData.activeDepthTexture;
            builder.UseTexture(passData.FrameDepth);

            var targetWidth = 4 * _renderingData.Cascade0Size.x;
            var targetHeight = 4 * _renderingData.Cascade0Size.y;
            passData.TargetResolution = new Vector4(targetWidth, targetHeight);
            passData.TargetMipsCount = (int)Mathf.Log(targetHeight, 2);

            var desc = new TextureDesc(targetWidth, targetHeight)
            {
                name = "MinMaxDepth",
                colorFormat = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.RGFloat, false),
                wrapMode = TextureWrapMode.Clamp,
                filterMode = FilterMode.Point,
                useMipMap = true,
                autoGenerateMips = false
            };
            passData.MinMaxDepth = renderGraph.CreateTexture(desc);
            builder.UseTexture(passData.MinMaxDepth, AccessFlags.ReadWrite);
            minMaxDepthData.MinMaxDepth = passData.MinMaxDepth;

            if (SystemInfo.graphicsDeviceType is not (GraphicsDeviceType.Metal or GraphicsDeviceType.Vulkan))
            {
                desc.name = "Temp";
                desc.width >>= 1;
                desc.height >>= 1;
                desc.useMipMap = false;
                passData.IntermediateDownsampleBuffer = builder.CreateTransientTexture(desc);
            }

            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);

                cmd.SetRenderTarget(data.MinMaxDepth, 0, CubemapFace.Unknown);
                cmd.SetGlobalInteger(InputMipLevelId, 0);
                cmd.SetGlobalFloat(ScaleId, 1);
                cmd.SetGlobalVector(TargetResolutionId, data.TargetResolution);
                cmd.SetGlobalVector(InputResolutionId, data.InputResolution);
                // BlitUtils.BlitTexture(cmd, data.FrameDepth, data.Material, DepthToMinMaxDepth);
                BlitUtils.BlitTexture(cmd, data.FrameDepth, data.Material, MinMaxOriginalDepthPass);

                var width = (int)data.TargetResolution.x;
                var height = (int)data.TargetResolution.y;
                for (int mipLevel = 1; mipLevel < data.TargetMipsCount; mipLevel++)
                {
                    cmd.SetGlobalVector(InputResolutionId, new Vector4(width, height));

                    if (SystemInfo.graphicsDeviceType is GraphicsDeviceType.Metal or GraphicsDeviceType.Vulkan)
                    {
                        cmd.SetGlobalInteger(InputMipLevelId, mipLevel - 1);
                        cmd.SetRenderTarget(data.MinMaxDepth, mipLevel);
                        BlitUtils.BlitTexture(cmd, data.MinMaxDepth, data.Material, MinMaxDepthMipPass);
                    }
                    else
                    {
                        // BUG: Incorrect MinMax values, smth with sample coords.
                        cmd.SetRenderTarget(data.IntermediateDownsampleBuffer);
                        cmd.EnableScissorRect(new Rect(0, 0, width, height));
                        cmd.SetGlobalInteger(InputMipLevelId, mipLevel - 1);
                        cmd.SetGlobalFloat(ScaleId, 1 << (mipLevel - 1));
                        BlitUtils.BlitTexture(cmd, data.MinMaxDepth, data.Material, MinMaxDepthMipPass);
                        cmd.DisableScissorRect();

                        cmd.SetRenderTarget(data.MinMaxDepth, mipLevel);
                        BlitUtils.BlitTexture(cmd, data.IntermediateDownsampleBuffer, data.Material, CopyLevelPass);
                    }

                    width = Mathf.FloorToInt(width / 2.0f);
                    height = Mathf.FloorToInt(height / 2.0f);
                }
            });
        }

        public void Dispose() { }
    }
}
