# Dome Iris: 3D Mesh & Explosion System

Design document for replacing the texture-based dome iris with 3D blade meshes, enabling both smooth aperture animation and touch-triggered shatter effects.

## Goals

- **Visual style**: Clean, sci-fi aesthetic. Smooth motion, precise timing.
- **Aperture animation**: Blades open/close with satisfying mechanical feel.
- **Shatter on touch**: User touches aperture opening, dome explodes into tumbling fragments.
- **Parameterized**: Tunable values for experimentation before locking down the "feel."

---

## Part 1: Blade Mesh Geometry

### Blade Shape

Each blade is a 3D mesh forming one segment of the iris. Shape options:

- **Curved wedge**: Arc segment matching current 2D iris blade profile
- **Tapered petal**: Wider at outer edge, narrow at pivot
- **Angular shard**: More geometric/crystalline

Start with curved wedge to match existing aesthetic, parameterize for later experimentation.

### Mesh Properties

- **Thickness**: Blades have volume (not paper-thin). Suggested: 0.5-2% of dome radius.
- **Bevel**: Slight edge bevel to catch rim lighting.
- **Double-sided rendering**: Required for shatter (fragments tumble, both sides visible).
- **Material**:
  - Front face: Glass (translucent, tinted, slight refraction)
  - Back face: Metal (reflective, subtle brushed texture)

### Blade Count

Parameterized. Default: 8-12 blades. Fewer = chunkier shards on explode. More = finer, more "mechanical."

### Coordinate System

Blades defined in dome-local space:
- Origin at dome center
- Blades arranged radially, covering hemisphere from base plane to pole
- Each blade spans from rim (θ=90°) toward pole (θ approaching 0°)

---

## Part 2: Aperture Animation

### Motion Model

Blades rotate around pivot points to open/close the aperture.

**Pivot placement**: Near outer edge of blade (close to dome rim). Allows blade to sweep inward toward pole when closing.

**Rotation direction**: All blades rotate in same direction (e.g., all clockwise when viewed from above). Creates unified mechanical motion.

### Animation Parameter

Single normalized value `t`:
- `t = 0`: Fully closed (blades meet at pole, aperture sealed)
- `t = 1`: Fully open (blades retracted to rim, aperture clear)

### Motion Curve

Smooth easing. Suggested: cubic ease-in-out or sine.

```
t_eased = t * t * (3 - 2 * t)  // smoothstep
```

All blades move in sync (no stagger for sci-fi clean look).

### Parameterizable Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `bladeCount` | Number of iris blades | 10 |
| `pivotRadius` | Distance from dome center to pivot (normalized) | 0.85 |
| `rotationRange` | Total blade rotation from closed to open (radians) | 1.2 |
| `animationDuration` | Time for full open/close (seconds) | 0.4 |
| `easingFunction` | Motion curve type | smoothstep |

### Future: Unwinding Variant

Once basic aperture works, experiment with:
- Spiral motion (rotate + radial translate)
- Fold-back (blades hinge onto dome surface)
- Slide-retract (blades slide into rim housing)

Keep animation system parameterized to support these variants.

---

## Part 3: Shatter/Explosion System

Triggered when user touches the aperture opening.

### Fragment Generation

**Source geometry**: Triangles from blade meshes.

**Pre-computation**:
- Calculate triangle count per blade at mesh creation time
- On shatter, spawn fragments proportional to visible blade area
- If iris is 50% open, ~50% fewer fragments (blades partially retracted)

**Fragment mesh**: Each fragment is a single triangle (or small triangle group for chunkier pieces).

### Fragment Properties

Each fragment particle has:

| Property | Description |
|----------|-------------|
| `position` | Starts at original triangle location on dome |
| `velocity` | Initial velocity vector (see below) |
| `gravity` | Per-fragment gravity value (randomized from range) |
| `rotation` | Current orientation quaternion |
| `angularVelocity` | Constant spin axis + rate |
| `material` | Metal (front) / Glass (back) |

### Initial Velocity

**Direction**: Outward from dome center + upward bias + random spread.

**Magnitude**: Random from range, biased by distance from touch point (closer = faster).

**Inherited spin**: Fragments inherit angular momentum from blade's rotation at moment of shatter. If blade was sweeping clockwise, its fragments fling tangentially in that direction.

```
fragmentVelocity = outwardDirection * baseSpeed
                 + upVector * upwardBias
                 + randomSpread
                 + bladeTangentialVelocity
```

### Gravity

Each fragment gets random gravity value from range (e.g., 0.5 to 1.5 × base gravity).

**Purpose**: Variation in fall rates creates organic spread. Lighter pieces linger, heavier pieces drop fast.

### Rotation/Tumble

