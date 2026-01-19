# Iris Mechanism Modeling Plan

## Overview

Model a physical 12-blade iris mechanism from CAD files and implement as a GPU shader. Each phase includes a **debug visualization** added to the macOS debug menu to verify correctness before proceeding.

---

## Physical Mechanism (Reference)

```
Assembly (side view):
┌─────────────────────────┐
│   Securing Clip         │  ← Holds it together (ignore)
├─────────────────────────┤
│   Actuator Ring         │  ← Blue ring with 12 radial SLOTS, rotates
├─────────────────────────┤
│   Blades (12x)          │  ← Curved crescents, overlap when closed
├─────────────────────────┤
│   Base Ring             │  ← Green ring with 12 HOLES for pivot pins
└─────────────────────────┘

Each Blade:
- Curved crescent/banana shape
- TWO PINS (posts) sticking up:
  - Pivot pin → sits in base ring hole (fixed rotation point)
  - Actuator pin → slides in actuator ring slot
```

---

## Phase 1: Extract Single Blade Geometry

### Goal
Extract the 2D curved outline of one blade, identifying the pin positions and inner/outer edges.

### What to Extract

1. **Blade outline** - The curved crescent shape as ordered 2D points
2. **Pivot pin position** - Center of the pivot pin in blade-local coordinates
3. **Actuator pin position** - Center of the actuator pin in blade-local coordinates
4. **Inner edge** - The edge that faces the iris center (forms the aperture)
5. **Outer edge** - The edge that faces the iris perimeter

### Method

```python
# Load blade STL
blade = trimesh.load('iris_fidget_blade.stl')

# Slice at Z=1.5mm (middle of 3mm thick blade)
blade_slice = blade.section(plane_origin=[0,0,1.5], plane_normal=[0,0,1])

# Convert to 2D path - will have multiple entities:
# - One large curved outline (the blade)
# - Two small circles (the pins)
path_2d = blade_slice.to_2D()

# Separate by size: pins are small circles (~r=1.5mm)
# Blade outline is the large curved shape
```

### Blade-Local Coordinate System

Define blade-local coordinates with:
- **Origin** at the pivot pin center
- **+X axis** pointing toward the actuator pin
- **+Y axis** perpendicular (toward inner edge of blade)

This makes later transforms simpler.

### Debug View: `IrisDebug_BladeGeometry`

Add to macOS debug menu: **"Iris: Blade Geometry"**

Display:
- [ ] Blade outline curve (the crescent shape)
- [ ] Pivot pin location (red dot)
- [ ] Actuator pin location (blue dot)
- [ ] Inner edge highlighted (green)
- [ ] Outer edge highlighted (orange)
- [ ] Coordinate axes shown
- [ ] Measurements displayed:
  - Pivot-to-actuator distance
  - Blade arc length
  - Inner/outer edge curvature

### Success Criteria
- Blade shape visually matches the physical photos
- Two pins clearly identified at correct positions
- Inner vs outer edge correctly distinguished

### Data to Record
```
BLADE_PIVOT_TO_ACTUATOR = ??? mm
BLADE_INNER_EDGE = [array of (x,y) points in blade-local coords]
BLADE_OUTER_EDGE = [array of (x,y) points in blade-local coords]
PIN_RADIUS = 1.5 mm (verify)
```

---

## Phase 2: Extract Assembly Geometry

### Goal
Determine where blades sit in the assembled iris - pivot positions on base ring, slot positions on actuator ring.

### What to Extract

1. **Pivot hole positions** - 12 holes in base ring, their (x,y) centers
2. **Pivot radius** - Distance from iris center to pivot holes
3. **Slot geometry** - Radial extent (inner to outer radius) and angular width
4. **Slot positions** - Angular position of each slot

### Method

```python
# Analyze base ring for pivot holes
body = trimesh.load('iris_fidget_main_body.stl')
# Slice and find 12 circular holes

# Analyze actuator ring for slots
ring = trimesh.load('iris_fidget_actuator_ring.stl')
# Slice and find 12 elongated radial features
```

### Debug View: `IrisDebug_AssemblyGeometry`

Add to macOS debug menu: **"Iris: Assembly Geometry"**

Display:
- [ ] Iris center (origin)
- [ ] Base ring outline
- [ ] 12 pivot hole positions (red circles)
- [ ] Actuator ring outline
- [ ] 12 slot positions (blue radial lines showing extent)
- [ ] One blade placed at pivot 0 (using Phase 1 geometry)
- [ ] Verify: actuator pin falls within slot range

### Success Criteria
- 12 pivot holes at consistent radius, 30° apart
- 12 slots at consistent radius range, 30° apart
- Single blade placement looks correct

