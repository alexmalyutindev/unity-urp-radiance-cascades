using UnityEngine;

namespace AlexMalyutinDev.RadianceCascades
{
    public static class ShaderIds
    {
        public static readonly int CascadeLevel = Shader.PropertyToID("_CascadeLevel");
        public static readonly int CascadeSize = Shader.PropertyToID("_CascadeSize");
        public static readonly int ProbesCount = Shader.PropertyToID("_ProbesCount");

        public static readonly int CascadeBufferSize = Shader.PropertyToID("_CascadeBufferSize");
        public static readonly int NextCascadeLevel = Shader.PropertyToID("_LowerCascadeLevel");

        public static readonly int SceneColor = Shader.PropertyToID("_SceneColor");
        public static readonly int SceneDepth = Shader.PropertyToID("_SceneDepth");
        public static readonly int NormalsTexture = Shader.PropertyToID("_NormalsTexture");
        public static readonly int GBuffer3 = Shader.PropertyToID("_GBuffer3");

        public static readonly int MinMaxDepth = Shader.PropertyToID("_MinMaxDepth");
        public static readonly int SmoothedDepth = Shader.PropertyToID("_SmoothedDepth");
        public static readonly int VarianceDepth = Shader.PropertyToID("_VarianceDepth");
        public static readonly int BlurredColor = Shader.PropertyToID("_BlurredColor");
    }
}
