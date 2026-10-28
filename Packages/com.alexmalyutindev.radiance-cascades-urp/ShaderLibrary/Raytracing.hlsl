#ifndef DEPTH_MOMENTS_TRACING
#define DEPTH_MOMENTS_TRACING

#include "Packages/com.alexmalyutindev.radiance-cascades-urp/ShaderLibrary/TrapezoidInegration.hlsl"
#include "Packages/com.alexmalyutindev.radiance-cascades-urp/ShaderLibrary/SoftCoverage.hlsl"

// NOTE: Declare!
float2 GetDepthMoments(float2 uv);
float3 GetSceneLighting(float2 uv);

struct RayTracingArgs
{
    float2 probeCenterUV;
    float2 probeMinMaxDepth;
    float2 rayDirection;
    float2 tracingRange;
    float sharpness;
    float probeSize;
    float stepSize;
    float depthThickness;
};

void RayTracing_TrapezoidIntegration(
    RayTracingArgs args,
    out half4x4 nearSectorRadiance,
    out half4x4 farSectorRadiance
)
{
    float2 depthMoments = GetDepthMoments(args.probeCenterUV);

    IntegrationSector integrationSector[2];
    integrationSector[0] = PrepareSector(args.probeMinMaxDepth, depthMoments, args.sharpness);
    integrationSector[1] = integrationSector[0];

    float3 probeViewDirectionVS = ReconstructPositionVS(args.probeCenterUV, 1.0f);
    float3 probeNormalVS = normalize(probeViewDirectionVS);

    float3 probeCenterVS[2];
    probeCenterVS[0] = probeViewDirectionVS * args.probeMinMaxDepth.x;
    probeCenterVS[1] = probeViewDirectionVS * args.probeMinMaxDepth.y;
    
    float2 rayDirectionUV = args.rayDirection * args.probeSize;
    args.tracingRange.x = max(0.5, args.tracingRange.x);

    UNITY_LOOP
    for (float rayStep = args.tracingRange.x; rayStep < args.tracingRange.y; rayStep += args.stepSize)
    {
        float2 rayUV = args.probeCenterUV + rayStep * rayDirectionUV;

        if (any(rayUV > 1.0f || rayUV < 0.0f)) break;

        depthMoments = GetDepthMoments(rayUV);
        float4 directLight = float4(GetSceneLighting(rayUV), -1.0f);

        float3 viewDirectionVS = ReconstructPositionVS(rayUV, 1.0f);

        float varianceDepth = depthMoments.x + sqrt(max(0.0f, depthMoments.y - depthMoments.x * depthMoments.x));
        float3 occluderMeanVS = viewDirectionVS * depthMoments.x;
        float3 occluderFarVS = viewDirectionVS * varianceDepth;
        float3 occluderThickVS = viewDirectionVS * (depthMoments.x + args.depthThickness);

        UNITY_UNROLL
        for (uint sectorId = 0u; sectorId < 2u; sectorId++)
        {
            IntegrateDepthSector(
                probeNormalVS, probeCenterVS[sectorId],
                occluderMeanVS, occluderFarVS, occluderThickVS,
                directLight,
                args.sharpness,
                integrationSector[sectorId]
            );
        }
    }

    nearSectorRadiance = integrationSector[0].color;
    farSectorRadiance = integrationSector[1].color;
}

