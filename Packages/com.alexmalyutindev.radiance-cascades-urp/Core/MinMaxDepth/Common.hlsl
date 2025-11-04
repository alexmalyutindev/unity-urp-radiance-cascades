#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

Texture2D<float2> _BlitTexture;
float4 _BlitTexture_TexelSize;
float2 _InputResolution;
int _InputMipLevel;
float _Scale;

struct Attributes
{
    float4 positionOS : POSITION;
    float2 texcoord : TEXCOORD0;
};

struct Varyings
{
    float2 uv : TEXCOORD0;
    float4 positionCS : SV_POSITION;
};

Varyings Vertex(Attributes input)
{
    Varyings output;
    output.positionCS = float4(input.positionOS.xy * 2 - 1, 0, 1);
    output.uv = input.texcoord;
    #if UNITY_UV_STARTS_AT_TOP
    output.uv.y = 1 - output.uv.y;
    #endif
    return output;
}

float4 LinearEyeDepth(float4 depth, float4 zBufferParam)
{
    return 1.0 / (zBufferParam.z * depth + zBufferParam.w);
}

#if defined(SINGLE_CHANNEL)
float2 LoadDepth(int2 coord, int _InputMipLevel)
{
    coord = min(coord, int2(_InputResolution) - 1);
    return LOAD_TEXTURE2D_LOD(_BlitTexture, coord, _InputMipLevel).r;
}
#else
float2 LoadDepth(int2 coord, int _InputMipLevel)
{
    // coord = min(coord, int2(_InputResolution) - 1);
    return LOAD_TEXTURE2D_LOD(_BlitTexture, coord, _InputMipLevel).rg;
}
#endif

float2 LoadDepthMinMax(int2 coord, int _InputMipLevel)
{
    float2 a = LoadDepth(coord, _InputMipLevel);
    float2 b = LoadDepth(coord + int2(1, 0), _InputMipLevel);
    float2 c = LoadDepth(coord + int2(0, 1), _InputMipLevel);
    float2 d = LoadDepth(coord + int2(1, 1), _InputMipLevel);

    return float2(
        min(min(a.x, b.x), min(c.x, d.x)),
        max(max(a.y, b.y), max(c.y, d.y))
    );
}

float4 GatherDepth(int2 coord, int _InputMipLevel)
{
    float a = LoadDepth(coord, _InputMipLevel);
    float b = LoadDepth(coord + int2(1, 0), _InputMipLevel);
    float c = LoadDepth(coord + int2(0, 1), _InputMipLevel);
    float d = LoadDepth(coord + int2(1, 1), _InputMipLevel);

    return float4(a, b, c, d);
}