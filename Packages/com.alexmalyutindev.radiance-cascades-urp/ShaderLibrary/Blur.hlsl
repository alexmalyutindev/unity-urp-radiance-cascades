#ifndef BLUR_INCLUDED
#define BLUR_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

#define SAMPLE_TENT_FUNC(TexType, ElementType) \
ElementType SampleTent( \
    TexType tex, \
    SamplerState sampler_tex, \
    float4 texelSize, \
    int mipLevel, \
    float4 positionCS, \
    float2 radii \
) \
{ \
    float2 invSize = texelSize.xy; \
    int2 r = int2(radii.xy + 0.5); \
    int2 dir = (r.x > r.y) ? int2(1, 0) : int2(0, 1); \
    int radius = max(r.x, r.y); \
    float weightSum = 1e-5; \
    ElementType sum = (ElementType)0; \
    float lod = (float)mipLevel; \
    UNITY_LOOP \
    for (int i = -radius; i <= radius; ++i) \
    { \
        float tent = ((float)radius + 1.0 - (float)abs(i)) / ((float)radius + 1.0); \
        float w = exp((float)(-i * i)) * tent; \
        weightSum += w; \
        float2 uv = invSize * (positionCS.xy + float2(dir * i)); \
        ElementType s = tex.SampleLevel(sampler_tex, uv, lod); \
        sum += abs(s) * (ElementType)w; \
    } \
    return sum / (ElementType)weightSum; \
}

SAMPLE_TENT_FUNC(Texture2D<float4>, float4)
SAMPLE_TENT_FUNC(Texture2D<half4>, half4)
SAMPLE_TENT_FUNC(Texture2D<float2>, float2)
SAMPLE_TENT_FUNC(Texture2D<half2>, half2)
SAMPLE_TENT_FUNC(Texture2D<float>, float)

#endif
