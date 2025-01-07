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
            Name "Combine"
            ZTest Greater
            ZWrite Off
            Blend One One

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

            TEXTURE2D_X(_BlitTexture);
            TEXTURE2D(_GBuffer0);
            float4 _BlitTexture_TexelSize;
            float3 _CameraForward;

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

                pos.z = UNITY_RAW_FAR_CLIP_VALUE;
                output.positionCS = pos;
                output.texcoord = uv;
                return output;
            }


            half4 Fragment(Varyings input) : SV_TARGET
            {
                // TODO: Bilateral Upsampling.
                // half depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_PointClamp, input.texcoord).x;
                // if (depth == UNITY_RAW_FAR_CLIP_VALUE)
                // {
                //     clip(-1);
                // }

                const float2 temp = input.texcoord * _BlitTexture_TexelSize.zw * 0.5f;
                const float2 w = fmod(temp, 1.0f);
                const int2 coord = floor(temp) * 2.0f;

                float2 uv = (coord + 1.0f) * _BlitTexture_TexelSize.xy;
                float3 offset = float3(_BlitTexture_TexelSize.xy * 2.0f, 0.0f);
                half4 a = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv) * 4;
                half4 b = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + offset.xz) * 4;
                half4 c = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + offset.zy) * 4;
                half4 d = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + offset.xy) * 4;

                // Bilinear Interpolation.
                half4 color = lerp(
                    lerp(a, b, w.x),
                    lerp(c, d, w.x),
                    w.y
                );

                half4 gbuffer0 = SAMPLE_TEXTURE2D(_GBuffer0, sampler_PointClamp, input.texcoord);
                return color * gbuffer0;

                half3 normalWS = SampleSceneNormals(input.texcoord);
                half angleFade = 1.0h - abs(dot(normalWS, -_CameraForward));

                return color * gbuffer0 * angleFade;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Combine3d"
            ZTest Greater
            ZWrite Off
            Blend One One

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

            TEXTURE2D(_GBuffer0);
            TEXTURE2D(_BlitTexture);
            float4 _BlitTexture_TexelSize;
            float3 _CameraForward;

            #if SHADER_API_GLES
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            #else
            struct Attributes
            {
                uint vertexID : SV_VertexID;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            #endif

            struct Varyings
            {
                float2 texcoord : TEXCOORD0;
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                #if SHADER_API_GLES
                float4 pos = input.positionOS;
                float2 uv  = input.uv;
                #else
                float4 pos = GetFullScreenTriangleVertexPosition(input.vertexID);
                float2 uv = GetFullScreenTriangleTexCoord(input.vertexID);
                #endif

                pos.z = UNITY_RAW_FAR_CLIP_VALUE;
                output.positionCS = pos;
                output.texcoord = uv;
                return output;
            }

            float4 SamlpeSampleProbe2x2(float2 uv, half3 normalWS)
            {
                float2 sideOffset = 1.0f / float2(2.0f, 3.0f);

                #if 1
                float2 uvX = normalWS.x < 0 ? uv : uv + sideOffset.xy * float2(1, 0);
                float2 uvY = normalWS.y < 0 ? uv + sideOffset.xy * float2(0, 1) : uv + sideOffset.xy * float2(1, 1);
                float2 uvZ = normalWS.y < 0 ? uv + sideOffset.xy * float2(0, 2) : uv + sideOffset.xy * float2(1, 2);

                float4 x = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uvX, 0) * 4;
                float4 y = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uvY, 0) * 4;
                float4 z = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uvZ, 0) * 4;

                // return x + y + z;

                half3 weight = abs(normalWS);
                weight /= dot(weight, 1.0h);
                return
                    x * weight.x +
                    y * weight.y +
                    z * weight.z;

                #else

                float4 x0 = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv, 0) * 4;
                float4 x1 = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv + sideOffset.xy * float2(1, 0), 0) * 4;

                float4 y0 = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv + sideOffset.xy * float2(0, 1), 0) * 4;
                float4 y1 = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv + sideOffset.xy * float2(1, 1), 0) * 4;

                float4 z0 = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv + sideOffset.xy * float2(0, 2), 0) * 4;
                float4 z1 = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv + sideOffset.xy * float2(1, 2), 0) * 4;

                return x0 + x1 + y0 + y1 + z0 + z1;

                #endif
            }

            half4 Fragment(Varyings input) : SV_TARGET
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                const float2 sideSize = floor(_BlitTexture_TexelSize.zw / float2(2, 3));
                const float probe0Size = 2.0f;
                const float2 probeIndex = input.texcoord * sideSize / probe0Size;
                const float2 w = frac(probeIndex);

                half3 normalWS = normalize(SampleSceneNormals(input.texcoord));

                float2 coords = floor(probeIndex) * probe0Size;
                float2 uv = (coords + 1.0f) * _BlitTexture_TexelSize.xy;

                // BUG: Offset can lead to sampling adjacent side probes!
                float3 offset = float3(_BlitTexture_TexelSize.xy * probe0Size, 0.0f);
                half4 a = SamlpeSampleProbe2x2(uv, normalWS);
                half4 b = SamlpeSampleProbe2x2(uv + offset.xz, normalWS);
                half4 c = SamlpeSampleProbe2x2(uv + offset.zy, normalWS);
                half4 d = SamlpeSampleProbe2x2(uv + offset.xy, normalWS);

                // Bilinear Interpolation.
                half4 color = lerp(
                    lerp(a, b, w.x),
                    lerp(c, d, w.x),
                    w.y
                );

                half4 gbuffer0 = SAMPLE_TEXTURE2D_LOD(_GBuffer0, sampler_PointClamp, input.texcoord, 0);
                return color * gbuffer0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Combine Direction First Intermediate"
            ZTest Off
            ZWrite Off
            Blend One Zero

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
            #include "Common.hlsl"

            TEXTURE2D_X(_BlitTexture);
            TEXTURE2D(_GBuffer0); // Color
            TEXTURE2D(_GBuffer1); // Color
            TEXTURE2D(_GBuffer2); // Normals
            TEXTURE2D(_GBuffer3); // Emmision
            float4 _BlitTexture_TexelSize;
            float3 _CameraForward;

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


            half4 Fragment(Varyings input) : SV_TARGET
            {
                float3 normalWS = SAMPLE_TEXTURE2D_LOD(_GBuffer2, sampler_LinearClamp, input.texcoord, 0);

                // TODO: Bilateral Upsampling.
                // TODO: Fix uv, to trim cascade padding.
                float2 uv = (input.texcoord * _BlitTexture_TexelSize.zw + 4.0f) / (_BlitTexture_TexelSize.zw + 8.0f);
                uv = (uv + float2(0.0f, 7.0f)) / 8.0f;

                float2 horizontalOffset = float2(1.0f / 8.0f, 0.0f);
                float2 verticalOffset = float2(0.0f, 1.0f / 8.0f);

                // TODO: Sample radiance like merging higher cascade!
                half4 color = 0.0f;
                UNITY_UNROLL
                for (int x = 0; x < 8; x++)
                {
                    for (int y = 0; y < 4; y++)
                    {
                        float3 direction = GetRay_DirectionFirst(float2(x, y), 0);
                        float NdotL = saturate(dot(direction, normalWS));

                        float4 radiance = SAMPLE_TEXTURE2D_LOD(
                            _BlitTexture,
                            sampler_LinearClamp,
                            uv + horizontalOffset * x - verticalOffset * y,
                            0
                        );
                        color += radiance * NdotL;
                    }
                }

                return color;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Combine Direction First Final"
            ZTest Off
            ZWrite Off
            Blend One One
            // Blend One Zero

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            TEXTURE2D_X(_BlitTexture);
            TEXTURE2D(_GBuffer0);
            TEXTURE2D(_GBuffer3);
            TEXTURE2D(_MinMaxDepth);
            float4 _BlitTexture_TexelSize;
            float3 _CameraForward;

            float _UpsampleTolerance;
            float _NoiseFilterStrength;

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

                pos.z = UNITY_RAW_FAR_CLIP_VALUE;
                output.positionCS = pos;
                output.texcoord = uv;
                return output;
            }

            // GTAOBlurAndUpsample.compute
            // We essentially want 5 weights:  4 for each low-res pixel and 1 to blend in when none of the 4 really
            // match.  The filter strength is 1 / DeltaZTolerance.  So a tolerance of 0.01 would yield a strength of 100.
            // Note that a perfect match of low to high depths would yield a weight of 10^6, completely superceding any
            // noise filtering.  The noise filter is intended to soften the effects of shimmering when the high-res depth
            // buffer has a lot of small holes in it causing the low-res depth buffer to inaccurately represent it.
            float BilateralUpsample(float HiDepth, float4 LowDepths, float4 LowAO)
            {
                float4 weights = float4(9, 3, 1, 3) / (abs(HiDepth - LowDepths) + _UpsampleTolerance);
                float TotalWeight = dot(weights, 1) + _NoiseFilterStrength;
                float WeightedSum = dot(LowAO, weights) + _NoiseFilterStrength;
                return WeightedSum / TotalWeight;
            }

            float4 BilateralUpsample(float HiDepth, float4 LowDepths, float4 a, float4 b, float4 c, float4 d)
            {
                float4 weights = float4(9, 3, 1, 3) / (abs(HiDepth - LowDepths) + _UpsampleTolerance);
                float TotalWeight = dot(weights, 1.0f) + _NoiseFilterStrength;
                float4 WeightedSum = a * weights.x + b * weights.y + c * weights.z + d * weights.w + _NoiseFilterStrength;
                return WeightedSum / TotalWeight;
            }

            half4 Fragment(Varyings input) : SV_TARGET
            {
                float2 uv = input.texcoord;
                half4 gbuffer0 = SAMPLE_TEXTURE2D_LOD(_GBuffer0, sampler_PointClamp, uv, 0);

                float2 minMaxDepth = SAMPLE_TEXTURE2D_LOD(_MinMaxDepth, sampler_PointClamp, uv, 0).xy;
                float4 sceneDepth = GATHER_TEXTURE2D(_CameraDepthTexture, sampler_PointClamp, uv);


                float3 offset0 = float3(_BlitTexture_TexelSize.xy, 0.0f);
                float4 radianceA = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_PointClamp, uv, 0);
                float4 radianceB = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_PointClamp, uv + offset0.xz, 0);
                float4 radianceC = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_PointClamp, uv + offset0.zy, 0);
                float4 radianceD = SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_PointClamp, uv + offset0.xy, 0);
                
                float4 radiance = BilateralUpsample(minMaxDepth.y, sceneDepth, radianceA, radianceB, radianceC, radianceD);
                return radiance * gbuffer0;

                float4 color = 0;
                float4 offset = 0.64f * float4(1.0f, 1.0f, -1.0f, -1.0f) * _BlitTexture_TexelSize.xyxy;
                color += SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv + offset.xy, 0);
                color += SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv + offset.xw, 0);
                color += SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv + offset.zy, 0);
                color += SAMPLE_TEXTURE2D_LOD(_BlitTexture, sampler_LinearClamp, uv + offset.zw, 0);
                color *= 0.25f;

                return color * gbuffer0;
            }
            ENDHLSL
        }
    }
}