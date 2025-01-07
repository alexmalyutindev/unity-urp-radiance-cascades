using System;
using UnityEngine;
using UnityEngine.Rendering;

namespace AlexMalyutinDev.RadianceCascades.Voxelization
{
    public class VoxelizatorCompute : IDisposable
    {
        private readonly ComputeShader _compute;
        private readonly int _clearKernel;
        private readonly int _clear3dKernel;
        private readonly int _parametrizeKernel;
        private readonly int _consumeKernel;
        private readonly int _aggregateKernel;

        private readonly ComputeBuffer _consumeKernelArguments;
        private readonly int _renderKernelX;
        private readonly int _renderKernelY;
        private readonly int _renderKernelZ;

        private bool _initialized;

        // Intermediate buffer for Buffer to Texture3D conversion
        private ComputeBuffer _volumeRGBuffer;
        private ComputeBuffer _volumeBABuffer;
        private ComputeBuffer _volumeCountBuffer;

        public VoxelizatorCompute(ComputeShader compute)
        {
            _compute = compute;

            _clearKernel = compute.FindKernel("CSClear");
            _clear3dKernel = compute.FindKernel("CSClear3d");
            _consumeKernel = compute.FindKernel("CSConsume");
            _parametrizeKernel = compute.FindKernel("CSParameterize");
            _aggregateKernel = compute.FindKernel("CSAggregate");

            // BUG: Memory leak!
            _consumeKernelArguments = new ComputeBuffer(3, sizeof(int), ComputeBufferType.IndirectArguments);
            _consumeKernelArguments.SetData(new int[] { 1, 1, 1 });

            _compute.GetKernelThreadGroupSizes(_aggregateKernel, out var x, out var y, out var z);
            _renderKernelX = (int) x;
            _renderKernelY = (int) y;
            _renderKernelZ = (int) z;
        }

        public void Prepare(int resolution)
        {
            if (_initialized) CleanUp();

            int volumeResolution = resolution * resolution * resolution;
            _volumeRGBuffer = new ComputeBuffer(
                volumeResolution,
                sizeof(uint),
                ComputeBufferType.Default,
                ComputeBufferMode.Immutable
            );
            _volumeBABuffer = new ComputeBuffer(
                volumeResolution,
                sizeof(uint),
                ComputeBufferType.Default,
                ComputeBufferMode.Immutable
            );
            _volumeCountBuffer = new ComputeBuffer(
                volumeResolution,
                sizeof(uint),
                ComputeBufferType.Default,
                ComputeBufferMode.Immutable
            );
            _initialized = true;
        }

        public void Dispatch(CommandBuffer cmd, int resolution, ComputeBuffer rawVoxelsBuffer, RTHandle target)
        {
            if (!_initialized) Prepare(resolution);

            cmd.SetComputeIntParam(_compute, "Resolution", resolution);

            ClearTempBuffers(cmd, resolution);
            ConsumeVoxels(cmd, rawVoxelsBuffer);
            AggregateVoxels(cmd, resolution, target);
        }

        public void CleanUp()
        {
            _initialized = false;
            _volumeRGBuffer?.Release();
            _volumeBABuffer?.Release();
            _volumeCountBuffer?.Release();
        }

        private void ClearTempBuffers(CommandBuffer cmd, int resolution)
        {
            const string tag = "Voxel." + nameof(ClearTempBuffers);

            cmd.BeginSample(tag);

            cmd.SetComputeBufferParam(_compute, _clearKernel, "VolumeRG", _volumeRGBuffer);
            cmd.SetComputeBufferParam(_compute, _clearKernel, "VolumeBA", _volumeBABuffer);
            cmd.SetComputeBufferParam(_compute, _clearKernel, "VolumeCount", _volumeCountBuffer);

            var clearThreads = Mathf.CeilToInt(resolution / 4f);
            cmd.DispatchCompute(_compute, _clearKernel, clearThreads, clearThreads, clearThreads);

            cmd.EndSample(tag);
        }

        public void ClearTexture3d(CommandBuffer cmd, RTHandle volume)
        {
            var resolution = volume.rt.width;
            var threadGroups = resolution / 4;
            cmd.SetComputeIntParam(_compute, "Resolution", resolution);
            cmd.SetComputeTextureParam(_compute, _clear3dKernel, "Target", volume);
            cmd.DispatchCompute(_compute, _clear3dKernel, threadGroups, threadGroups, threadGroups);
        }

        private void ConsumeVoxels(CommandBuffer cmd, ComputeBuffer rawVoxelsBuffer)
        {
            const string tag = "Voxel." + nameof(ConsumeVoxels);

            cmd.BeginSample(tag);

            // Compute threads count
            cmd.CopyCounterValue(rawVoxelsBuffer, _consumeKernelArguments, dstOffsetBytes: 0);
            cmd.SetComputeIntParams(_compute, "NumThreads", _renderKernelX, _renderKernelY, _renderKernelZ);
            cmd.SetComputeBufferParam(_compute, _parametrizeKernel, "Arguments", _consumeKernelArguments);
            cmd.DispatchCompute(_compute, _parametrizeKernel, 1, 1, 1);

            // Consume raw voxel buffer into [RG,BA,Count] buffers.
            cmd.SetComputeBufferParam(_compute, _consumeKernel, "VolumeRG", _volumeRGBuffer);
            cmd.SetComputeBufferParam(_compute, _consumeKernel, "VolumeBA", _volumeBABuffer);
            cmd.SetComputeBufferParam(_compute, _consumeKernel, "VolumeCount", _volumeCountBuffer);

            cmd.SetComputeBufferParam(_compute, _consumeKernel, "VoxelBuffer", rawVoxelsBuffer);
            cmd.DispatchCompute(_compute, _consumeKernel, _consumeKernelArguments, argsOffset: 0);

            cmd.EndSample(tag);
        }

        private void AggregateVoxels(CommandBuffer cmd, int resolution, RTHandle target)
        {
            const string tag = "Voxel." + nameof(AggregateVoxels);

            cmd.BeginSample(tag);

            cmd.SetComputeBufferParam(_compute, _aggregateKernel, "VolumeRG", _volumeRGBuffer);
            cmd.SetComputeBufferParam(_compute, _aggregateKernel, "VolumeBA", _volumeBABuffer);
            cmd.SetComputeBufferParam(_compute, _aggregateKernel, "VolumeCount", _volumeCountBuffer);

            cmd.SetComputeTextureParam(_compute, _aggregateKernel, "Target", target);

            var aggregateThreads = Mathf.CeilToInt(resolution / 4f);
            cmd.DispatchCompute(_compute, _aggregateKernel, aggregateThreads, aggregateThreads, aggregateThreads);

            cmd.EndSample(tag);
        }

        public void Dispose()
        {
            _consumeKernelArguments?.Dispose();
            _volumeRGBuffer?.Dispose();
            _volumeBABuffer?.Dispose();
            _volumeCountBuffer?.Dispose();
        }
    }
}
