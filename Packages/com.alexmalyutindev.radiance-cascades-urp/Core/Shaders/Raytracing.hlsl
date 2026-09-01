#ifndef DEPTH_MOMENTS_TRACING
#define DEPTH_MOMENTS_TRACING

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Common.hlsl"
#include "SoftCoverage.hlsl"

static const half HLF_EPS = 1e-7h;
static const half SQRT3 = sqrt(3.0h);

struct Trapezoid
{
    half median;
    half constHalfSize;
    half linHalfSize;
    half height;
};

// Builds a trapezoid-shaped opacity function from an interval [minmax.x, minmax.y] offset by a uniformly
// distributed function with variance = sigma^2
Trapezoid GetVarianceTrapezoid(half2 minMax, half sigma0)
{
    Trapezoid result;
    half halfRange = SQRT3 * sigma0;
    half halfSize = (minMax.y - minMax.x) * 0.5f;
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
    return sector;

    // TODO: Self occlusion!
    half sigma = sqrt(max(0.0f, depthMoments.y - depthMoments.x * depthMoments.x));
    half2 minMax = float2(step(probeMinMaxDepth.x, depthMoments.x), 1.0h);

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

    return sector;
}

//////////////
/// ACTUAL ///
//////////////

void IntegrateDepthSector(
    float3 probeNormalVS, float3 probeCenterVS,
    float3 occluderMeanVS, float3 occluderUpperVS, float3 occluderThickVS,
    half4 directLight,
    half sharpness,
    inout IntegrationSector sector
)
{
    half meanAngle = dot(probeNormalVS, normalize(occluderMeanVS - probeCenterVS)) * 0.5f + 0.5f;
    half upperAngle = dot(probeNormalVS, normalize(occluderUpperVS - probeCenterVS)) * 0.5f + 0.5f;
    half thickAngle = dot(probeNormalVS, normalize(occluderThickVS - probeCenterVS)) * 0.5f + 0.5f;
    half sigma = max(HLF_EPS, meanAngle - upperAngle);

    Trapezoid trapezoid = GetVarianceTrapezoid(half2(upperAngle, 1.0h + sigma), sigma);

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

float2 GetDepthMoments(float2 uv);
float3 GetSceneLighting(float2 uv);

half4 RayTracing_TrapezoidIntegration(
    float2 probeMinMaxDepth,
    float2 probeCenterUV,
    float2 rayDirection,
    float2 range,
    half cascadePower,
    out half4x4 nearSectorRadiance,
    out half4x4 farSectorRadiance
)
{
    const float depthThickness = 40.0f;
    const float stepSize = _RayScale;

    float2 depthMoments = GetDepthMoments(probeCenterUV);

    IntegrationSector integrationSector[2];
    integrationSector[0] = PrepareSector(probeMinMaxDepth, depthMoments, cascadePower);
    integrationSector[1] = integrationSector[0];

    float3 probeViewDirectionVS = ReconstructPositionVS(probeCenterUV, 1.0f);
    float3 probeNormalVS = normalize(probeViewDirectionVS);

    float3 probeCenterVS[2];
    probeCenterVS[0] = probeViewDirectionVS * probeMinMaxDepth.x;
    probeCenterVS[1] = probeViewDirectionVS * probeMinMaxDepth.y;

    float2 directionUV = stepSize * rayDirection;

    UNITY_LOOP
    for (float rayStep = range.x; rayStep < range.y; rayStep += 1.0f)
    {
        float2 rayUV = probeCenterUV + rayStep * directionUV;

        if (any(rayUV > 1.0f || rayUV < 0.0f)) break;

        float2 depthMoments = GetDepthMoments(rayUV);
        float4 directLight = float4(GetSceneLighting(rayUV), -1.0f);

        float3 viewDirectionVS = ReconstructPositionVS(rayUV, 1.0f);

        float upperDepth = depthMoments.x + sqrt(max(0.0f, depthMoments.y - depthMoments.x * depthMoments.x));
        float3 occluderMeanVS = viewDirectionVS * depthMoments.x;
        float3 occluderUpperVS = viewDirectionVS * upperDepth;
        float3 occluderThickVS = viewDirectionVS * (depthMoments.x + depthThickness);

        UNITY_UNROLL
        for (uint sectorId = 0u; sectorId < 2u; sectorId++)
        {
            IntegrateDepthSector(
                probeNormalVS, probeCenterVS[sectorId],
                occluderMeanVS, occluderUpperVS, occluderThickVS,
                directLight,
                cascadePower,
                integrationSector[sectorId]
            );
        }
    }

    nearSectorRadiance = integrationSector[0].color;
    farSectorRadiance = integrationSector[1].color;
    return 0.0f;
}

half4 RayTracing_SoftBins(
    float2 probeMinMaxDepth,
    float2 probeCenterUV,
    float2 rayDirection,
    float2 range,
    float4 outputSizeTexel,
    float cascadePower,
    out half4x4 nearSectorRadiance,
    out half4x4 farSectorRadiance
)
{
    const float depthThickness = 40.0f;
    const float stepSize = _RayScale;

    IntegrationSector minSector;
    minSector.transmittance = 1.0h;
    minSector.color = float4x4(
        half4(0.0h, 0.0h, 0.0h, 1.0h),
        half4(0.0h, 0.0h, 0.0h, 1.0h),
        half4(0.0h, 0.0h, 0.0h, 1.0h),
        half4(0.0h, 0.0h, 0.0h, 1.0h)
    );
    IntegrationSector maxSector = minSector;

    float3 probeViewDirectionVS = ReconstructPositionVS(probeCenterUV, 1.0f);
    float3 probeNormalVS = normalize(probeViewDirectionVS);

    float3 minProbeCenterVS = probeViewDirectionVS * probeMinMaxDepth.x;
    float3 maxProbeCenterVS = probeViewDirectionVS * probeMinMaxDepth.y;

    float2 directionUV = stepSize * rayDirection * outputSizeTexel.zw;

    UNITY_LOOP
    for (float rayStep = range.x; rayStep < range.y; rayStep += 1.0f)
    {
        float2 rayUV = probeCenterUV + (rayStep + 0.5f) * directionUV;

        if (any(rayUV > 1.0f || rayUV < 0.0f)) break;

        float2 depthMoments = GetDepthMoments(rayUV);
        float4 directLight = float4(GetSceneLighting(rayUV), -1.0f);

        float3 viewDirectionVS = ReconstructPositionVS(rayUV, 1.0f);

        float meanDepth = depthMoments.x + sqrt(max(0.0f, depthMoments.y - depthMoments.x * depthMoments.x));

        {
            float3 occluderNearVS = viewDirectionVS * depthMoments.x;
            float3 occluderFarVS = viewDirectionVS * (depthMoments.x + depthThickness);
            float3 occluderMeanVS = viewDirectionVS * meanDepth;

            float binNear = dot(probeNormalVS, normalize(occluderNearVS - minProbeCenterVS)) * 0.5f + 0.5f;
            float binVarFar = dot(probeNormalVS, normalize(occluderMeanVS - minProbeCenterVS)) * 0.5f + 0.5f;
            float binThick = dot(probeNormalVS, normalize(occluderFarVS - minProbeCenterVS)) * 0.5f + 0.5f;

            float curveTerm = SQRT3 * (binNear - binVarFar);
            float halfRange = (binNear - binThick) * 0.5;
            float sumRange  = binThick + binNear;
            float binCenter = sumRange * 0.5;
            float distConst = abs(halfRange - curveTerm);
            float invCurve  = max(FLT_EPS, (halfRange + curveTerm) - distConst);
            float rampSlope = min(1.0, halfRange / max(FLT_EPS, curveTerm));

            AccumulateSoftBins(minSector, directLight, binCenter, distConst, invCurve, rampSlope, cascadePower);
        }

        {
            float3 occluderNearVS = viewDirectionVS * depthMoments.x;
            float3 occluderFarVS = viewDirectionVS * (depthMoments.x + depthThickness);
            float3 occluderMeanVS = viewDirectionVS * meanDepth;

            float binNear = dot(probeNormalVS, normalize(occluderNearVS - maxProbeCenterVS)) * 0.5f + 0.5f;
            float binVarFar = dot(probeNormalVS, normalize(occluderMeanVS - maxProbeCenterVS)) * 0.5f + 0.5f;
            float binThick = dot(probeNormalVS, normalize(occluderFarVS - maxProbeCenterVS)) * 0.5f + 0.5f;

            float curveTerm = SQRT3 * (binNear - binVarFar);
            float halfRange = (binNear - binThick) * 0.5;
            float sumRange  = binThick + binNear;
            float binCenter = sumRange * 0.5;
            float distConst = abs(halfRange - curveTerm);
            float invCurve  = max(FLT_EPS, (halfRange + curveTerm) - distConst);
            float rampSlope = min(1.0, halfRange / max(FLT_EPS, curveTerm));

            AccumulateSoftBins(maxSector, directLight, binCenter, distConst, invCurve, rampSlope, cascadePower);
        }
    }

    nearSectorRadiance = minSector.color;
    farSectorRadiance = maxSector.color;
    return float4(maxProbeCenterVS, 0.0f);
}

#endif
