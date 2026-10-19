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
    float raysPerLayer = 4.0f * exp2(cascadeLevel);

    // Azimuth: same formula as the tracer (deltaPhi = TWO_PI / raysPerLayer).
    float phi = (angleId.x + 0.5f) * (TWO_PI / raysPerLayer);

    // Polar: center of the equal-area slab. Sector 0 = toward the camera = +z in Unity VS.
    float cosTheta = 0.75f - 0.5f * angleId.y;      // 0.75, 0.25, -0.25, -0.75
    float sinTheta = sqrt(saturate(1.0f - cosTheta * cosTheta));

    float sinPhi, cosPhi;
    sincos(phi, sinPhi, cosPhi);

    return float3(sinTheta * cosPhi, sinTheta * sinPhi, cosTheta);
}

float3 GetRayDirectionWS(float2 angleId, float cascadeLevel)
{
    return mul(_ViewToWorld, float4(GetRayDirectionVS(angleId, cascadeLevel), 0.0f));
}

#endif