**Angular velocity**: Random axis, random magnitude from range. Constant throughout flight (no damping needed).

**Visual payoff**: As triangles spin, they alternate between showing metal and glass faces. Creates glitter/shimmer effect without complex shaders.

### Clip Plane

The dome sits on a base plane. This plane acts as a kill boundary for fragments.

**Behavior**: When fragment position crosses below the plane, it is removed from simulation. No fade, no bounce - just gone.

**Rationale**: Simple, clean. Fragments "fall through the floor" naturally. Avoids accumulation or complex ground collision.

### Parameterizable Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `baseSpeed` | Base outward velocity | 2.0 |
| `upwardBias` | Upward velocity component | 1.0 |
| `spreadAngle` | Random cone spread (radians) | 0.5 |
| `gravityRange` | Min/max gravity multiplier | (0.5, 1.5) |
| `spinRateRange` | Min/max angular velocity (rad/s) | (2.0, 8.0) |
| `inheritedSpinScale` | How much blade motion transfers to fragments | 0.5 |

---

## Part 4: Implementation Notes

### Mesh Generation

Generate blade meshes procedurally:
1. Define blade profile curve (inner edge, outer edge)
2. Sweep around blade's arc span
3. Extrude for thickness
4. Add end caps
5. Compute normals, assign front/back material IDs

### Animation Update Loop

```
for each blade:
    angle = bladeBaseAngle + rotationRange * ease(t)
    blade.transform = rotationAroundPivot(angle)
```

### Shatter Trigger

On touch event intersecting aperture:
1. Freeze current blade positions
2. For each blade, for each triangle:
   - Spawn fragment at triangle world position
   - Compute initial velocity (outward + up + inherited spin)
   - Assign random gravity, spin axis, spin rate
3. Hide original blade meshes
4. Run fragment simulation

### Fragment Update Loop

```
for each fragment:
    velocity.y -= gravity * dt
    position += velocity * dt
    rotation += angularVelocity * dt

    if position.y < clipPlaneY:
        remove fragment
```

### Performance Considerations

- **Fragment count**: Cap at reasonable maximum (e.g., 500-1000 triangles total)
- **Hybrid LOD**: Far fragments could become billboards or just disappear
- **Shader**: Single draw call with instancing if possible

---

## Part 5: Open Questions

1. **Touch detection**: Raycast against aperture opening, or simpler distance-from-center check?
2. **Sound**: Shatter needs audio. Glass break? Metallic ping? Sci-fi whoosh?
3. **Secondary particles**: Dust, sparks, or energy wisps on shatter? Or keep clean?
4. **Reassembly**: Should dome be able to reform? (Time reverse the explosion?)
5. **Partial shatter**: Touch edge = only nearby blades explode? Or always full dome?

---

## Part 6: Shatter Wave Propagation

Instead of all fragments spawning simultaneously, the explosion radiates outward from touch point like a waterdrop ripple.

### Concept

Touch point defines wave origin. Wave expands as a sphere (or circle on dome surface). Fragments spawn when the wave reaches them.

### Implementation

**Wave state**:
- `waveOrigin`: Touch point on dome surface
- `waveRadius`: Current radius of wave front (starts at 0, grows over time)
- `waveSpeed`: How fast wave expands (parameterized)

**Per-fragment spawn check**:
```
distanceFromTouch = geodesicDistance(fragment.origin, waveOrigin)
// or simpler: Euclidean distance

if waveRadius >= distanceFromTouch and not fragment.spawned:
    spawn fragment with initial velocity
    fragment.spawned = true
```

**Visual result**: Explosion cascades across dome surface. Fragments near touch point fly first, far side of dome shatters last.

### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `waveSpeed` | Expansion rate (units/sec) | 3.0 |
| `waveDuration` | Time for wave to cross full dome | ~0.3s |

### Velocity Direction Refinement

With wave propagation, fragment velocity can be biased away from wave origin (not just dome center). Creates more realistic "blast" directionality.

```
blastDirection = normalize(fragment.position - waveOrigin)
velocity = blastDirection * speed + upBias + inherited + random
```

---

## Part 7: Development Plan

Phased approach with clear validation checkpoints. Each phase produces visible, testable results.

---

### Phase 1: Static Blade Meshes

**Goal**: Render blade meshes on dome in closed position.

**Tasks**:
1. Define blade profile geometry (arc segment with thickness)
2. Generate mesh for single blade (vertices, indices, normals)
3. Replicate around dome (N blades evenly spaced)
4. Render with basic material (single color, both sides visible)

**Validation checkpoint**:
> You see a dome covered by N wedge-shaped blade meshes arranged radially. They form a closed surface meeting at the pole. Blades have visible thickness. Rotate the view to confirm geometry looks solid from all angles.

