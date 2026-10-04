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
                half4 color = SampleColorBuffer(input.uv + offset.xy, _InputMipLevel) * 0.25f;
                color += SampleColorBuffer(input.uv + offset.xw, _InputMipLevel) * 0.25f;
                color += SampleColorBuffer(input.uv + offset.zy, _InputMipLevel) * 0.25f;
                color += SampleColorBuffer(input.uv + offset.zw, _InputMipLevel) * 0.25f;

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

            Texture2D<half4> _BlitTexture;
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
            #include "Packages/com.alexmalyutindev.radiance-cascades-urp/ShaderLibrary/Blur.hlsl"

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

            half3 Fragment(Varyings input) : SV_TARGET
            {
                return SampleTent(
                    _BlitTexture,
                    sampler_BlitTexture,
                    _InputTexelSize, 
                    _InputMipLevel,
                    input.positionCS, 
                    _OffsetDirection
                );
            }
            ENDHLSL
        }
    }
}