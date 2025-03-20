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
                cameraTextureDescriptor.width >> 1,
                cameraTextureDescriptor.height >> 1
            )
            {
                colorFormat = RenderTextureFormat.RGFloat,
                depthStencilFormat = GraphicsFormat.None,
                useMipMap = false,
                autoGenerateMips = false,
            };
            RenderingUtils.ReAllocateIfNeeded(
                ref _radianceCascadesRenderingData.VarianceDepth,
                desc,
                FilterMode.Point,
                TextureWrapMode.Clamp,
                name: "VarianceDepth"
            );
            RenderingUtils.ReAllocateIfNeeded(
                ref _tempBuffer,
                desc,
                FilterMode.Point,
                TextureWrapMode.Clamp,
                name: "Temp"
            );
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            // TODO: VarianceDepth
            // - Make VarianceDepth mip chain
            // - Blur VarianceDepth
            if (_material == null) return;

            var cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, profilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                var depthBuffer = renderingData.cameraData.renderer.cameraDepthTargetHandle;
                cmd.SetRenderTarget(_radianceCascadesRenderingData.VarianceDepth);
                BlitUtils.BlitTexture(cmd, depthBuffer, _material, DepthToMomentsPass);
                cmd.SetRenderTarget(_tempBuffer);
                BlitUtils.BlitTexture(cmd, _radianceCascadesRenderingData.VarianceDepth, _material, BlurVerticalPass);
                cmd.SetRenderTarget(_radianceCascadesRenderingData.VarianceDepth);
                BlitUtils.BlitTexture(cmd, _tempBuffer, _material, BlurHorizontalPass);
            }

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }
    }
}
