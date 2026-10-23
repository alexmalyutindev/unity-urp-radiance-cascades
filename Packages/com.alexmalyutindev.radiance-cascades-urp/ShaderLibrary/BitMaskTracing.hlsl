#ifndef BITMASK_TRACING
#define BITMASK_TRACING

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.alexmalyutindev.radiance-cascades-urp/ShaderLibrary/Common.hlsl"

// NOTE: Declare!
float LoadLinearDepth(int2 pixel);
float3 GetFullResSceneLighting(float2 uv);

uint CountBits(uint bitMask)
{
    bitMask = bitMask - ((bitMask >> 1) & 0x55555555);
    bitMask = (bitMask & 0x33333333) + ((bitMask >> 2) & 0x33333333);
    bitMask = (bitMask + (bitMask >> 4)) & 0x0F0F0F0F;
    return (bitMask * 0x01010101) >> 24;
}


struct BitmaskTracingArgs
{
    float2 probeUV;
    float probeDepth;
    float2 depthSlope;     // Linear eye depth change per pixel (x, y).
    float2 rayDirection;   // Unit direction in pixels: (cos, sin).
    float4 texelSize;      // xy = 1 / full-res size, zw = full-res size.
    float2 tracingRange;   // In pixels.
    float stepSize;        // In pixels.
    float depthThickness;
};

// Edge-aware derivative: smallest magnitude of one-sided and central differences.
float MinAbsSlope(float backward, float forward)
{
    float oneSided = abs(forward) < abs(backward) ? forward : backward;
    float central = 0.5f * (forward + backward);
    return abs(oneSided) < abs(central) ? oneSided : central;
}

// Bits [lo, hi) of 32-bit word `wordId` inside 128-bit mask.
uint MaskWord(int lo, int hi, int wordId)
{
    int a = clamp(lo - 32 * wordId, 0, 32);
    int b = clamp(hi - 32 * wordId, 0, 32);
    uint fromA = a >= 32 ? 0u : (0xFFFFFFFFu << a);
    uint toB = b >= 32 ? 0xFFFFFFFFu : ((1u << b) - 1u);
    return fromA & toB;
}

// NOTE: alpha = dot(probeForward, direction) * 0.5 + 0.5, 128 bins, 32 bins per sector (one word per sector).
uint4 IntervalMask128(float alphaA, float alphaB)
{
    int lo = int(floor(saturate(min(alphaA, alphaB)) * 128.0f + 0.5f));
    int hi = int(floor(saturate(max(alphaA, alphaB)) * 128.0f + 0.5f));
    return uint4(
        MaskWord(lo, hi, 0),
        MaskWord(lo, hi, 1),
        MaskWord(lo, hi, 2),
        MaskWord(lo, hi, 3)
    );
}

// Output: row = depth sector, rgb = radiance, a = transmittance.
void RayTracing_Bitmask(BitmaskTracingArgs args, out float4x4 sectorRadiance)
{
    float3 forwardVS = normalize(ReconstructPositionVS(args.probeUV, 1.0f));
    float3 probeVS = ReconstructPositionVS(args.probeUV, args.probeDepth);

    float2 stepUV = args.rayDirection * args.texelSize.xy;

    // NOTE: Self occlusion. Bins behind the probe's own tangent plane are already occluded.
    float2 planeOffsetPixels = args.rayDirection * 1.1f;
    float3 planeVS = ReconstructPositionVS(
        args.probeUV + planeOffsetPixels * args.texelSize.xy,
        args.probeDepth + dot(planeOffsetPixels, args.depthSlope)
    );
    float planeAlpha = dot(forwardVS, normalize(planeVS - probeVS)) * 0.5f + 0.5f;
    uint4 visited = IntervalMask128(planeAlpha - 0.01f, 1.0f);

    sectorRadiance = 0.0f;
    UNITY_UNROLL for (int sectorId = 0; sectorId < 4; sectorId++)
    {
        sectorRadiance[sectorId] = float4(0.0f, 0.0f, 0.0f, 1.0f - CountBits(visited[sectorId]) * (1.0f / 32.0f));
    }

    UNITY_LOOP
    for (float rayStep = max(1.0f, args.tracingRange.x); rayStep <= args.tracingRange.y; rayStep += args.stepSize)
    {
        float2 rayUV = args.probeUV + rayStep * stepUV;

        if (any(rayUV > 1.0f || rayUV < 0.0f)) break;

        float depth = LoadLinearDepth(int2(rayUV * args.texelSize.zw));
        float3 directLight = GetFullResSceneLighting(rayUV);

        float3 surfaceVS = ReconstructPositionVS(rayUV, depth);
        float3 backVS = ReconstructPositionVS(rayUV, depth + args.depthThickness);

        float frontAlpha = dot(forwardVS, normalize(surfaceVS - probeVS)) * 0.5f + 0.5f;
        float backAlpha = dot(forwardVS, normalize(backVS - probeVS)) * 0.5f + 0.5f;

        uint4 occluder = IntervalMask128(frontAlpha, backAlpha);
        uint4 newBits = occluder & ~visited;
        visited |= occluder;

        UNITY_UNROLL for (int sectorId = 0; sectorId < 4; sectorId++)
        {
            sectorRadiance[sectorId] += float4(directLight, -1.0f) * (CountBits(newBits[sectorId]) * (1.0f / 32.0f));
        }
    }
}
#endif
