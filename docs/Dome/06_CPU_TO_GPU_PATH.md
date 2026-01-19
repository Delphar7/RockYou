# CPU to GPU Path

The math is identical on CPU and GPU.

CPU = reference implementation
GPU = acceleration (Metal)

Steps:
1. Validate CPU mask
2. Freeze math
3. Port distance functions to Metal
4. Replace CPU rasterization
