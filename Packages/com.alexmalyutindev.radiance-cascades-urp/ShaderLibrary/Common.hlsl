#ifndef COMMON_INCLUDED
#define COMMON_INCLUDED

static const half HLF_EPS = 1e-7h;
static const half SQRT3 = sqrt(3.0h);

float4x4 _WorldToView;
float4x4 _ViewToWorld;
float4x4 _ViewToHClip;

inline float2 TransformViewToScreenUV(float3 positionVS)
{
    float4 positionCS = mul(_ViewToHClip, float4(positionVS, 1));
    positionCS.xyz /= positionCS.w;
    positionCS.xy = mad(positionCS.xy, float2(0.5f, 0.5f), float2(0.5f, 0.5f));
    return positionCS.xy;
}

float3 ReconstructPositionVS(float2 uv, float eyeDepth)
{
    float2 ndc = mad(uv, 2.0f, -1.0f);
    return float3(
        ndc.x / _ViewToHClip[0][0],
        ndc.y / _ViewToHClip[1][1],
        1.0f
    ) * eyeDepth;
}

float4 NormalizeWeights(float4 weights)
{
    return saturate(weights / max(0.0001f, dot(weights, float4(1.0f, 1.0f, 1.0f, 1.0f))));
}

float2 LinearEyeDepth(float2 depth, float4 zBufferParam)
{
    return 1.0f / (zBufferParam.z * depth + zBufferParam.w);
}

float3 LinearEyeDepth(float3 depth, float4 zBufferParam)
{
    return 1.0f / (zBufferParam.z * depth + zBufferParam.w);
}

float4 LinearEyeDepth(float4 depth, float4 zBufferParam)
{
    return 1.0f / (zBufferParam.z * depth + zBufferParam.w);
}

#endif
