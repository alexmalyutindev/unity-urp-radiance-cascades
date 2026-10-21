#ifndef TRAPEZOID_INTEGRATION
#define TRAPEZOID_INTEGRATION

#include "Packages/com.alexmalyutindev.radiance-cascades-urp/ShaderLibrary/TracingCommon.hlsl"

struct Trapezoid
{
    float median;
    float constHalfSize;
    float linHalfSize;
    float height;
};

// Builds a trapezoid-shaped opacity function from an interval [minmax.x, minmax.y] offset by a uniformly
// distributed function with variance = sigma^2
Trapezoid GetVarianceTrapezoid(half2 minMax, half sigma0)
{
    Trapezoid result;
    float halfRange = SQRT3 * sigma0;
    float halfSize = (minMax.y - minMax.x) * 0.5f;
    result.median = 0.5f * (minMax.x + minMax.y);
    result.constHalfSize = abs(halfSize - halfRange);
    result.linHalfSize = max(HLF_EPS, halfSize + halfRange - result.constHalfSize);
    result.height = min(1.0f, halfSize / max(HLF_EPS, halfRange));
    return result;
}

//Integral [0..x] t dt
float LinearIntegral(float x)
{
    return x * x * 0.5f;
}

//Integral [0..x] trapezoid(t) dt
float IntegrateTrapezoid(Trapezoid trapezoid, half x)
{
    half constRange = min(abs(x - trapezoid.median), trapezoid.constHalfSize + trapezoid.linHalfSize);
    half linRange = max(0.0f, constRange - trapezoid.constHalfSize);
    half constInt = constRange;
    half linInt = -LinearIntegral(linRange) / trapezoid.linHalfSize;
    return (x > trapezoid.median ? 1.0f : -1.0f) * trapezoid.height * (constInt + linInt);
}

IntegrationSector PrepareSector(float2 probeMinMaxDepth, float2 depthMoments, float cascadePower)
{
    const float4 directLight = float4(0.0f, 0.0f, 0.0f, -1.0f);

    IntegrationSector sector;
    sector.transmittance = 1.0h;
    sector.color = float4x4(
        half4(0.0h, 0.0h, 0.0h, 1.0h),
        half4(0.0h, 0.0h, 0.0h, 1.0h),
        half4(0.0h, 0.0h, 0.0h, 1.0h),
        half4(0.0h, 0.0h, 0.0h, 1.0h)
    );

#ifdef SELF_OCCLUSION
    // TODO: Self occlusion!
    half sigma = sqrt(max(0.0f, depthMoments.y - depthMoments.x * depthMoments.x)) * 100.0f;
    // half2 minMax = float2(step(probeMinMaxDepth.x, depthMoments.x), 1.0h);
    half2 minMax = float2(0.5h, 1.0h);

    Trapezoid trapezoid = GetVarianceTrapezoid(minMax, sigma);

    half prevOcclusion = IntegrateTrapezoid(trapezoid, 0.0f);

    UNITY_UNROLL
    for (uint rayId = 0; rayId < 16; rayId++)
    {
        half alpha = (rayId + 1.0f) * (1.0f / 16.0f);

        int groupId = rayId / 4;
        int subRayId = rayId % 4;

        half occlusion = IntegrateTrapezoid(trapezoid, alpha);
        half transmittance = saturate(pow(saturate(1.0f - (occlusion - prevOcclusion) * 16.0f), cascadePower));
        prevOcclusion = occlusion;

        half currentTransmittance = sector.transmittance[groupId][subRayId];
        sector.color[groupId] += directLight * currentTransmittance * saturate(1.0f - transmittance) * 0.25h;
        sector.transmittance[groupId][subRayId] *= saturate(transmittance);
    }
#endif

    return sector;
}


void IntegrateDepthSector(
    float3 probeNormalVS, float3 probeCenterVS,
    float3 occluderMeanVS, float3 occluderFarVS, float3 occluderThickVS,
    half4 directLight,
    half sharpness,
    inout IntegrationSector sector
)
{
    //  mean  far
    //    /  ╱ 
    //   / ╱
    //  /╱
    // /⎽⎽⎼⎼⎼⎻⎻⎻⎺⎺⎺ thick
    // 0 ------------> 1
    float meanAngle = dot(probeNormalVS, normalize(occluderMeanVS - probeCenterVS)) * 0.5f + 0.5f;
    float farAngle = dot(probeNormalVS, normalize(occluderFarVS - probeCenterVS)) * 0.5f + 0.5f;
    float thickAngle = dot(probeNormalVS, normalize(occluderThickVS - probeCenterVS)) * 0.5f + 0.5f;
    float sigma = max(HLF_EPS, farAngle - meanAngle);

    Trapezoid trapezoid = GetVarianceTrapezoid(half2(farAngle, thickAngle), sigma);

    half prevOcclusion = IntegrateTrapezoid(trapezoid, 0.0f);

    UNITY_UNROLL
    for (uint rayId = 0; rayId < 16; rayId++)
    {
        half alpha = (rayId + 1.0f) * (1.0f / 16.0f);

        int groupId = rayId / 4;
        int subRayId = rayId % 4;

        half occlusion = IntegrateTrapezoid(trapezoid, alpha);
        half transmittance = saturate(pow(saturate(1.0f - (occlusion - prevOcclusion) * 16.0f), sharpness));
        // half transmittance = saturate(1.0f - (occlusion - prevOcclusion) * 16.0f);
        prevOcclusion = occlusion;

        half currentTransmittance = sector.transmittance[groupId][subRayId];
        sector.color[groupId] += directLight * currentTransmittance * saturate(1.0f - transmittance) * 0.25h;
        sector.transmittance[groupId][subRayId] *= saturate(transmittance);
    }
}

#endif