**Tuning opportunity**: Blade count, thickness, profile curve.

---

### Phase 2: Dual-Sided Material

**Goal**: Blades show different material on front vs back face.

**Tasks**:
1. Assign material IDs to front/back faces (or use face normal to select)
2. Create glass material (tinted, semi-transparent)
3. Create metal material (reflective, opaque)
4. Render with correct material per face

**Validation checkpoint**:
> Rotate camera inside and outside the dome. Outside shows glass faces (translucent). Inside shows metal faces (reflective). The two materials are clearly distinct.

**Tuning opportunity**: Glass tint/opacity, metal reflectivity.

---

### Phase 3: Aperture Animation

**Goal**: Blades rotate to open/close aperture.

**Tasks**:
1. Define pivot point per blade (near outer edge)
2. Implement rotation transform around pivot
3. Drive rotation from animation parameter `t` (0=closed, 1=open)
4. Apply easing function to `t`
5. Wire up UI control (slider or auto-animate loop)

**Validation checkpoint**:
> Slide `t` from 0 to 1. Blades smoothly rotate outward, revealing aperture at pole. Motion is clean and synchronized. At t=1, aperture is fully clear. Reverse to close. No jitter, no gaps between blades at closed position.

**Tuning opportunity**: Pivot placement, rotation range, easing curve, animation speed.

---

### Phase 4: Basic Shatter (All At Once)

**Goal**: Touch triggers explosion, all fragments spawn simultaneously.

**Tasks**:
1. Extract triangles from blade meshes
2. On touch, spawn fragment per triangle at original position
3. Assign random velocity (outward + up + spread)
4. Assign random gravity, random spin axis/rate
5. Run fragment simulation (position += velocity, velocity.y -= gravity)
6. Render fragments as triangles with dual-sided material

**Validation checkpoint**:
> Touch the aperture. All blade geometry instantly converts to flying triangles. Fragments fly outward and upward, then arc downward. Each fragment tumbles, flashing between glass and metal as it spins. Visually chaotic but coherent.

**Tuning opportunity**: Base velocity, spread angle, gravity range, spin rate range.

---

### Phase 5: Clip Plane

**Goal**: Fragments disappear when they fall below dome base.

**Tasks**:
1. Define clip plane Y position (dome base)
2. In fragment update, check position.y < clipPlaneY
3. Remove fragment from simulation when crossed

**Validation checkpoint**:
> Trigger shatter, watch fragments fall. As each fragment crosses the base plane, it vanishes cleanly. No accumulation on floor. After a few seconds, all fragments gone.

**Tuning opportunity**: Clip plane position (if dome is elevated).

---

### Phase 6: Inherited Blade Spin

**Goal**: Fragments inherit angular momentum from blade motion.

**Tasks**:
1. Track blade angular velocity during animation
2. On shatter, compute tangential velocity at each triangle's position
3. Add tangential component to fragment's initial velocity

**Validation checkpoint**:
> Trigger shatter while iris is mid-animation (partially open, blades still moving). Fragments fling tangentially in direction of blade motion, not just radially outward. If blade was sweeping clockwise, fragments spray clockwise-biased.

**Tuning opportunity**: Inherited spin scale factor.

---

### Phase 7: Wave Propagation

**Goal**: Explosion radiates outward from touch point.

**Tasks**:
1. Record touch point on dome surface
2. Implement expanding wave radius over time
3. Spawn fragments only when wave reaches them
4. Bias velocity away from touch point (blast direction)

**Validation checkpoint**:
> Touch one side of dome. Fragments near touch explode first. Explosion cascades across dome surface like a ripple. Far side shatters last. Creates directional "blast wave" feel rather than uniform pop.

**Tuning opportunity**: Wave speed, velocity bias toward blast direction.

---

### Phase 8: Polish & Parameter Tuning

**Goal**: Lock down the "feel."

**Tasks**:
1. Expose all parameters in debug UI
2. Iterate on values until motion feels right
3. Test at different aperture states (closed, half-open, mostly-open)
4. Verify fragment count scaling with visible blade area
5. Profile performance, cap fragment count if needed

**Validation checkpoint**:
> Shatter looks and feels satisfying at all aperture states. Performance is solid. Parameters documented with final values.

---

## Summary

| Component | Approach |
|-----------|----------|
| Blades | 3D meshes, curved wedge shape, beveled edges |
| Material | Dual-sided: glass front, metal back |
| Animation | Pivot rotation, smooth easing, all blades in sync |
| Shatter trigger | Touch aperture opening |
| Fragments | Blade triangles, inherit spin, random gravity |
| Wave propagation | Radial expansion from touch point |
| Clip plane | Base plane kills fragments on crossing |
| Parameterization | Extensive - tune before locking down |