### Data to Record
```
PIVOT_RADIUS = ??? mm (distance from iris center to pivot holes)
PIVOT_ANGLES = [0°, 30°, 60°, ..., 330°] (or offset if not starting at 0)
SLOT_INNER_RADIUS = ??? mm
SLOT_OUTER_RADIUS = ??? mm
SLOT_ANGULAR_WIDTH = ??? degrees
```

---

## Phase 3: Derive Kinematic Equations

### Goal
Establish the mathematical relationship: given animation parameter t ∈ [0,1], compute blade angle θ.

### The Kinematics

When actuator ring rotates:
1. Slot moves tangentially
2. Actuator pin (constrained to slot) moves radially within slot
3. Blade rotates around pivot to keep actuator pin in slot

```
Given:
- Pivot at (r_pivot, 0) for blade 0
- Actuator pin at distance L from pivot
- Slot allows actuator to be at radius [r_slot_inner, r_slot_outer]

Find:
- Blade angle θ when actuator is at radius r_act
- Relationship between ring angle φ and blade angle θ
```

### Derivation

For blade with pivot at P and actuator at A:
- P = (r_pivot, 0)
- A = P + L * (cos(θ), sin(θ))  [in blade-local rotated to world]

Actually need to be careful about angle conventions. Define:
- θ = 0 when blade points radially outward (actuator away from center)
- θ increases as blade rotates CCW

Actuator radius: `r_act = |A| = sqrt((r_pivot + L*cos(θ))² + (L*sin(θ))²)`

Solving for θ given r_act:
```
r_act² = r_pivot² + 2*r_pivot*L*cos(θ) + L²
cos(θ) = (r_act² - r_pivot² - L²) / (2*r_pivot*L)
θ = arccos(...)
```

### Animation Mapping

Define t ∈ [0, 1]:
- t = 0: CLOSED (maximum blade overlap, minimum aperture)
- t = 1: OPEN (minimum blade overlap, maximum aperture)

Determine which direction (θ increasing or decreasing) corresponds to closing.

Final equation:
```
θ(t) = θ_closed + t * (θ_open - θ_closed)
```

Or if non-linear, derive the actual relationship.

### Debug View: `IrisDebug_Kinematics`

Add to macOS debug menu: **"Iris: Kinematics"**

Display (builds on Phase 2 view):
- [ ] All geometry from Phase 2
- [ ] **Slider control: t = 0.0 to 1.0**
- [ ] All 12 blades rendered at computed angle θ(t)
- [ ] Actuator pins shown moving in slots
- [ ] Current values displayed:
  - t value
  - θ angle (degrees)
  - Actuator radius
  - Aperture radius (estimated)

### Success Criteria
- At t=0, blades overlap in spiral pattern (matches photo)
- At t=1, blades spread apart, aperture opens
- Animation is smooth, no discontinuities
- Actuator pins stay within slot bounds

### Data to Record
```
THETA_CLOSED = ??? radians (blade angle at t=0)
THETA_OPEN = ??? radians (blade angle at t=1)
θ(t) = [formula or lookup table]
```

---

## Phase 4: Compute Aperture Boundary

### Goal
Determine the visible aperture (central opening) as a function of t.

### The Problem

The aperture is bounded by the **inner edges** of all 12 blades. Since blades overlap, the aperture boundary is the **envelope** of all inner edges - the innermost point at each angle.

### Method

For a given t:
1. Compute each blade's position (angle θ, placed at its pivot)
2. Transform each blade's inner edge to world coordinates
3. For each angle φ around the iris, find the minimum radius (closest inner edge)
4. The aperture is approximately circular but may have 12-fold symmetry

### Simplification

If the aperture is approximately circular:
```
aperture_radius(t) = min over all blades of (closest point on inner edge to origin)
```

### Debug View: `IrisDebug_Aperture`

Add to macOS debug menu: **"Iris: Aperture"**

Display (builds on Phase 3 view):
- [ ] All geometry from Phase 3 with t slider
- [ ] Aperture boundary highlighted (yellow/gold)
- [ ] Aperture center marked
- [ ] Aperture radius displayed
- [ ] Toggle: show/hide individual blade inner edges

### Success Criteria
- Aperture boundary follows blade inner edges correctly
- Aperture grows as t increases (iris opens)
- No gaps or overlaps in boundary computation

### Data to Record
```
APERTURE_RADIUS(t) = [formula or sampled values]
Example: t=0 → r=5mm, t=0.5 → r=10mm, t=1 → r=15mm
```

---

## Phase 5: Blade Visibility and Overlap

