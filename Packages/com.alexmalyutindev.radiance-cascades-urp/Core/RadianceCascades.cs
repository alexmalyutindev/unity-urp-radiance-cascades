using UnityEngine.Rendering;

namespace AlexMalyutinDev.RadianceCascades
{
    [VolumeComponentMenu(nameof(AlexMalyutinDev) + "/" + nameof(AlexMalyutinDev.RadianceCascades))]
    public sealed class RadianceCascades : VolumeComponent
    {
        public VolumeParameter<RenderingType> RenderingType = new();
        public ClampedFloatParameter UpsampleTolerance = new(0.1f, 0.0001f, 0.1f);
        public ClampedFloatParameter NoiseFilterStrength = new(0.1f, 0.0f, 1.0f);
    }
}
