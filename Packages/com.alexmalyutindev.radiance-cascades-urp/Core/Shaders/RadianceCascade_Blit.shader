Shader "Hidden/RadianceCascade/Blit"
{
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }
        LOD 100

        Pass
        {
            Name "0 Blit RadianceSH"
            ZTest Off
            ZWrite Off
            Blend One One

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #pragma target 2.0
            #pragma editor_sync_compilation

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SphericalHarmonics.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.alexmalyutindev.radiance-cascades-urp/ShaderLibrary/Common.hlsl"

            float4 _NextProbesCount;
            float4 _BlitTexture_TexelSize;
            TEXTURE2D_X(_BlitTexture);
            
            Texture2D<float2> _MinMaxDepth;
            TEXTURE2D(_GBuffer0); // Color
            TEXTURE2D(_GBuffer2); // Normals

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 texcoord : TEXCOORD0;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;

                float4 pos = input.positionOS * 2.0f - 1.0f;
                float2 uv = input.uv;

                #if UNITY_UV_STARTS_AT_TOP
                uv.y = 1 - uv.y;
                #endif

                output.positionCS = pos;
                output.texcoord = uv;
                return output;
            }

            half4 LoadSHProbe(int2 probeId, int2 tileOffset, int2 probeCount)
            {
                probeId = clamp(probeId, 0, probeCount - 1);
                return LOAD_TEXTURE2D(_BlitTexture, probeId + tileOffset);
            }

            half4 LoadSH(float2 probeContinuous, int2 tileOffset, int2 probeCount)
            {
                probeContinuous = clamp(probeContinuous, 0.0f, probeCount - 1.0f);
                int2 baseId = min((int2)floor(probeContinuous), probeCount - 2);
                float2 f = probeContinuous - baseId;

                half4 a = LoadSHProbe(baseId, tileOffset, probeCount);
                half4 b = LoadSHProbe(baseId + int2(1, 0), tileOffset, probeCount);
                half4 c = LoadSHProbe(baseId + int2(0, 1), tileOffset, probeCount);
                half4 d = LoadSHProbe(baseId + int2(1, 1), tileOffset, probeCount);

                return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
            }

            half4 Fragment(Varyings input) : SV_TARGET
            {
                int2 coords = floor(input.positionCS.xy);
                half4 gbuffer0 = LOAD_TEXTURE2D_LOD(_GBuffer0, coords, 0);
                // NOTE: if "Accurate G-buffer normals" is enabled in URP, _GBuffer2 is octahedron encoded and must be unpacked.
                float3 normalWS = normalize(LOAD_TEXTURE2D_LOD(_GBuffer2, coords, 0).xyz);

                int2 probeCount = int2(_NextProbesCount.xy);
                int2 tileSize = int2(floor(_BlitTexture_TexelSize.zw * 0.5f));
                float2 probeContinuous = input.texcoord * _NextProbesCount.xy - 0.5f;

                half4 sh0 = LoadSH(probeContinuous, int2(0, 0), probeCount) * kSHBasis0;
                half4 shX = LoadSH(probeContinuous, int2(tileSize.x, 0), probeCount) * kSHBasis1;
                half4 shY = LoadSH(probeContinuous, int2(0, tileSize.y), probeCount) * kSHBasis1;
                half4 shZ = LoadSH(probeContinuous, tileSize, probeCount) * kSHBasis1;

                // DEBUG: show L0 only. If rings are visible here, they come from the tracing, not from this pass.
                // return half4(sh0.rgb * gbuffer0.rgb, 0.0h);

                float3 L0L1 = SHEvalLinearL0L1(
                    normalWS,
                    float4(shX.r, shY.r, shZ.r, sh0.r),
                    float4(shX.g, shY.g, shZ.g, sh0.g),
                    float4(shX.b, shY.b, shZ.b, sh0.b)
                );

                float3 irradianceOverPi = max(float3(0.0f, 0.0f, 0.0f), L0L1);

                // Alpha 0 so the additive blend does not touch the target's alpha (gbuffer0.a holds material flags).
                return half4(irradianceOverPi * gbuffer0.rgb, 0.0h);
            }
            ENDHLSL
        }

        Pass
        {
            Name "1 LoadBlit"
            ZTest Off
            ZWrite Off
            Blend One Zero

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #pragma target 2.0
            #pragma editor_sync_compilation

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float4 _BlitTexture_TexelSize;
            TEXTURE2D_X(_BlitTexture);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 texcoord : TEXCOORD0;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;

                float4 pos = input.positionOS * 2.0f - 1.0f;
                float2 uv = input.uv;

                #if UNITY_UV_STARTS_AT_TOP
                uv.y = 1 - uv.y;
                #endif

                // pos.z = UNITY_RAW_FAR_CLIP_VALUE;
                output.positionCS = pos;
                output.texcoord = uv;
                return output;
            }

            float4 Fragment(Varyings input) : SV_TARGET
            {
                int2 coords = floor(input.positionCS.xy);
                // coords.x += round(_BlitTexture_TexelSize.x * 1.0f);
                coords.y += round(_BlitTexture_TexelSize.w * 1.0f) - round(_ScreenSize.y);
                return (LOAD_TEXTURE2D(_BlitTexture, coords));
            }
            ENDHLSL
        }
    }
}