### Goal
Determine which blade is "on top" at any point (for correct rendering of overlapping blades).

### The Problem

When closed, blades overlap in a spiral pattern. For rendering:
- Need to know which blade is visible at each pixel
- Or render back-to-front with transparency

### Method

Option A: **Depth ordering**
- Blades have a consistent overlap order (each blade over its CCW neighbor)
- Render in order, back to front

Option B: **Per-pixel determination**
- At each pixel, determine which blade(s) cover it
- Use blade index to determine which is on top

### Debug View: `IrisDebug_Overlap`

Add to macOS debug menu: **"Iris: Overlap"**

Display:
- [ ] All geometry from Phase 4 with t slider
- [ ] Color-code each blade (blade 0 = red, blade 1 = orange, etc.)
- [ ] Toggle: show overlap order (which blade is on top)
- [ ] Click on a point to show which blades cover it

### Success Criteria
- Overlap pattern matches physical iris photos
- No visual artifacts at blade boundaries

---

## Phase 6: Metal Shader Implementation

### Goal
Implement the iris model as a GPU compute shader.

### Shader Structure

```metal
struct IrisConfig {
    int blade_count;           // 12
    float r_pivot;             // Normalized pivot radius
    float L;                   // Pivot-to-actuator distance (normalized)
    float theta_closed;        // Blade angle at t=0
    float theta_open;          // Blade angle at t=1
    // Blade edge curve (sampled or as coefficients)
    // Color parameters
};

kernel void irisKernel(...) {
    // 1. Compute blade angle from t
    // 2. For this pixel, test against each blade
    // 3. Determine if inside aperture or on a blade
    // 4. If on blade, determine which blade (for overlap)
    // 5. Output color with appropriate alpha
}
```

### Debug View: `IrisDebug_Shader`

Add to macOS debug menu: **"Iris: Shader Output"**

Display:
- [ ] GPU-rendered iris texture
- [ ] t slider control
- [ ] Side-by-side: CPU debug view vs GPU shader output
- [ ] Verify they match

### Success Criteria
- Shader output matches CPU debug visualization
- Performance is acceptable (real-time at target resolution)

---

## Phase 7: Integration

### Goal
Integrate new iris shader into existing dome system.

### Tasks
- Replace or augment `DomeGPU.metal`
- Match animation timing
- Polish visual appearance
- Performance optimization

---

## Debug Menu Structure

```
Debug Menu
├── Iris: Blade Geometry      (Phase 1)
├── Iris: Assembly Geometry   (Phase 2)
├── Iris: Kinematics          (Phase 3) ← has t slider
├── Iris: Aperture            (Phase 4) ← has t slider
├── Iris: Overlap             (Phase 5) ← has t slider
└── Iris: Shader Output       (Phase 6) ← has t slider, GPU vs CPU comparison
```

Each subsequent view BUILDS ON the previous, adding more information.

---

## File References

**STL Files:** `Resources/Iris/`
- `iris_fidget_blade.stl` - Single curved blade with two pins
- `iris_fidget_main_body.stl` - Base ring with pivot holes
- `iris_fidget_actuator_ring.stl` - Rotating ring with radial slots
- `iris_fidget_securing_clip.stl` - (not needed)

**Code to Create:**
- `IrisModel.swift` - Data model and kinematic calculations
- `IrisDebugView.swift` - SwiftUI debug views for each phase
- `IrisGPU.metal` - Final Metal shader
- `IrisGPU.swift` - Swift host for shader

**Existing Code (Reference):**
- `DomeGPU.metal` - Current iris shader (different model)
- `DomeGPU.swift` - Current Swift host

---

## Recorded Data (fill in as we progress)

### Phase 1: Blade Geometry
```
BLADE_PIVOT_TO_ACTUATOR = ___ mm
PIN_RADIUS = ___ mm
BLADE_INNER_EDGE = [points TBD]
BLADE_OUTER_EDGE = [points TBD]
```

### Phase 2: Assembly Geometry
```
PIVOT_RADIUS = ___ mm
PIVOT_ANGLE_OFFSET = ___ degrees (if pivots don't start at 0°)
SLOT_INNER_RADIUS = ___ mm
SLOT_OUTER_RADIUS = ___ mm
```

### Phase 3: Kinematics
```
THETA_CLOSED = ___ radians
THETA_OPEN = ___ radians
θ(t) = ___
```

### Phase 4: Aperture
```
APERTURE_CLOSED = ___ mm (at t=0)
APERTURE_OPEN = ___ mm (at t=1)
```

---

## Current Status

**Phase:** Not started
**Next Step:** Begin Phase 1 - Extract blade geometry and create first debug view
