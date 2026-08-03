using System.Reflection;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace InternalBridge
{
    // TODO: Move to shared!
    public static class UniversalRendererInternal
    {
        private static FieldInfo m_OpaqueColor = typeof(UniversalRenderer).GetField(
            "m_OpaqueColor",
            BindingFlags.NonPublic | BindingFlags.Instance
        );

        // public static RTHandle GetDepthTexture(this UniversalRenderer renderer)
        // {
        //     return renderer.m_DepthTexture;
        // }

        // TODO: Use with [UnsafeAccessor] when Unity start supporting .NET8
        public static RTHandle GetOpaqueTexture(this ScriptableRenderer renderer)
        {
            return (RTHandle) m_OpaqueColor.GetValue(renderer);
        }
        
        // TODO: Use with [UnsafeAccessor] when Unity start supporting .NET8
        public static RTHandle GetGBuffer(this ScriptableRenderer renderer, int index)
        {
            if (renderer is UniversalRenderer r)
            {
                return r.deferredLights.GbufferAttachments[index];
            }
            return null;
        }
    }
}
