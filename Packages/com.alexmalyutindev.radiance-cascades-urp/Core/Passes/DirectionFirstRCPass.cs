using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

namespace AlexMalyutinDev.RadianceCascades
{
    public class DirectionFirstRCPass : ScriptableRenderPass, IDisposable
    {
        private readonly RadianceCascadesDirectionFirstCS _compute;
        private readonly Material _blitMaterial;

        public DirectionFirstRCPass(RadianceCascadeResources resources)
        {
            profilingSampler = new ProfilingSampler("RadianceCascades.DirectionFirst");
            _compute = new RadianceCascadesDirectionFirstCS(resources.RadianceCascadesDirectionalFirstCS);
            // TODO: Make proper C# wrapper for Blit/Combine shader!
            _blitMaterial = resources.BlitMaterial;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            RenderCascades(renderGraph, frameData, out var cascades, out var sh);
            CombineCascades(renderGraph, frameData, cascades, sh);
        }

        private class PassData
        {
            public RadianceCascadesDirectionFirstCS Compute;
            public float RayLength;

            public Vector2Int ScreenSize;
            public Vector4 Cascade0Size;
            public Vector4 Cascade0ProbesCount;

            public Vector4 CascadesSizeTexel;
            public TextureHandle Cascades;
            public Vector4 RadianceSHSizeTexel;
            public TextureHandle RadianceSH;

            public UniversalCameraData CameraData;

            public TextureHandle FrameDepth;
            public TextureHandle BlurredColor;

            public TextureHandle MinMaxDepth;
            public Vector4 VarianceDepthSizeTexel;
            public TextureHandle VarianceDepth;
        }

        private void RenderCascades(RenderGraph renderGraph, ContextContainer frameData, 
            out TextureHandle radianceCascades, out TextureHandle radianceSH
        )
        {
            var cameraData = frameData.Get<UniversalCameraData>();
            var resourceData = frameData.Get<UniversalResourceData>();

            var minMaxDepthData = frameData.Get<MinMaxDepthData>();
            var varianceDepthData = frameData.Get<VarianceDepthData>();
            var blurredColorData = frameData.Get<BlurredColorData>();

            var settings = VolumeManager.instance.stack.GetComponent<RadianceCascades>();

            using var builder = renderGraph.AddComputePass<PassData>("RC.Render", out var passData);
            builder.AllowPassCulling(false);

            passData.CameraData = cameraData;
            passData.ScreenSize = new Vector2Int(cameraData.scaledWidth, cameraData.scaledHeight);

            passData.RayLength = settings.RayScale.value;

            passData.FrameDepth = resourceData.activeDepthTexture;
            builder.UseTexture(passData.FrameDepth);
            passData.MinMaxDepth = minMaxDepthData.MinMaxDepth;
            builder.UseTexture(passData.MinMaxDepth);

            passData.VarianceDepthSizeTexel = GetSizeTexel(varianceDepthData.VarianceDepth, renderGraph);
            passData.VarianceDepth = varianceDepthData.VarianceDepth;
            builder.UseTexture(passData.VarianceDepth);
            passData.BlurredColor = blurredColorData.BlurredColor;
            builder.UseTexture(passData.BlurredColor);

            passData.Compute = _compute;

            int lastCascadeScale = 2 << 5;
            float lastCascadeScaleRcp = 1.0f / lastCascadeScale;
            int cascade0WidthWithPadding = Mathf.CeilToInt(cameraData.scaledWidth / 4.0f * lastCascadeScaleRcp) * lastCascadeScale;
            int cascade0HeightWithPadding = Mathf.CeilToInt(cameraData.scaledHeight / 4.0f * lastCascadeScaleRcp) * lastCascadeScale;
            passData.Cascade0Size = new Vector4(
                cascade0WidthWithPadding,
                cascade0HeightWithPadding,
                1.0f / cascade0WidthWithPadding,
                1.0f / cascade0HeightWithPadding
            );

            int cascadeWidth = cascade0WidthWithPadding * 8; // 2048;
            int cascadeHeight = cascade0HeightWithPadding * 8; // 1024; 

            int probesCountX = cameraData.scaledWidth / 4;
            int probesCountY = cameraData.scaledHeight / 4;
            passData.Cascade0ProbesCount = new Vector4(probesCountX, probesCountY, 1.0f / probesCountX, 1.0f / probesCountY);

            var desc = new TextureDesc(cascadeWidth, cascadeHeight)
            {
                name = "RadianceCascades",
                format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.ARGBFloat, false),
                enableRandomWrite = true,
                clearBuffer = false, // NOTE: TESTING!!! Remove after!
            };
            passData.CascadesSizeTexel = new Vector4(
                desc.width, desc.height,
                1.0f / desc.width, 1.0f / desc.height
            );
            passData.Cascades = renderGraph.CreateTexture(desc);
            builder.UseTexture(passData.Cascades, AccessFlags.ReadWrite);

            desc.name = "RadianceSH";
            desc.width = cascadeWidth / 2;
            desc.height = cascadeHeight / 2;
            passData.RadianceSHSizeTexel = new Vector4(
                desc.width, desc.height,
                1.0f / desc.width, 1.0f / desc.height
            );
            passData.RadianceSH = renderGraph.CreateTexture(desc);
            builder.UseTexture(passData.RadianceSH, AccessFlags.Write);

