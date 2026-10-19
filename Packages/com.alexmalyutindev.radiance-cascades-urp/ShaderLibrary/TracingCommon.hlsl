#ifndef TRACING_COMMON_INCLUDED
#define TRACING_COMMON_INCLUDED

#include "Packages/com.alexmalyutindev.radiance-cascades-urp/ShaderLibrary/Common.hlsl"

struct IntegrationSector
{
    half4x4 transmittance;
    half4x4 color;
};

float3 GetRayDirectionVS(float2 angleId, float cascadeLevel)
{
    float deltaPhi = TWO_PI * pow(0.5f, cascadeLevel) * 0.25f; // 1/4
    static const float deltaTheta = PI * 0.25f;
    // Azimuth
    float phi = (angleId.x + 0.5f) * deltaPhi;
    // Polar
    float theta = (angleId.y + 0.5f) * deltaTheta;

    float2 sinCosPhi;
    float2 sinCosTheta;
    sincos(phi, sinCosPhi.x, sinCosPhi.y);
    sincos(theta, sinCosTheta.x, sinCosTheta.y);

    float3 ray = normalize(float3(sinCosTheta.x * sinCosPhi.y, sinCosTheta.x * sinCosPhi.x, sinCosTheta.y));
    return ray;
}

float3 GetRayDirectionWS(float2 angleId, float cascadeLevel)
{
    return mul(_ViewToWorld, float4(GetRayDirectionVS(angleId, cascadeLevel), 0.0f));
}

#endif
