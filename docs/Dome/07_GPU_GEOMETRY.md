# GPU Geometry Approach

Carve the iris pattern from the hemisphere mesh using GPU shaders.

## Concept

Instead of painting a texture onto a static hemisphere, use vertex/geometry shaders to sculpt the mesh itself:

- **Input**: Same hemisphere mesh every frame
- **Output**: Modified geometry with aperture hole and optional raised seams

No dynamic mesh construction on CPU. The GPU evaluates iris math per-vertex.

## Pipeline

```
Hemisphere mesh → Vertex Shader → Geometry Shader → Fragment Shader
                      ↓                 ↓                 ↓
              Transform to       Discard aperture    Glass material
              blade-local        triangles, maybe    + seam coloring
              coords             displace seams
```

## Per-Vertex Evaluation

For each vertex at position `p` on the hemisphere:

1. Project to disc coords (same UV mapping as texture approach)
2. Compute `IrisFrame` from animation parameter `t`
3. For each blade `i`, call `evalBlade(p, i, frame)`
4. Find `minSignedDist` across all blades
5. Use signed distance to determine fate:
   - `signedDist < -threshold` → covered (keep, glass material)
   - `signedDist > threshold` → aperture (discard or alpha-kill)
   - Near zero → seam region

## Aperture Handling

Option A: **Geometry Shader Discard**
- Geometry shader receives triangles
- If all 3 vertices are in aperture region → emit nothing
- Creates true hole in mesh

Option B: **Alpha Discard in Fragment**
- Fragment shader sets `discard` for aperture pixels
- Simpler, but no true geometry hole

## Seam Options

**Option 1: Vertex Displacement**
- Vertices near seam edges displaced outward along normal
- Creates 3D ridges that catch light naturally
- Requires sufficient mesh tessellation

**Option 2: Fragment Shader Only**
- Seams rendered as brighter/more opaque in fragment shader
- Same as current texture approach, no geometric depth
- Simpler, lower mesh requirements

**Option 3: Hybrid**
- Coarse displacement for major ridges
- Fragment shader for fine seam detail

TBD which approach based on visual requirements.

## Advantages Over Texture

- True aperture hole (not just alpha transparency)
- Blade surfaces can have thickness/depth
- Seams cast real shadows
- Lighting responds to actual surface orientation
- No texture resolution limits

## Mesh Requirements

Current hemisphere: 22 theta × 96 phi segments

For vertex displacement to look smooth, may need higher tessellation near seam regions. Options:
- Increase base mesh density
- Use tessellation shaders for adaptive detail
- Accept coarser seam ridges

## Implementation Order

1. First: GPU texture generation (port current CPU math to compute shader)
2. Then: Geometry approach (this doc)
   - Start with fragment-only seams (Option 2)
   - Add vertex displacement if visual quality requires it
   - Consider tessellation for smooth ridges

## Shader Uniforms

```metal
struct IrisUniforms {
  float t;              // Animation progress
  int bladeCount;
  float pivotRadius;
  float bladeRotMax;
  float edgeInnerRadius;
  float edgeOuterRadius;
  float arcSagitta;
  // ... other config params
};
```

## Reference

The iris math in `DomeIrisAnimation.swift`:
- `makeFrame()` → precompute per-frame constants
- `evalBlade()` → per-vertex blade evaluation
- `IrisFrame` struct → shader uniforms
