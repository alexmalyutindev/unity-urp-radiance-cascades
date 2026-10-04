using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace AlexMalyutinDev.RadianceCascades
{
    public class BlitUtils
    {
        private static readonly int BlitTextureId = Shader.PropertyToID("_BlitTexture");
        private static readonly int InputMipLevelId = Shader.PropertyToID("_InputMipLevel");
        private static readonly int InputTexelSizeId = Shader.PropertyToID("_InputTexelSize");

        private static Mesh _quadMesh;
        private static MaterialPropertyBlock _props;

        public static void Blit(CommandBuffer cmd, Material material, int pass)
        {
            Initialize();
            cmd.DrawMesh(_quadMesh, Matrix4x4.identity, material, 0, pass);
        }

        public static void Blit(RasterCommandBuffer cmd, Material material, int pass)
        {
            Initialize();
            cmd.DrawMesh(_quadMesh, Matrix4x4.identity, material, 0, pass);
        }

        public static void BlitTexture(CommandBuffer cmd, Texture texture, Material material, int pass)
        {
            Initialize();
            _props ??= new MaterialPropertyBlock();
            _props.Clear();
            _props.SetTexture(BlitTextureId, texture);
            cmd.DrawMesh(_quadMesh, Matrix4x4.identity, material, 0, pass, _props);
        }

        public static void BlitTexture(RasterCommandBuffer cmd, TextureHandle texture, Material material, int pass)
        {
            Initialize();
            _props ??= new MaterialPropertyBlock();
            _props.Clear();
            _props.SetTexture(BlitTextureId, texture);
            cmd.DrawMesh(_quadMesh, Matrix4x4.identity, material, 0, pass, _props);
        }

        public static void GenerateMips(
            CommandBuffer cmd,
            TextureHandle texture,
            TextureHandle temp,
            Material material,
            int baseWidth,
            int baseHeight,
            int totalMipCount,
            int downsamplePassIndex = 0)
        {
            int width = baseWidth;
            int height = baseHeight;

            for (int mip = 0; mip < totalMipCount - 1; mip++)
            {
                int nextWidth = Mathf.Max(1, width >> 1);
                int nextHeight = Mathf.Max(1, height >> 1);

                cmd.SetGlobalVector(InputTexelSizeId, new Vector4(1.0f / width, 1.0f / height, width, height));
                cmd.SetGlobalInteger(InputMipLevelId, mip);

                cmd.SetRenderTarget(temp, mip + 1, CubemapFace.Unknown, -1);
                BlitTexture(cmd, texture, material, downsamplePassIndex);

                cmd.CopyTexture(
                    src: temp, srcElement: 0, srcMip: mip + 1, srcX: 0, srcY: 0, srcWidth: nextWidth,
                    srcHeight: nextHeight,
                    dst: texture, dstElement: 0, dstMip: mip + 1, dstX: 0, dstY: 0
                );

                width = nextWidth;
                height = nextHeight;
            }
        }

        public static void Initialize()
        {
            if (!_quadMesh)
            {
                /*UNITY_NEAR_CLIP_VALUE*/
                float nearClipZ = -1;
                if (SystemInfo.usesReversedZBuffer)
                {
                    nearClipZ = 1;
                }

                _quadMesh = new Mesh();
                _quadMesh.vertices = GetQuadVertexPosition(nearClipZ);
                _quadMesh.uv = GetQuadTexCoord();
                _quadMesh.triangles = new int[6] { 0, 1, 2, 0, 2, 3 };
            }
        }

        // Should match Common.hlsl
        public static Vector3[] GetQuadVertexPosition(float z /*= UNITY_NEAR_CLIP_VALUE*/)
        {
            var r = new Vector3[4];
            for (uint i = 0; i < 4; i++)
            {
                uint topBit = i >> 1;
                uint botBit = (i & 1);
                float x = topBit;
                float y = 1 - (topBit + botBit) & 1; // produces 1 for indices 0,3 and 0 for 1,2
                r[i] = new Vector3(x, y, z);
            }

            return r;
        }

        // Should match Common.hlsl
        public static Vector2[] GetQuadTexCoord()
        {
            var r = new Vector2[4];
            for (uint i = 0; i < 4; i++)
            {
                uint topBit = i >> 1;
                uint botBit = (i & 1);
                float u = topBit;
                float v = (topBit + botBit) & 1; // produces 0 for indices 0,3 and 1 for 1,2
                if (SystemInfo.graphicsUVStartsAtTop)
                    v = 1.0f - v;

                r[i] = new Vector2(u, v);
            }

            return r;
        }
    }
}