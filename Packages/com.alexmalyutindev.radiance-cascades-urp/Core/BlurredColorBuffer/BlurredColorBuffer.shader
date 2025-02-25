Shader "Hidden/BlurredColorBuffer"
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
            Name "DownSampleColorBlurred"
            Cull Back

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            Texture2D<float4> _BlitTexture;
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

            inline half4 SampleColorBuffer(float2 uv, int lod)
            {
                return SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv, lod);
            }

            half4 Fragment(Varyings input) : SV_TARGET
            {
                float4 offset = 1.0f / float4(_InputResolution.xy, -_InputResolution.xy);

                half4 color = SampleColorBuffer(input.uv + offset.xy, _InputMipLevel);
                color += SampleColorBuffer(input.uv + offset.xw, _InputMipLevel);
                color += SampleColorBuffer(input.uv + offset.zy, _InputMipLevel);
                color += SampleColorBuffer(input.uv + offset.zw, _InputMipLevel);
                color *= 0.25f;

                return color;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DownSampleColorBlurredHorizontal"
            Cull Back

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            Texture2D<float4> _BlitTexture;
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

            inline half4 SampleColorBuffer(float2 uv, int lod)
            {
                return SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv, lod);
            }

            half4 Fragment(Varyings input) : SV_TARGET
            {
                float2 offset = float2(1.0f / _InputResolution.x, 0.0f);

                half4 color = SampleColorBuffer(input.uv, _InputMipLevel);
                color += SampleColorBuffer(input.uv + offset.xy, _InputMipLevel);
                color += SampleColorBuffer(input.uv - offset.xy, _InputMipLevel);
                color *= 0.3334f;

                return color;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DownSampleColorBlurredVertical"
            Cull Back

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            Texture2D<float4> _BlitTexture;
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

            inline half4 SampleColorBuffer(float2 uv, int lod)
            {
                return SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv, lod);
            }

            half4 Fragment(Varyings input) : SV_TARGET
            {
                float2 offset = float2(0.0f, 1.0f / _InputResolution.y);

                half4 color = SampleColorBuffer(input.uv, _InputMipLevel);
                color += SampleColorBuffer(input.uv + offset.xy, _InputMipLevel);
                color += SampleColorBuffer(input.uv - offset.xy, _InputMipLevel);
                color *= 1.0f / 3.0f;

                return color;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DownSampleColorBlurredDirectional"
            Cull Back

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            Texture2D<float4> _BlitTexture;
            float4 _BlitTexture_TexelSize;
            float2 _InputResolution;
            float2 _OffsetDirection;
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

            inline half4 SampleColorBuffer(float2 uv, int lod)
            {
                return SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv, lod);
            }

            half4 Fragment(Varyings input) : SV_TARGET
            {
                float2 offset = _OffsetDirection / _InputResolution.xy;

                half4 color = SampleColorBuffer(input.uv, _InputMipLevel);
                color += SampleColorBuffer(input.uv + offset.xy, _InputMipLevel);
                color += SampleColorBuffer(input.uv - offset.xy, _InputMipLevel);
                color *= 1.0f / 3.0f;

                return color;
            }
            ENDHLSL
        }
    }
}