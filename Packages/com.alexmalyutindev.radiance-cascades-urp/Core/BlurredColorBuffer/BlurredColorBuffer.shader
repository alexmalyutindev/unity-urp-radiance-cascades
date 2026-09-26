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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            Texture2D<float4> _BlitTexture;
            float4 _BlitTexture_TexelSize;
            float4 _InputSizeTexel;
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
                float4 offset = float4(_InputSizeTexel.zw, -_InputSizeTexel.zw);

                // NOTE: Simple box blur into 1/2 res target
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
            Name "Copy"
            Cull Back

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            Texture2D<float4> _BlitTexture;
            float4 _BlitTexture_TexelSize;
            float4 _InputSizeTexel;
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
                return SampleColorBuffer(input.uv, 0);
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            SAMPLER(sampler_BlitTexture);
            Texture2D<half4> _BlitTexture;
            float4 _BlitTexture_TexelSize;
            float4 _InputTexelSize;
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
            
            #define SAMPLE_INPUT_TEX_LOD(uv, mipLevel) SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_BlitTexture, uv, mipLevel)

            inline half3 SampleColorBuffer(float2 uv, int lod)
            {
                return SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_BlitTexture, uv, lod);
            }
            
            // 3-Tap Symmetric Weights (Sum up to 1.0)
            static const float CenterWeight = 0.520500f;
            static const float OuterWeight  = 0.239750f;

            float3 GaussianBlur3(float2 uv, float2 offsetDirection)
            {
                float2 offset = _InputTexelSize.xy * offsetDirection;
                float3 momentsL0 = SAMPLE_INPUT_TEX_LOD(uv - offset, _InputMipLevel);
                float3 momentsC0 = SAMPLE_INPUT_TEX_LOD(uv, _InputMipLevel);
                float3 momentsR0 = SAMPLE_INPUT_TEX_LOD(uv + offset, _InputMipLevel);

                return momentsC0 * CenterWeight
                    + (momentsL0 + momentsR0) * OuterWeight;
            }

            half3 GausianBlur3x3(float2 uv, float2 offset)
            {
                half3 color = SampleColorBuffer(uv, _InputMipLevel) * 0.5h;
                color += SampleColorBuffer(uv + offset.xy, _InputMipLevel) * 0.25h;
                color += SampleColorBuffer(uv - offset.xy, _InputMipLevel) * 0.25h;
                return color;
            }
            
            half3 BoxBlur3x3(float2 uv, float2 offset)
            {
                half3 color = SampleColorBuffer(uv, _InputMipLevel);
                color += SampleColorBuffer(uv + offset.xy, _InputMipLevel);
                color += SampleColorBuffer(uv - offset.xy, _InputMipLevel);
                return color * half(0.333334h);
            }

            half3 GausianBlur5x5(float2 uv, float2 offset)
            {
                half3 color = SampleColorBuffer(uv, _InputMipLevel) * 6.0h;
                color += SampleColorBuffer(uv + offset.xy, _InputMipLevel) * 4.0h;
                color += SampleColorBuffer(uv - offset.xy, _InputMipLevel) * 4.0h;
                color += SampleColorBuffer(uv + offset.xy * 2.0f, _InputMipLevel);
                color += SampleColorBuffer(uv - offset.xy * 2.0f, _InputMipLevel);
                return color * half(1.0h / 16.0h);
            }

            half3 Fragment(Varyings input) : SV_TARGET
            {
                float2 offset = _OffsetDirection * _InputTexelSize.xy;
                return GausianBlur3x3(input.uv, offset);
            }
            ENDHLSL
        }
    }
}