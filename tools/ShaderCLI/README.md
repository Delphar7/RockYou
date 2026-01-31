# ShaderCLI — Metal Compute Debugging Harness

Run Metal compute kernels from the command line to debug GPU math without Xcode or RealityKit.

## Quick Start

```bash
# 1. Build the metallib from project shaders
./tools/ShaderCLI/build_metallib.sh

# 2. Copy the template and customize it
cp tools/ShaderCLI/ShaderRunTemplate.swift /tmp/my_debug.swift
# Edit the CUSTOMIZE sections: params struct, output struct, kernel name
swift /tmp/my_debug.swift
```

## Files

| File | Purpose |
|------|---------|
| `build_metallib.sh` | Compiles `RockYou/UI/Shaders/*.metal` → `/tmp/metal_build/RockYou.metallib` |
| `ShaderRunTemplate.swift` | Copy-and-customize template with all Metal boilerplate |
| `examples/seam_debug.swift` | Calls `halfSpaceComputeSeamArcs`, prints per-blade arc geometry |
| `examples/seam_diag.swift` | Reads intermediate values from a diagnostic kernel |

## Workflow

1. **Write a compute kernel** in a `.metal` file (or add to an existing one) that calls the algorithm functions you want to test. No RealityKit dependency — just `metal_stdlib` + your algorithm header.

2. **Build the metallib** with `build_metallib.sh`. RealityKit-dependent shaders are skipped automatically.

3. **Copy the template**, fill in the `// CUSTOMIZE:` sections to match your kernel's params and output structs, and run with `swift`.

4. **For deeper debugging**, add a diagnostic kernel that writes intermediate values into a flat struct (see `examples/seam_diag.swift`). This is the GPU equivalent of printf debugging.

## Struct Layout Rules

Swift structs passed to Metal must match layout exactly:

| Metal | Swift | Size | Stride |
|-------|-------|------|--------|
| `int` | `Int32` | 4 | 4 |
| `float` | `Float` | 4 | 4 |
| `float2` | `SIMD2<Float>` | 8 | 8 |
| `float3` | `SIMD3<Float>` | 12 | **16** |
| `float4` | `SIMD4<Float>` | 16 | 16 |

Verify with `MemoryLayout<YourStruct>.stride` — it must match Metal's `sizeof()`.
