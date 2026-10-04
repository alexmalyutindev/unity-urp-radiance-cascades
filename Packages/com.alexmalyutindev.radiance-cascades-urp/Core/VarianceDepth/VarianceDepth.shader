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

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        SAMPLER(sampler_BlitTexture);
        Texture2D<float2> _BlitTexture;
        float4 _InputTexelSize;
        float2 _BlurDirection;
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

        #define SAMPLE_INPUT_TEX(uv) SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_BlitTexture, uv, 0)
        #define SAMPLE_INPUT_TEX_LOD(uv, mipLevel) SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_BlitTexture, uv, mipLevel)

        float2 BoxBlur3(float2 uv, float2 offsetDirection)
        {
            float2 offset = _InputTexelSize.xy * offsetDirection;
            float2 momentsL0 = SAMPLE_INPUT_TEX_LOD(uv - offset, _InputMipLevel);
            float2 momentsC0 = SAMPLE_INPUT_TEX_LOD(uv, _InputMipLevel);
            float2 momentsR0 = SAMPLE_INPUT_TEX_LOD(uv + offset, _InputMipLevel);

            return (momentsC0 + momentsL0 + momentsR0) * (1.0f / 3.0f);
        }
        
        // 3-Tap Symmetric Weights (Sum up to 1.0)
        static const float CenterWeight = 0.520500f;
        static const float OuterWeight  = 0.239750f;

        float2 GaussianBlur3(float2 uv, float2 offsetDirection)
        {
            float2 offset = _InputTexelSize.xy * offsetDirection;
            float2 momentsL0 = SAMPLE_INPUT_TEX_LOD(uv - offset, _InputMipLevel);
            float2 momentsC0 = SAMPLE_INPUT_TEX_LOD(uv, _InputMipLevel);
            float2 momentsR0 = SAMPLE_INPUT_TEX_LOD(uv + offset, _InputMipLevel);

            return momentsC0 * CenterWeight
                + (momentsL0 + momentsR0) * OuterWeight;
        }

        float2 GaussianBlur5(float2 uv, float2 offsetDirection)
        {
            float2 offset = _InputTexelSize.xy * offsetDirection;
            float2 momentsL1 = SAMPLE_INPUT_TEX_LOD(uv - 2.0h * offset, _InputMipLevel);
            float2 momentsL0 = SAMPLE_INPUT_TEX_LOD(uv - offset, _InputMipLevel);
            float2 momentsC0 = SAMPLE_INPUT_TEX_LOD(uv, _InputMipLevel);
            float2 momentsR0 = SAMPLE_INPUT_TEX_LOD(uv + offset, _InputMipLevel);
            float2 momentsR1 = SAMPLE_INPUT_TEX_LOD(uv + 2.0h * offset, _InputMipLevel);

            return momentsC0 * 6.0f / 16.0f
                + (momentsL0 + momentsR0) * 4.0f / 16.0f
                + (momentsL1 + momentsR1) * 1.0f / 16.0f;
        }
        
        float2 GaussianBlur3x3(float2 uv, float2 offsetDirection)
        {
            float2 offset = _InputTexelSize.xy * offsetDirection;
            float2 momentsL0 = SAMPLE_INPUT_TEX_LOD(uv - offset.xy, _InputMipLevel);
            float2 momentsC0 = SAMPLE_INPUT_TEX_LOD(uv, _InputMipLevel);
            float2 momentsR0 = SAMPLE_INPUT_TEX_LOD(uv + offset.xy, _InputMipLevel);
            return momentsC0 * 0.5f + momentsR0 * 0.25f + momentsL0 * 0.25f;
        }
        ENDHLSL

        Pass
        {
            Name "0 DepthToMoments"

            HLSLPROGRAM
            float3 ReconstructPositionVS(float2 uv, float eyeDepth)
            {
                float2 ndc = mad(uv, 2.0f, -1.0f);
                return float3(
                    ndc.x / _ProjMatrix[0][0],
                    ndc.y / _ProjMatrix[1][1],
                    1.0f
                ) * eyeDepth;
            }

            float2 Fragment(Varyings input) : SV_TARGET
            {
                float depthRaw = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, input.uv).r;
                float depth = LinearEyeDepth(depthRaw, _ZBufferParams);
                // depth = length(ReconstructPositionVS(input.uv, depth));
                return float2(depth, depth * depth);
            }
            ENDHLSL
        }

        Pass
        {
            Name "1 DepthMomentsBlurH"

            HLSLPROGRAM
            float2 Fragment(Varyings input) : SV_TARGET
            {
                return GaussianBlur5(input.uv, float2(1, 0));
            }
            ENDHLSL
        }

        Pass
        {
            Name "2 DepthMomentsBlurV"

            HLSLPROGRAM
            float2 Fragment(Varyings input) : SV_TARGET
            {
                return GaussianBlur5(input.uv, float2(0, 1));
            }
            ENDHLSL
        }

        Pass
        {
            Name "3 DepthMomentsBlurD"

            HLSLPROGRAM
            #include "Packages/com.alexmalyutindev.radiance-cascades-urp/ShaderLibrary/Blur.hlsl"

            float2 Fragment(Varyings input) : SV_TARGET
            {
                return SampleTent(_BlitTexture, sampler_BlitTexture, _InputTexelSize, _InputMipLevel, input.positionCS, _BlurDirection);
                return GaussianBlur3x3(input.uv, _BlurDirection);
            }
            ENDHLSL
        }
    }
}