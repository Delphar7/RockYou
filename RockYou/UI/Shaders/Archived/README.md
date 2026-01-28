# Archived Shaders

Shaders with interesting techniques that are no longer in active use.
Preserved for reference/future use.

## DomeSurfaceShader.metal

**Technique:** Ray-plane intersection for texture compositing through glass.

Traces a ray from camera through each fragment to a virtual backdrop plane,
samples DPad textures at the intersection point, and composites them based
on glass opacity. Creates realistic see-through effect.

Key concepts:
- Ray from camera through fragment: `rayDir = normalize(fragPos - cameraPos)`
- Ray-plane intersection: `t = (planeY - fragPos.y) / rayDir.y`
- Hit point to UV conversion for texture sampling
- Blend between "regular" and "refracted" textures based on glass thickness

Could be useful for showing content through dome fragments in the future.
