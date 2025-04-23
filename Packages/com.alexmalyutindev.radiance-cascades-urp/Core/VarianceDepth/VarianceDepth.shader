Shader "Hidden/VarianceDepth"
{
    Properties {}

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
        }
        LOD 100
        
        HLSLINCLUDE
        #pragma vertex Vertex
        #pragma fragment Fragment
        
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        Texture2D<float2> _BlitTexture;
        float4 _BlitTexture_TexelSize;
        float4 _InputTexelSize;
        int _InputMipLevel;

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

        #define SAMPLE_INPUT_TEX(uv, mipLevel) SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv, mipLevel)

        float2 GaussianBlur3(float2 uv, float2 offsetDirection)
        {
            float2 offset = _BlitTexture_TexelSize.xy * offsetDirection * pow(2, _InputMipLevel);
            float2 momentsL0 = SAMPLE_INPUT_TEX(uv - offset, _InputMipLevel);
            float2 momentsC0 = SAMPLE_INPUT_TEX(uv, _InputMipLevel);
            float2 momentsR0 = SAMPLE_INPUT_TEX(uv + offset, _InputMipLevel);

            return momentsC0 * 2.0f / 4.0f
                + (momentsL0 + momentsR0) * 1.0f / 4.0f
            ;
        }

        float2 GaussianBlur5(float2 uv, float2 offsetDirection)
        {
            float2 offset = _BlitTexture_TexelSize.xy * offsetDirection * pow(2, _InputMipLevel);
            float2 momentsL1 = SAMPLE_INPUT_TEX(uv - 2.0h * offset, _InputMipLevel);
            float2 momentsL0 = SAMPLE_INPUT_TEX(uv - offset, _InputMipLevel);
            float2 momentsC0 = SAMPLE_INPUT_TEX(uv, _InputMipLevel);
            float2 momentsR0 = SAMPLE_INPUT_TEX(uv + offset, _InputMipLevel);
            float2 momentsR1 = SAMPLE_INPUT_TEX(uv + 2.0h * offset, _InputMipLevel);

            return momentsC0 * 6.0f / 16.0f
                + (momentsL0 + momentsR0) * 4.0f / 16.0f
                + (momentsL1 + momentsR1) * 1.0f / 16.0f
            ;
        }
        ENDHLSL

        Pass
        {
            Name "DepthToMoments"

            HLSLPROGRAM
            float2 Fragment(Varyings input) : SV_TARGET
            {
                float depthRaw = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, input.uv).r;
                float depth = LinearEyeDepth(depthRaw, _ZBufferParams);
                return float2(depth, depth * depth);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthMomentsBlurV"

            HLSLPROGRAM
            float2 Fragment(Varyings input) : SV_TARGET
            {
                return GaussianBlur3(input.uv, float2(1, 0));
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthMomentsBlurH"

            HLSLPROGRAM
            float2 Fragment(Varyings input) : SV_TARGET
            {
                return GaussianBlur3(input.uv, float2(0, 1));
            }
            ENDHLSL
        }
    }
}