            // TODO: Refactor!
            radianceCascades = passData.Cascades;
            radianceSH = passData.RadianceSH;

            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var renderArgs = new RadianceCascadesDirectionFirstCS.RenderMergeArgs
                {
                    CameraData = data.CameraData,
                    Depth = data.FrameDepth,
                    MinMaxDepth = data.MinMaxDepth,
                    VarianceDepth = data.VarianceDepth,
                    VarianceDepthSizeTexel = data.VarianceDepthSizeTexel,
                    BlurredColor = data.BlurredColor,
                    RayScale = data.RayLength,
                    Target = data.Cascades,
                    Cascade0Size = data.Cascade0Size,
                    Cascade0ProbesCount = data.Cascade0ProbesCount,
                    ScreenSize = data.ScreenSize
                };

                data.Compute.RenderMerge(context.cmd, ref renderArgs);

                var combineArgs = new RadianceCascadesDirectionFirstCS.CombineSHArgs
                {
                    CameraData = data.CameraData,
                    Cascades = data.Cascades,
                    CascadesSizeTexel = data.CascadesSizeTexel,
                    MinMaxDepth = data.MinMaxDepth,
                    VarianceDepth = data.VarianceDepth,
                    RadianceSH = data.RadianceSH,
                    CascadeProbesCountWithPadding = data.Cascade0Size,
                    CascadeProbesCount = data.Cascade0ProbesCount
                };

                data.Compute.CombineSH(context.cmd, ref combineArgs);
            });
        }

        private class CombinePassData
        {
            public Material Material;
            public UniversalCameraData CameraData;

            public TextureHandle MinMaxDepth;
            public TextureHandle RadianceCascades;
            public TextureHandle RadianceSH;

            public TextureHandle FrameColor;
            public TextureHandle FrameDepth;
            public TextureHandle FrameNormals;
        }

        private void CombineCascades(RenderGraph renderGraph, ContextContainer frameData, 
            in TextureHandle radianceCascades, in TextureHandle radianceSH
        )
        {
            var cameraData = frameData.Get<UniversalCameraData>();
            var resourceData = frameData.Get<UniversalResourceData>();
            var minMaxDepthData = frameData.Get<MinMaxDepthData>();

            using var builder = renderGraph.AddRasterRenderPass<CombinePassData>("RC.Combine", out var passData);
            builder.AllowGlobalStateModification(true);

            passData.Material = _blitMaterial;
            passData.CameraData = cameraData;

            passData.FrameColor = resourceData.gBuffer[0];
            builder.UseTexture(passData.FrameColor);
            passData.FrameNormals = resourceData.gBuffer[2];
            builder.UseTexture(passData.FrameNormals);
            passData.FrameDepth = resourceData.cameraDepth;
            builder.UseTexture(passData.FrameDepth);

            passData.RadianceCascades = radianceCascades;
            builder.UseTexture(passData.RadianceCascades);
            passData.RadianceSH = radianceSH;
            builder.UseTexture(passData.RadianceSH);

            passData.MinMaxDepth = minMaxDepthData.MinMaxDepth;
            builder.UseTexture(passData.MinMaxDepth);

            builder.SetRenderAttachment(resourceData.activeColorTexture, 0);
            builder.SetRenderFunc<CombinePassData>(static (data, context) =>
            {
                // TEST: Preview cascades blit.
                if (false)
                {
                    BlitUtils.BlitTexture(context.cmd, data.RadianceCascades, data.Material, 5);
                    // BlitUtils.BlitTexture(context.cmd, data.RadianceSH, data.Material, 5);
                }
                else
                {
                    context.cmd.SetGlobalMatrix("_ViewToWorld", data.CameraData.GetViewMatrix().inverse);
                    context.cmd.SetGlobalTexture("_MinMaxDepth", data.MinMaxDepth);

                    context.cmd.SetGlobalTexture("_GBuffer0", data.FrameColor);
                    context.cmd.SetGlobalTexture("_GBuffer2", data.FrameNormals);
                    context.cmd.SetGlobalTexture("_CameraDepthTexture", data.FrameDepth);
                    BlitUtils.BlitTexture(context.cmd, data.RadianceSH, data.Material, 4);
                }
            });
        }

        public void Dispose() { }

        private static Vector4 GetSizeTexel(TextureHandle texture, RenderGraph rg)
        {
            var desc = texture.GetDescriptor(rg);
            return new Vector4(
                desc.width, desc.height,
                1.0f / desc.width, 1.0f / desc.height
            );
        }

        public static Vector4 GetCascade0Size(int targetWidth, int targetHeight)
        {
            int cascade0WidthWithPadding = Mathf.CeilToInt(targetWidth / 4.0f / 16.0f) * 16;
            int cascade0HeightWithPadding = Mathf.CeilToInt(targetHeight / 4.0f / 16.0f) * 16;
            return new Vector4(cascade0WidthWithPadding, cascade0HeightWithPadding);
        }
    }
}
