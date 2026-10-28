// TODO: CleanUP!!!
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

                // pos.z = UNITY_RAW_FAR_CLIP_VALUE;
                output.positionCS = pos;
                output.texcoord = uv;
                return output;
            }

            // The bilateral upscale function (2x2 neighborhood, color4 version)
            float4 BilUpColor(
                float HiDepth,
                float4 LowDepths,
                float4 lowValue0, float4 lowValue1, float4 lowValue2, float4 lowValue3,
                float4 intialWeights
            )
            {
                float _UpsampleTolerance = 1e-5f;
                float _NoiseFilterStrength = 0.9999999f;

                float4 weights = intialWeights / (abs(HiDepth - LowDepths) + _UpsampleTolerance);
                float TotalWeight = dot(weights, 1) + _NoiseFilterStrength;
                float4 WeightedSum =
                    lowValue0 * weights.x
                    + lowValue1 * weights.y
                    + lowValue2 * weights.z
                    + lowValue3 * weights.w
                    + _NoiseFilterStrength;
                return WeightedSum / TotalWeight;
            }

            float4 SampleSHBuffer(float2 uv)
            {
                // TODO: Depth-guided sampling
                return SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv, 0);
            }

            float4 SampleSH(float2 uv, float3 normalWS)
            {
                float2 shUV = uv * 0.5f;
                float4 sh0 = SampleSHBuffer(shUV + float2(0.0f, 0.5f));
                float4 shX = SampleSHBuffer(shUV + float2(0.5f, 0.5f));
                float4 shY = SampleSHBuffer(shUV);
                float4 shZ = SampleSHBuffer(shUV + float2(0.5f, 0.0f));
                float3 L0L1 = SHEvalLinearL0L1(
                    normalWS,
                    float4(shX.r, shY.r, shZ.r, sh0.r),
                    float4(shX.g, shY.g, shZ.g, sh0.g),
                    float4(shX.b, shY.b, shZ.b, sh0.b)
                );
                return float4(max(half3(0.0h, 0.0h, 0.0h), L0L1), 1.0f);
            }

            inline float4 GetSH(int2 coords, float4 weights, float depth, float4 lowerDepth)
            {
                return BilUpColor(
                    depth,
                    lowerDepth,
                    LOAD_TEXTURE2D(_BlitTexture, coords),
                    LOAD_TEXTURE2D(_BlitTexture, coords + int2(1, 0)),
                    LOAD_TEXTURE2D(_BlitTexture, coords + int2(0, 1)),
                    LOAD_TEXTURE2D(_BlitTexture, coords + int2(1, 1)),
                    weights
                );
            }

            float Linear01MinDepth(float2 minMaxDepth)
            {
                minMaxDepth = (minMaxDepth - _ProjectionParams.y) * _ProjectionParams.w;
                return dot(minMaxDepth, 0.5f);

                minMaxDepth = 1.0 / (_ZBufferParams.x * minMaxDepth + _ZBufferParams.y);
                return dot(minMaxDepth, 0.5f);
            }

            float4 SampleSH2(float2 uv, float3 normalWS)
            {
                float depth = Linear01Depth(SampleSceneDepth(uv), _ZBufferParams);

                int2 shSize = floor(_BlitTexture_TexelSize.zw * 0.5f);
                int2 lowerCoords = floor(uv * shSize - 0.5f);

                float2 depth0 = LOAD_TEXTURE2D_LOD(_MinMaxDepth, lowerCoords, 1).xy;
                float2 depth1 = LOAD_TEXTURE2D_LOD(_MinMaxDepth, lowerCoords + int2(1, 0), 1).xy;
                float2 depth2 = LOAD_TEXTURE2D_LOD(_MinMaxDepth, lowerCoords + int2(0, 1), 1).xy;
                float2 depth3 = LOAD_TEXTURE2D_LOD(_MinMaxDepth, lowerCoords + int2(1, 1), 1).xy;
                // float4 lowerDepth = float4(depth0.x, depth1.x, depth2.x, depth3.x);
                float4 lowerDepth = float4(
                    Linear01MinDepth(depth0),
                    Linear01MinDepth(depth1),
                    Linear01MinDepth(depth2),
                    Linear01MinDepth(depth3)
                );

                float2 bilinearWeights = frac(uv * shSize - 0.5f);
                float4 weights = float4(bilinearWeights, 1.0f - bilinearWeights);
                weights = float4(
                    weights.z * weights.w,
                    weights.x * weights.w,
                    weights.z * weights.y,
                    weights.x * weights.y
                );

                float4 sh0 = GetSH(lowerCoords + int2(0, shSize.y), weights, depth, lowerDepth);
                float4 shX = GetSH(lowerCoords + shSize, weights, depth, lowerDepth);
                float4 shY = GetSH(lowerCoords, weights, depth, lowerDepth);
                float4 shZ = GetSH(lowerCoords + int2(shSize.x, 0), weights, depth, lowerDepth);

                float3 L0L1 = SHEvalLinearL0L1(
                    normalWS,
                    float4(shX.r, shY.r, shZ.r, sh0.r),
                    float4(shX.g, shY.g, shZ.g, sh0.g),
                    float4(shX.b, shY.b, shZ.b, sh0.b)
                );
                return float4(max(float3(0.0f, 0.0f, 0.0f), L0L1), 1.0f);
            }
            
            half4 LoadSH(int2 coords, int2 offset, int2 upperBound, half4 bilinearWeights)
            {
                const int2 insideBounds = coords < upperBound - 1;
                coords += offset;
                half4 a = LOAD_TEXTURE2D(_BlitTexture, coords);
                half4 b = LOAD_TEXTURE2D(_BlitTexture, coords + int2(1, 0) * insideBounds);
                half4 c = LOAD_TEXTURE2D(_BlitTexture, coords + int2(0, 1) * insideBounds);
                half4 d = LOAD_TEXTURE2D(_BlitTexture, coords + int2(1, 1) * insideBounds);

                return 
                    a * bilinearWeights.x +
                    b * bilinearWeights.y +
                    c * bilinearWeights.z +
                    d * bilinearWeights.w;
            }
            
            float GetMinMaxDepthThickness(uint2 coords, int depthLevel, float4 bilinearWeights, 
                out float4 lowDepthABCD_min, out float4 lowDepthABCD_max)
            {
                static const int2 neighbours[4] = {int2(0, 0), int2(1, 0), int2(0, 1), int2(1, 1)};

                float2 minMaxDepthBilinear = float2(0.0f, 0.0f);
                UNITY_UNROLL for (int i = 0; i < 4; i++)
                {
                    // TODO: Coors clamping
                    float2 minMaxDepth = LOAD_TEXTURE2D_LOD(_MinMaxDepth, coords + neighbours[i], depthLevel);
                    lowDepthABCD_min[i] = minMaxDepth.x;
                    lowDepthABCD_max[i] = minMaxDepth.y;
                    // minMaxDepthBilinear += minMaxDepth * bilinearWeights[i];
                }

                minMaxDepthBilinear.x = dot(lowDepthABCD_min, bilinearWeights);
                minMaxDepthBilinear.y = dot(lowDepthABCD_max, bilinearWeights);

                float depthThickness = max(0.0001f, abs(minMaxDepthBilinear.y - minMaxDepthBilinear.x));
                return depthThickness;
            }

            half4 Fragment(Varyings input) : SV_TARGET
            {
                int2 coords = floor(input.positionCS.xy);
                half4 gbuffer0 = LOAD_TEXTURE2D_LOD(_GBuffer0, coords, 0);
                float3 normalWS = LOAD_TEXTURE2D_LOD(_GBuffer2, coords, 0).xyz;
                float depth = LinearEyeDepth(LoadSceneDepth(coords), _ZBufferParams); 

                float2 lowProbeContinuous = input.texcoord * _NextProbesCount.xy - 0.5f;
                int2 lowProbeBaseId = (int2)floor(lowProbeContinuous);
                float2 bilinearOffsets = frac(lowProbeContinuous);
                float4 bilinearWeights = float4(bilinearOffsets, 1.0f - bilinearOffsets);
                bilinearWeights = bilinearWeights.zxzx * bilinearWeights.wwyy;

                float4 lowDepthABCD_min;
                float4 lowDepthABCD_max;
                float depthThickness = GetMinMaxDepthThickness(lowProbeBaseId, 0, bilinearWeights, lowDepthABCD_min, lowDepthABCD_max);
                // TODO: SH contains only 1 slice of probes, blending is a bit awkward here.
                float4 lowDepthABCD = (lowDepthABCD_min + lowDepthABCD_max) * 0.5f;
                
                const float sharpness = 10.0f;
                half4 probeWeights = exp2(-sharpness * depthThickness * abs(depth - lowDepthABCD)) + 0.0001f;
                probeWeights = NormalizeWeights(probeWeights * bilinearWeights);

                int2 cascadeSize = floor(_BlitTexture_TexelSize.zw * 0.5f);
                int3 offsets = int3(cascadeSize, 0);
                half4 sh0 = LoadSH(lowProbeBaseId, int2(0, 0), cascadeSize.xy, bilinearWeights);
                half4 shX = LoadSH(lowProbeBaseId, offsets.xz, cascadeSize.xy, bilinearWeights);
                half4 shY = LoadSH(lowProbeBaseId, offsets.zy, cascadeSize.xy, bilinearWeights);
                half4 shZ = LoadSH(lowProbeBaseId, offsets.xy, cascadeSize.xy, bilinearWeights);

                float3 L0L1 = SHEvalLinearL0L1(
                    normalWS,
                    float4(shX.r, shY.r, shZ.r, sh0.r),
                    float4(shX.g, shY.g, shZ.g, sh0.g),
                    float4(shX.b, shY.b, shZ.b, sh0.b)
                );
                float4 radiance = float4(max(float3(0.0f, 0.0f, 0.0f), L0L1), 1.0f);
                
                return radiance * gbuffer0;
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