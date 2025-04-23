#ifndef DEPTH_MOMENTS_TRAING
#define DEPTH_MOMENTS_TRAING

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

#define MY_FLT_EPS (1e-7f)

struct Trapezoid
{
    float median;
    float constHalfSize;
    float linHalfSize;
    float height;
};

// Builds a trapezoid-shaped opacity function from an interval [minmax.x, minmax.y] offset by a uniformly
// distributed function with variance = sigma^2
Trapezoid GetVarianceTrapezoid(float2 minmax, float sigma0)
{
    Trapezoid result;
    float halfRange = sqrt(3.0f) * sigma0;
    float halfSize = (minmax.y - minmax.x) * 0.5f;
    result.median = 0.5f * (minmax.x + minmax.y);
    result.constHalfSize = abs(halfSize - halfRange);
    result.linHalfSize = max(MY_FLT_EPS, halfSize + halfRange - result.constHalfSize);
    result.height = min(1.0f, halfSize / max(MY_FLT_EPS, halfRange));
    return result;
}

//Integral [0..x] t dt
float LinearIntegral(float x)
{
    return x * x * 0.5f;
}

//Integral [0..x] trapezoid(t) dt
float IntegrateTrapezoid(Trapezoid trapezoid, float x)
{
    float constRange = min(abs(x - trapezoid.median), trapezoid.constHalfSize + trapezoid.linHalfSize);
    float linRange = max(0.0f, constRange - trapezoid.constHalfSize);
    float constInt = constRange;
    float linInt = -LinearIntegral(linRange) / trapezoid.linHalfSize;
    return (x > trapezoid.median ? 1.0f : -1.0f) * trapezoid.height * (constInt + linInt);
}

struct IntegrationSector
{
    float4x4 transmittance;
    float4x4 color;
};

IntegrationSector PrepareSector(float cascadePower)
{
    const float4 directLight = float4(0.0f, 0.0f, 0.0f, -1.0f);

    IntegrationSector sector;
    sector.transmittance = float4x4(
        float4(1.0f, 1.0f, 1.0f, 1.0f),
        float4(1.0f, 1.0f, 1.0f, 1.0f),
        float4(1.0f, 1.0f, 1.0f, 1.0f),
        float4(1.0f, 1.0f, 1.0f, 1.0f)
    );
    sector.color = float4x4(
        float4(0.0f, 0.0f, 0.0f, 1.0f),
        float4(0.0f, 0.0f, 0.0f, 1.0f),
        float4(0.0f, 0.0f, 0.0f, 1.0f),
        float4(0.0f, 0.0f, 0.0f, 1.0f)
    );

    float sigma = 1.0f;
    float2 minmax = float2(0.0f, MY_FLT_EPS);

    Trapezoid trapezoid = GetVarianceTrapezoid(minmax, sigma);

    float prevOcclusion = IntegrateTrapezoid(trapezoid, 0.0f);

    UNITY_UNROLL
    for (uint rayId = 0; rayId < 16; rayId++)
    {
        float alpha = (rayId + 1.0f) * (1.0f / 16.0f);

        int groupId = rayId / 4;
        int subRayId = rayId % 4;

        float occlusion = IntegrateTrapezoid(trapezoid, alpha);
        float transmittance = pow(saturate(1.0f - (occlusion - prevOcclusion) * 16.0f), cascadePower);
        prevOcclusion = occlusion;

        float currentTransmittance = sector.transmittance[groupId][subRayId];
        sector.color[groupId] += directLight * currentTransmittance * (1.0f - transmittance) * 0.25h;
        sector.transmittance[groupId][subRayId] *= transmittance;
    }

    return sector;
}

half4x4 TraceDepthSector(
    float3 probePositionVS,
    float2 rayDirection,
    float2 range,
    float4 outputSizeTexel,
    float cascadePower
)
{
    const float depthThickness = 50.0f;
    const float stepSize = outputSizeTexel.w;

    IntegrationSector sector = PrepareSector(cascadePower);

    float3 probeViewDirectionVS = -normalize(probePositionVS);
    float2 probeCenterUV = TransformViewToScreenUV(probePositionVS).xy;
    float2 directionUV = rayDirection * float2(outputSizeTexel.y * outputSizeTexel.z, 1.0h) * stepSize;

    range.x = max(range.x, 1.0f);

    UNITY_LOOP
    for (float rayStep = range.x; rayStep < range.y; rayStep += 1.0f)
    {
        float2 rayUV = probeCenterUV + rayStep * directionUV;

        if (any(rayUV > 1 || rayUV < 0)) break;

        float2 depthMoments = GetDepthMoments(rayUV);
        float4 directLight = float4(GetSceneLighting(rayUV), -1.0);

        float3 viewDirectionVS = ComputeViewSpacePosition(rayUV, UNITY_RAW_FAR_CLIP_VALUE, _InvProjectionMatrix);
        viewDirectionVS.xyz /= viewDirectionVS.z;

        float meanDepth = depthMoments.x + sqrt(max(0.0f, depthMoments.y - depthMoments.x * depthMoments.x));
        float3 occluderNearVS = viewDirectionVS.xyz * depthMoments.x;
        float3 occluderFarVS = viewDirectionVS.xyz * (depthMoments.x + depthThickness);
        float3 occluderMeanVS = viewDirectionVS.xyz * meanDepth;

        // TODO: Min and Max probe
        float nearAngle = dot(probeViewDirectionVS, normalize(occluderNearVS - probePositionVS));
        float farAngle = dot(probeViewDirectionVS, normalize(occluderFarVS - probePositionVS));
        float meanAngle = dot(probeViewDirectionVS, normalize(occluderMeanVS - probePositionVS));

        Trapezoid trapezoid = GetVarianceTrapezoid(float2(nearAngle, farAngle), meanAngle - nearAngle);

        float prevOcclusion = IntegrateTrapezoid(trapezoid, 0);

        for (uint rayId = 0; rayId < 16; rayId++)
        {
            float alpha = (rayId + 1.0f) * (1.0f / 8.0f) - 1.0f;

            int groupId = rayId / 4;
            int subRayId = rayId % 4;

            float occlusion = IntegrateTrapezoid(trapezoid, alpha);
            float transmittance = saturate(pow(saturate(1.0f - (occlusion - prevOcclusion) * 16.0f), cascadePower));
            prevOcclusion = occlusion;

            float currentTransmittance = sector.transmittance[groupId][subRayId];
            sector.color[groupId] += directLight * currentTransmittance * saturate(1.0f - transmittance) * 0.25h;
            sector.transmittance[groupId][subRayId] *= saturate(transmittance);
        }
    }

    return sector.color;
}


