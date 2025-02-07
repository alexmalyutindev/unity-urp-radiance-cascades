using UnityEngine;
using UnityEngine.Rendering;

namespace AlexMalyutinDev.RadianceCascades
{
    [VolumeComponentMenu(nameof(AlexMalyutinDev) + "/" + nameof(AlexMalyutinDev.RadianceCascades))]
    public sealed class RadianceCascades : VolumeComponent
    {
        public VolumeParameter<RenderingType> RenderingType = new();

        [Header("Direction First")]
        public ClampedFloatParameter RayScale = new ClampedFloatParameter(0.1f, 0.01f, 2.0f);
        public BoolParameter UseSH = new BoolParameter(false, BoolParameter.DisplayType.EnumPopup);
    }
}
