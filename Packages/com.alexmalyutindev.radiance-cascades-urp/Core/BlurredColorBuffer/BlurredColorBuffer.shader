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
            Name "DownSampleColorBlurredHorizontal"
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
                float2 offset = float2(_InputSizeTexel.z, 0.0f);

                half4 color = SampleColorBuffer(input.uv, _InputMipLevel) * 0.5h;
                color += SampleColorBuffer(input.uv + offset.xy, _InputMipLevel) * 0.25h;
                color += SampleColorBuffer(input.uv - offset.xy, _InputMipLevel) * 0.25h;

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
                float2 offset = float2(0.0f, _InputSizeTexel.w);

                half4 color = SampleColorBuffer(input.uv, _InputMipLevel) * 0.5h;
                color += SampleColorBuffer(input.uv + offset.xy, _InputMipLevel) * 0.25h;
                color += SampleColorBuffer(input.uv - offset.xy, _InputMipLevel) * 0.25h;

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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            SAMPLER(sampler_BlitTexture);
            Texture2D<half4> _BlitTexture;
            float4 _BlitTexture_TexelSize;
            float4 _InputSizeTexel;
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

            inline half3 SampleColorBuffer(float2 uv, int lod)
            {
                return SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_BlitTexture, uv, lod);
            }
            
            half3 BoxBlur3x3(float2 uv, float2 offset)
            {
                half3 color = SampleColorBuffer(uv, _InputMipLevel);
                color += SampleColorBuffer(uv + offset.xy, _InputMipLevel);
                color += SampleColorBuffer(uv - offset.xy, _InputMipLevel);
                return color * half(0.333334h);
            }

            half3 GausianBlur3x3(float2 uv, float2 offset)
            {
                half3 color = SampleColorBuffer(uv, _InputMipLevel) * 2.0h;
                color += SampleColorBuffer(uv + offset.xy, _InputMipLevel);
                color += SampleColorBuffer(uv - offset.xy, _InputMipLevel);
                return color * half(1.0h / 4.0h);
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
                float2 offset = _OffsetDirection * _InputSizeTexel.zw;
                return BoxBlur3x3(input.uv, offset);
            }
            ENDHLSL
        }
    }
}