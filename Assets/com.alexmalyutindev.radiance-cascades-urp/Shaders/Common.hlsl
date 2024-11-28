#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

float4 _ColorTexture_TexelSize;
float4 _DepthTexture_TexelSize;
float4 _CascadeBufferSize;

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
