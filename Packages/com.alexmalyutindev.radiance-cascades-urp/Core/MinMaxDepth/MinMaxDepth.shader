Shader "Hidden/MinMaxDepth"
{
    Properties {}

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
        }
        LOD 100

        Pass
        {
            Name "DownSampleDepthMinMax2x2_SingleChannel"
            ColorMask RG

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #define SINGLE_CHANNEL
            #include "Common.hlsl"

            float2 Fragment(Varyings input) : SV_TARGET
            {
                float2 uv = input.positionCS.xy * _BlitTexture_TexelSize.xy * 2.0f;
                float4 depths = _BlitTexture.GatherRed(sampler_PointClamp, uv);
                depths = LinearEyeDepth(depths, _ZBufferParams);
                return float2(Min4(depths), Max4(depths));
            }
            ENDHLSL
        }

        Pass
        {
            Name "DownSampleDepthMinMax2x2"
            ColorMask RG

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Common.hlsl"

            float2 Fragment(Varyings input) : SV_TARGET
            {
                return LoadDepthMinMax(floor(input.positionCS.xy) * 2, _InputMipLevel);
            }
            ENDHLSL
        }

        Pass
        {
            Name "CopyLevel"

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Common.hlsl"

            float2 Fragment(Varyings input) : SV_TARGET
            {
                int2 coord = input.positionCS.xy;
                return LOAD_TEXTURE2D_LOD(_BlitTexture, coord, 0).rg;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthToMixMaxDepth"
            ColorMask RG

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #pragma target 2.0
            #pragma editor_sync_compilation

            #define SINGLE_CHANNEL
            #include "Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
            float2 _TargetResolution;

            float2 Fragment(Varyings input) : SV_TARGET
            {
                return LinearEyeDepth(
                    SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_PointClamp, input.uv, 0).r,
                    _ZBufferParams
                );

                int2 range = 1; // floor(_BlitTexture_TexelSize.zw / _TargetResolution.xy);
                float2 minMaxDepth = float2(FLT_MAX, 0.0f);
                for (int x = -range; x <= range.x; x++)
                {
                    for (int y = -range; y <= range.y; y++)
                    {
                        float2 uv = input.uv + float2(x, y) * _BlitTexture_TexelSize.xy * 2;
                        float depth = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_PointClamp, uv, 0).r;
                        depth = LinearEyeDepth(depth, _ZBufferParams);
                        minMaxDepth = float2(
                            min(minMaxDepth.x, depth),
                            max(minMaxDepth.y, depth)
                        );
                    }
                }
                return minMaxDepth;
            }
            ENDHLSL
        }

        Pass
        {
            Name "[Test] BilateralWeights"

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Common.hlsl"

            float4 Fragment(Varyings input) : SV_TARGET
            {
                int2 coord = input.positionCS.xy;
                float2 hiDepth = LOAD_TEXTURE2D_LOD(_BlitTexture, coord, 0).rg;
                float4 lowDepthABCD_min;
                float4 lowDepthABCD_max;

                int2 lowSize = int2(_BlitTexture_TexelSize.zw / 2) - 1;
                coord = max(0, (coord - 1) / 2);

                static const int2 neighbours[4] = {int2(0, 0), int2(1, 0), int2(0, 1), int2(1, 1)};
                UNITY_UNROLL for (int i = 0; i < 4; i++)
                {
                    int2 c = min(coord + neighbours[i], lowSize);
                    float2 sample = LOAD_TEXTURE2D_LOD(_BlitTexture, c, 1).rg;
                    lowDepthABCD_min[i] = sample.x;
                    lowDepthABCD_max[i] = sample.y;
                }
                float4 weights_min = exp2(-20.0h * abs(hiDepth.x - lowDepthABCD_min));
                weights_min = saturate(weights_min / dot(1.0f, weights_min));
                return abs(hiDepth.x - dot(weights_min, lowDepthABCD_min));
                return abs(hiDepth.x - lowDepthABCD_min);
            }
            ENDHLSL
        }
    }
}