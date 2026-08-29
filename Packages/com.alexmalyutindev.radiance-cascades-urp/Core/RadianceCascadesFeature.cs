using AlexMalyutinDev.RadianceCascades.SmoothedDepth;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace AlexMalyutinDev.RadianceCascades
{
    public class RadianceCascadesFeature : ScriptableRendererFeature
    {
        public RadianceCascadeResources Resources;

        private RadinceCascadesPass _radinceCascadesPass;

        private MinMaxDepthPass _minMaxDepthPass;
        private SmoothedDepthPass _smoothedDepthPass;
        private VarianceDepthPass _varianceDepthPass;
        private BlurredColorBufferPass _blurredColorBufferPass;

        private RadianceCascadesRenderingData _radianceCascadesRenderingData;

        public override void Create()
        {
            _radianceCascadesRenderingData = new RadianceCascadesRenderingData();

            _minMaxDepthPass = new MinMaxDepthPass(Resources.MinMaxDepthMaterial, _radianceCascadesRenderingData)
            {
                renderPassEvent = RenderPassEvent.AfterRenderingGbuffer
            };
            _smoothedDepthPass = new SmoothedDepthPass(Resources.SmoothedDepthMaterial, _radianceCascadesRenderingData)
            {
                renderPassEvent = RenderPassEvent.AfterRenderingGbuffer
            };
            _varianceDepthPass = new VarianceDepthPass(Resources.VarianceDepthMaterial, _radianceCascadesRenderingData)
            {
                renderPassEvent = RenderPassEvent.AfterRenderingGbuffer
            };
            _blurredColorBufferPass = new BlurredColorBufferPass(
                Resources.BlurredColorBufferMaterial,
                _radianceCascadesRenderingData
            )
            {
                renderPassEvent = RenderPassEvent.AfterRenderingDeferredLights
            };
            _radinceCascadesPass = new RadinceCascadesPass(Resources)
            {
                renderPassEvent = RenderPassEvent.AfterRenderingDeferredLights,
            };
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (renderingData.cameraData.isPreviewCamera) return;

            var volume = VolumeManager.instance.stack.GetComponent<RadianceCascades>();
            if (!volume.active) return;

            // TODO: Refactor render target size! Only used in MinMaxDepthPass and BlurredColorBufferPass!
            var targetWidth = renderingData.cameraData.cameraTargetDescriptor.width;
            var targetHeight = renderingData.cameraData.cameraTargetDescriptor.height;

            var cascade0Size = RadinceCascadesPass.GetCascade0Size(targetWidth, targetHeight);
            _radianceCascadesRenderingData.Cascade0Size = new Vector2Int(
                Mathf.FloorToInt(cascade0Size.x / 2), 
                Mathf.FloorToInt(cascade0Size.y / 2)
            );

            renderer.EnqueuePass(_minMaxDepthPass);
            renderer.EnqueuePass(_varianceDepthPass);
            renderer.EnqueuePass(_blurredColorBufferPass);
            renderer.EnqueuePass(_radinceCascadesPass);
        }

        protected override void Dispose(bool disposing)
        {
            _minMaxDepthPass?.Dispose();
            _radinceCascadesPass?.Dispose();
        }
    }
}
