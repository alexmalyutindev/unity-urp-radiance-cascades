using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace AlexMalyutinDev.RadianceCascades.VarianceDepth
{
    public class VarianceDepthPass : ScriptableRenderPass
    {
        private const int DepthToMomentsPass = 0;
        private const int BlurVerticalPass = 1;
        private const int BlurHorizontalPass = 2;
        private readonly Material _material;
        private readonly RadianceCascadesRenderingData _radianceCascadesRenderingData;
        private RTHandle _tempBuffer;

        public VarianceDepthPass(
            Material material,
            RadianceCascadesRenderingData radianceCascadesRenderingData
        )
        {
            profilingSampler = new ProfilingSampler(nameof(VarianceDepthPass));
            _material = material;
            _radianceCascadesRenderingData = radianceCascadesRenderingData;
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            var desc = new RenderTextureDescriptor(
                cameraTextureDescriptor.width / 2,
                cameraTextureDescriptor.height / 2
            )
            {
                colorFormat = RenderTextureFormat.RGFloat,
                depthStencilFormat = GraphicsFormat.None,
                useMipMap = true,
                autoGenerateMips = false,
            };
            RenderingUtils.ReAllocateIfNeeded(
                ref _radianceCascadesRenderingData.VarianceDepth,
                desc,
                FilterMode.Bilinear,
                TextureWrapMode.Clamp,
                name: "VarianceDepth"
            );
            RenderingUtils.ReAllocateIfNeeded(
                ref _tempBuffer,
                desc,
                FilterMode.Bilinear,
                TextureWrapMode.Clamp,
                name: "Temp"
            );
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (_material == null) return;

            // TODO: Add VarianceDepth mip-chain!
            var cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, profilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                var depthBuffer = renderingData.cameraData.renderer.cameraDepthTargetHandle;
                cmd.SetRenderTarget(_radianceCascadesRenderingData.VarianceDepth);
                BlitUtils.BlitTexture(cmd, depthBuffer, _material, DepthToMomentsPass);
                cmd.GenerateMips(_radianceCascadesRenderingData.VarianceDepth);

                int width = _radianceCascadesRenderingData.VarianceDepth.rt.width;
                int height = _radianceCascadesRenderingData.VarianceDepth.rt.height;
                for (int mipLevel = 0; mipLevel < _radianceCascadesRenderingData.VarianceDepth.rt.mipmapCount; mipLevel++)
                {
                    cmd.SetGlobalInteger("_InputMipLevel", mipLevel);
                    cmd.SetGlobalVector("_InputTexelSize", new Vector4(1.0f / width, 1.0f / height, width, width));

                    cmd.SetRenderTarget(_tempBuffer, mipLevel);
                    BlitUtils.BlitTexture(cmd, _radianceCascadesRenderingData.VarianceDepth, _material, BlurVerticalPass);
                    
                    cmd.SetRenderTarget(_radianceCascadesRenderingData.VarianceDepth, mipLevel);
                    BlitUtils.BlitTexture(cmd, _tempBuffer, _material, BlurHorizontalPass);
                    
                    width /= 2;
                    height /= 2;
                }

                // cmd.SetRenderTarget(_tempBuffer);
                // BlitUtils.BlitTexture(cmd, _radianceCascadesRenderingData.VarianceDepth, _material, BlurVerticalPass);
                // cmd.SetRenderTarget(_radianceCascadesRenderingData.VarianceDepth);
                // BlitUtils.BlitTexture(cmd, _tempBuffer, _material, BlurHorizontalPass);
            }

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }
    }
}
