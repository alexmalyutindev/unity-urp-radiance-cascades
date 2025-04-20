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

        Pass
        {
            Name "DepthToMoments"

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            Texture2D<float> _BlitTexture;
            float4 _BlitTexture_TexelSize;

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
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            Texture2D<float2> _BlitTexture;
            float4 _BlitTexture_TexelSize;
            float2 _InputResolution;
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

            float2 Fragment(Varyings input) : SV_TARGET
            {
                float2 offset = float2(0.0f, _BlitTexture_TexelSize.y);
                float2 depth2 = 0.0f;
                int range = 5;
                for (int y = -range; y <= range; y++)
                {
                    float2 depthMoments = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, input.uv + offset * y).rg;
                    depth2 += depthMoments;
                }
                return depth2 / (range * 2.0f + 1.0f);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthMomentsBlurH"

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            Texture2D<float2> _BlitTexture;
            float4 _BlitTexture_TexelSize;
            float2 _InputResolution;
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

            float2 Fragment(Varyings input) : SV_TARGET
            {
                float2 offset = float2(_BlitTexture_TexelSize.x, 0.0f);
                float2 depth2 = 0.0f;
                int range = 5;
                for (int x = -range; x <= range; x++)
                {
                    float2 depthMoments = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, input.uv + offset * x).rg;
                    depth2 += depthMoments;
                }
                return depth2 / (range * 2.0f + 1.0f);
            }
            ENDHLSL
        }
    }
}