#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

float4 _ColorTexture_TexelSize;
float4 _DepthTexture_TexelSize;
// { width, height, 1 / width, 1 / height }
float4 _CascadeBufferSize;

float4x4 _WorldToView;
float4x4 _ViewToWorld;
float4x4 _ViewToHClip;

Texture2D _ColorTexture;
Texture2D<float> _DepthTexture;
Texture2D<half3> _NormalsTexture;

float GetSectorId(int2 texCoord, float probeSize)
{
    return texCoord.x % probeSize + (texCoord.y % probeSize) * probeSize;
}

float GetAngle(int2 texCoord, float probeSize)
{
    float sectorId = texCoord.x % probeSize + (texCoord.y % probeSize) * probeSize;
    float angleStep = TWO_PI / (probeSize * probeSize);
    return (sectorId + 0.5f) * angleStep;
}

float2 GetRayDirection(int2 texCoord, float probeSize)
{
    float sectorId = GetSectorId(texCoord, probeSize);
    float2 direction;
    sincos((sectorId + 0.5f) * PI * 4.0f / (probeSize * probeSize), direction.y, direction.x);
    return direction;
}

inline float SampleLinearDepth(float2 uv)
{
    // float rawDepth = SAMPLE_TEXTURE2D_LOD(_DepthTexture, sampler_PointClamp, uv, 0).r;
    float rawDepth = LOAD_TEXTURE2D(_DepthTexture, uv * _ColorTexture_TexelSize.xy).r;
    return rawDepth;
    // return LinearEyeDepth(rawDepth, zBufferParams);
}

float4 RayTrace(float2 probeUV, float2 ray, float sceneDepth, int stepsCount)
{
    // TODO: Cast ray in Depth target pixel coords (or use downscaled version).
    // ray *= _CascadeBufferSize.xy * _ColorTexture_TexelSize.zw;
    float2 uv = probeUV;
    float4 color =  float4(0.0f, 0.0f, 0.0f, 1.0f);
    for (int i = 0; i < stepsCount; i++)
    {
        uv += ray;
        if (any(uv < 0) || any(uv > 1))
        {
            break;
        }

        float currentDepth = LOAD_TEXTURE2D(_DepthTexture, uv * _ColorTexture_TexelSize.xy).r;
        if (sceneDepth < currentDepth)
        {
            color = float4(1.0f, 1.0f, 1.0f, 0.0f);
            break;
        }
    }

    return color * SAMPLE_TEXTURE2D_LOD(_ColorTexture, sampler_PointClamp, uv, 0);
}


int AngleToIndex(float angle, int dim)
{
    float t = angle / (2 * PI);
    int index = floor(t * float(dim * dim));
    return index;
}

int2 IndexToCoords(float index, float dim)
{
    //in case the index is lower than 0 or higher than the number of angles
    index = index % (dim * dim);
    int x = index % dim;
    int y = index / dim;

    return int2(x, y);
}

int2 CalculateRange(int cascadeLevel)
{
    const float factor = 4.0;

    float start = (1.0 - pow(factor, cascadeLevel)) / (1.0 - factor);
    float end = (1.0 - pow(factor, cascadeLevel + 1.0)) / (1.0 - factor);

    return int2(start, end);
}

float3 GetPositionVS(float2 screenUV, float rawDepth)
{
    screenUV = screenUV * 2 - 1;
    return ComputeViewSpacePosition(
        float2(screenUV.x, -screenUV.y),
        rawDepth,
        UNITY_MATRIX_I_P
    );
}

float3 GetPositionWS(float2 screenUV, float rawDepth)
{
    screenUV = screenUV * 2 - 1;
    return ComputeWorldSpacePosition(
        float4(screenUV.x, -screenUV.y, rawDepth, 1),
        unity_MatrixInvVP
    );
}

float3 Intersect(float3 planeP, float3 planeN, float3 rayP, float3 rayD)
{
    float d = dot(planeP, -planeN);
    float t = -(d + dot(rayP, planeN)) / dot(rayD, planeN);
    return rayP + t * rayD;
}

static float4 DirectionFirstRayZ = float4(-2.0f, -1.0f, 1.0f, 2.0f);

float3 GetRayDirectionDFWS(float2 angleId, float cascadeLevel)
{
    float deltaPhi = TWO_PI * pow(0.5f, cascadeLevel) * 0.25f; // 1/4
    static const float deltaTheta = PI * 0.25f;
    // Azimuth
    float phi = (angleId.x + 0.5f) * deltaPhi;
    // float phi = (angleId.x + angleId.y * 0.25f + 0.5f) * deltaPhi;
    // Polar
    float theta = (angleId.y + 0.5f) * deltaTheta;
    // float theta = HALF_PI;

    float2 sinCosPhi;
    float2 sinCosTheta;
    sincos(phi, sinCosPhi.x, sinCosPhi.y);
    sincos(theta, sinCosTheta.x, sinCosTheta.y);

    float3 ray = float3(sinCosTheta.x * sinCosPhi.y, sinCosTheta.x * sinCosPhi.x, sinCosTheta.y);
    return mul(_ViewToWorld, float4(ray, 0)).xyz;
}

float3 GetRayDirectionDFVS(float2 angleId, float cascadeLevel)
{
    float deltaPhi = TWO_PI * pow(0.5f, cascadeLevel) * 0.25f; // 1/4
    static const float deltaTheta = PI * 0.25f;
    // Azimuth
    float phi = (angleId.x + 0.5f) * deltaPhi;
    // float phi = (angleId.x + angleId.y * 0.25f + 0.5f) * deltaPhi;
    // Polar
    float theta = (angleId.y + 0.5f) * deltaTheta;
    // float theta = HALF_PI;

    float2 sinCosPhi;
    float2 sinCosTheta;
    sincos(phi, sinCosPhi.x, sinCosPhi.y);
    sincos(theta, sinCosTheta.x, sinCosTheta.y);

    float3 ray = float3(sinCosTheta.x * sinCosPhi.y, sinCosTheta.x * sinCosPhi.x, sinCosTheta.y);
    return ray;
}

float2 LinearEyeDepth(float2 depth, float4 zBufferParam)
{
    return 1.0f / (zBufferParam.z * depth + zBufferParam.w);
}

float4 LinearEyeDepth(float4 depth, float4 zBufferParam)
{
    return 1.0f / (zBufferParam.z * depth + zBufferParam.w);
}