//////////////
/// ACTUAL ///
//////////////

void IntegrateDepthSector(
    float3 probeNormalVS, float3 probeCenterVS,
    float3 occluderNearVS, float3 occluderFarVS, float3 occluderMeanVS,
    float4 directLight,
    float cascadePower,
    inout IntegrationSector minSector
)
{
    float nearAngle = dot(probeNormalVS, normalize(occluderNearVS - probeCenterVS)) * 0.5f + 0.5f;
    float farAngle = dot(probeNormalVS, normalize(occluderFarVS - probeCenterVS)) * 0.5f + 0.5f;
    float meanAngle = dot(probeNormalVS, normalize(occluderMeanVS - probeCenterVS)) * 0.5f + 0.5f;

    Trapezoid trapezoid = GetVarianceTrapezoid(float2(nearAngle, farAngle), nearAngle - meanAngle);

    float prevOcclusion = IntegrateTrapezoid(trapezoid, 0.0f);

    UNITY_UNROLL
    for (uint rayId = 0; rayId < 16; rayId++)
    {
        float alpha = (rayId + 1.0f) * (1.0f / 16.0f);

        int groupId = rayId / 4;
        int subRayId = rayId % 4;

        float occlusion = IntegrateTrapezoid(trapezoid, alpha);
        float transmittance = saturate(pow(saturate(1.0f - (occlusion - prevOcclusion) * 16.0f), cascadePower));
        prevOcclusion = occlusion;

        float currentTransmittance = minSector.transmittance[groupId][subRayId];
        minSector.color[groupId] += directLight * currentTransmittance * saturate(1.0f - transmittance) * 0.25h;
        minSector.transmittance[groupId][subRayId] *= saturate(transmittance);
    }
}

void ComputeProbeRadiance(
    float2 probeMinMaxDepth,
    float2 probeCenterUV,
    float2 rayDirection,
    float2 range,
    float4 outputSizeTexel,
    float cascadePower,
    out half4x4 minProbeRad,
    out half4x4 maxProbeRad
)
{
    const float depthThickness = 50.0f;
    const float stepSize = outputSizeTexel.w;

    IntegrationSector minSector = PrepareSector(cascadePower);
    IntegrationSector maxSector = minSector;

    float3 probeCenterVS = ComputeViewSpacePosition(probeCenterUV, UNITY_RAW_FAR_CLIP_VALUE, _InvProjectionMatrix);
    float3 probeNormalVS = normalize(probeCenterVS);

    float3 probeViewDirectionVS = probeCenterVS.xyz / abs(probeCenterVS.z);
    float3 minProbeCenterVS = probeViewDirectionVS * probeMinMaxDepth.x;
    float3 maxProbeCenterVS = probeViewDirectionVS * probeMinMaxDepth.y;

    float2 directionUV = stepSize * rayDirection * float2(outputSizeTexel.y * outputSizeTexel.z, 1.0h);

    range.x = max(range.x, 0.0f);

    UNITY_LOOP
    for (float rayStep = range.x; rayStep < range.y; rayStep += 1.0f)
    {
        float2 rayUV = probeCenterUV + rayStep * directionUV;

        if (any(rayUV > 1 || rayUV < 0)) break;

        float2 depthMoments = GetDepthMoments(rayUV);
        float4 directLight = float4(GetSceneLighting(rayUV), -1.0);

        float3 viewDirectionVS = ComputeViewSpacePosition(rayUV, UNITY_RAW_FAR_CLIP_VALUE, _InvProjectionMatrix);
        viewDirectionVS.xyz /= viewDirectionVS.z;

        float meanDepth = depthMoments.x + sqrt(max(0.0f, depthMoments.y - depthMoments.x * depthMoments.x));
        float3 occluderNearVS = viewDirectionVS * depthMoments.x;
        float3 occluderFarVS = viewDirectionVS * (depthMoments.x + depthThickness);
        float3 occluderMeanVS = viewDirectionVS * meanDepth;

        IntegrateDepthSector(
            probeNormalVS, minProbeCenterVS,
            occluderNearVS, occluderFarVS, occluderMeanVS,
            directLight,
            cascadePower,
            minSector
        );
        IntegrateDepthSector(
            probeNormalVS, maxProbeCenterVS,
            occluderNearVS, occluderFarVS, occluderMeanVS,
            directLight,
            cascadePower,
            maxSector
        );
    }

    minProbeRad = minSector.color;
    maxProbeRad = maxSector.color;
}

#endif