half4 RayTracing_SoftBins(
    RayTracingArgs args,
    out half4x4 nearSectorRadiance,
    out half4x4 farSectorRadiance
)
{
    IntegrationSector sectors[2];
    sectors[0].color = float4x4(
        half4(0.0h, 0.0h, 0.0h, 1.0h),
        half4(0.0h, 0.0h, 0.0h, 1.0h),
        half4(0.0h, 0.0h, 0.0h, 1.0h),
        half4(0.0h, 0.0h, 0.0h, 1.0h)
    );
    sectors[0].transmittance = 1.0h;
    sectors[1] = sectors[0];
    
    for (uint sectorId = 0u; sectorId < 2u; sectorId++)
    {
        sectors[sectorId].color = float4x4(float4(0,0,0,1), float4(0,0,0,1), float4(0,0,0,1), float4(0,0,0,1));
        sectors[sectorId].transmittance = 1.0f;

#ifdef SELF_OCCLUSION
        // Soft "self" pre-pass. With the constants used here (center=0, distConst=0,
        // rampSlope=min(1,0)=0) this evaluates to falloff==1 for every bin, i.e. it's
        // a structural no-op — kept because it mirrors the ray-hit splat exactly and
        // may not be a no-op in other compiled variants of this shader.

        float binNear = 0.2f;
        float binVarFar = 0.1f;
        float binThick = 0.0f;

        float curveTerm = SQRT3 * (binNear - binVarFar);
        float halfRange = (binNear - binThick) * 0.5;
        float sumRange  = binThick + binNear;
        float binCenter = sumRange * 0.5;
        float distConst = abs(halfRange - curveTerm);
        float invCurve  = max(FLT_EPS, (halfRange + curveTerm) - distConst);
        float rampSlope = min(1.0, halfRange / max(FLT_EPS, curveTerm));

        float4 directLight = float4(0, 0, 0, -1.0f);
        AccumulateSoftBins(sectors[sectorId], directLight, binCenter, distConst, invCurve, rampSlope, args.sharpness);
#endif
    }

    float3 probeViewDirectionVS = ReconstructPositionVS(args.probeCenterUV, 1.0f);
    float3 probeNormalVS = -normalize(probeViewDirectionVS);

    float3 probeCenterVS[2];
    probeCenterVS[0] = probeViewDirectionVS * args.probeMinMaxDepth.x;
    probeCenterVS[1] = probeViewDirectionVS * args.probeMinMaxDepth.y;
    
    float2 directionUV = args.rayDirection * args.probeSize;

    args.tracingRange.x = max(0.5f, args.tracingRange.x);

    UNITY_LOOP
    for (float marchDist = args.tracingRange.x; marchDist < args.tracingRange.y; marchDist += args.stepSize)
    {
        float2 rayUV = args.probeCenterUV + marchDist * directionUV;

        if (any(rayUV > 1.0f || rayUV < 0.0f)) break;

        float2 depthMoments = GetDepthMoments(rayUV);
        float4 directLight = float4(GetSceneLighting(rayUV), -1.0f);

        float3 viewDirectionVS = ReconstructPositionVS(rayUV, 1.0f);

        float meanDepth = depthMoments.x + sqrt(max(0.0f, depthMoments.y - depthMoments.x * depthMoments.x));

        float3 occluderNearVS = viewDirectionVS * depthMoments.x;
        float3 occluderFarVS = viewDirectionVS * (depthMoments.x + args.depthThickness);
        float3 occluderMeanVS = viewDirectionVS * meanDepth;

        UNITY_UNROLL
        for (uint sectorId = 0u; sectorId < 2u; sectorId++)
        {
            float binNear = dot(probeNormalVS, normalize(occluderNearVS - probeCenterVS[sectorId])) * 0.5f + 0.5f;
            float binVarFar = dot(probeNormalVS, normalize(occluderMeanVS - probeCenterVS[sectorId])) * 0.5f + 0.5f;
            float binThick = dot(probeNormalVS, normalize(occluderFarVS - probeCenterVS[sectorId])) * 0.5f + 0.5f;

            float curveTerm = SQRT3 * (binNear - binVarFar);
            float halfRange = (binNear - binThick) * 0.5;
            float sumRange  = binThick + binNear;
            float binCenter = sumRange * 0.5;
            float distConst = abs(halfRange - curveTerm);
            float invCurve  = max(FLT_EPS, (halfRange + curveTerm) - distConst);
            float rampSlope = min(1.0, halfRange / max(FLT_EPS, curveTerm));

            AccumulateSoftBins(sectors[sectorId], directLight, binCenter, distConst, invCurve, rampSlope, args.sharpness);
        } 
    }

    nearSectorRadiance = sectors[0].color;
    farSectorRadiance = sectors[1].color;
    return 0.0f;
}

#endif
