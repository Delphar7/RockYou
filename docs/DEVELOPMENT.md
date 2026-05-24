# RockYou Project Guidelines

## Build Commands

**Always use `buildrun` directly for builds, and always pass `--lint` for verification work.** Never invoke `xcodebuild` directly. `buildrun` is on `PATH`; run it from the project root, where it auto-discovers `buildrun.yaml` (no wrapper script). It handles scheme selection, simulator dispatch, build locking, and log capture.

```bash
# Canonical build + lint for the fast mac target
buildrun --lint RockYou:mac

# Other targets (Product:device)
buildrun --lint RockYou:phone
buildrun --lint RockYou:ipad
buildrun --lint "RockYou Watch App"     # product name has a space — quote it

# Inspect merged config (products, devices, aliases)
buildrun --list
```

### Before running `buildrun`: don't battle a live build

The user may have a `buildrun`/`watchexec` build running in another tmux pane that auto-rebuilds on save. Starting a second `buildrun` contends for the build lock and burns CPU. Check first:

```bash
pgrep -fil 'buildrun.*RockYou'
```

- **Hits:** a build is already running — your edits are being picked up automatically. Don't start another; read the log after it settles instead.
- **No hits:** running `buildrun --lint RockYou:mac` yourself is fine.

**Build log:** lint logs land under `DerivedData/Logs/BuildRunall/` (e.g. `RockYou.mac.lint.log`). A stable tail (no new lines for ~10s) means the build finished.

## Project Structure

- `RockYou/` - Main iOS/macOS app
- `RockYou/UI/Debug/` - macOS-only debug views and harnesses
- `RockYou/UI/Debug/Playground/` - Experimental engines (move to `UI/` when ready)
- `RockYou/UI/Shaders/` - Metal shaders
- `RockYou/UI/Shaders/Algorithms/` - Algorithm-specific shader headers
- `Shared/` - Code shared across all targets
- `Shared/Platform/` - Platform-specific implementations

## Logging

- Use `Log.debug/info/warn/error()` from `Shared/Log.swift`
- `Log.noisy()` is for verbose protocol dumps - disabled by default
- Enable noisy logging only when debugging: `Log.noisyEnabled = true`

## Metal Shader Architecture

### Algorithm Pattern
Shaders use compile-time algorithm selection via macros:

1. **Shared math utilities**: `FragmentMath.h` - quaternions, hashing, texture decoding, `stable_random()`
2. **Algorithm headers**: `Algorithms/ExplodeAlgorithm.h`, `ConfettiAlgorithm.h`, `RippleAlgorithm.h`
   - Each defines a namespace with `PhysicsData`, `readPhysicsData()`, `computeState()`
3. **Scaffold macro**: `FragmentShaderScaffold.h` - `FRAGMENT_GEOMETRY_MODIFIER(name, namespace)`
4. **One-line .metal files**: Instantiate the scaffold with an algorithm
   ```metal
   #include "FragmentShaderScaffold.h"
   #include "Algorithms/ExplodeAlgorithm.h"
   FRAGMENT_GEOMETRY_MODIFIER(explode, explode)
   ```

### GPU Randomness
Use `stable_random()` from `FragmentMath.h` for deterministic per-fragment randomness:
```metal
float val = stable_random(fragmentIndex, seed);                    // [0, 1]
float val = stable_random(fragmentIndex, seed, minVal, maxVal);    // [min, max]
```
Different seeds produce uncorrelated values for the same fragment index.

### Texture Header Layout
Parameters are encoded in texture header (row 0) using 16-bit encoding:
- Cols 0-2: Legacy lookup table data
- Cols 3-6: Dome params (radius, segments, waveOrigin, waveSpeed, waveEnabled)
- Col 7: Algorithm ID, cannon power
- Cols 8-11: Physics config (gravity, spin rates, speed, spread)
- Cols 12-13: Ripple params (frequency, amplitude, rippleSpeed, collapseSpeed)

## PropertyConfig Pattern

Engines in `Debug/Playground/` use KeyPath-based `PropertyConfig` for auto-generated UI.
Two lines per property - declare property, add to config array:

```swift
@Observable
final class MyEngine {
  // 1. Declare property with default
  var speed: Double = 1.0
  var enabled: Bool = true
  var mode: Mode = .normal  // CaseIterable enum

  // 2. Add to config array (single source of truth for UI)
  static let config: [PropertyConfig<MyEngine>] = [
    .slider(\.speed, "Speed", 0...10, step: 0.1),
    .toggle(\.enabled, "Enabled"),
    .picker(\.mode, "Mode"),  // Auto-iterates CaseIterable
  ]
}
```

Available config types:
- `.slider(keyPath, name, range, step:)` - Double/Float/CGFloat
- `.toggle(keyPath, name)` - Bool
- `.stepper(keyPath, name, range, step:)` - Int (small range)
- `.intField(keyPath, name)` - Int (large numbers)
- `.picker(keyPath, name)` - CaseIterable enum
- `.text(keyPath, name)` - String
- `.color(keyPath, name)` - Color

Use in views:
```swift
ConfigPanel(engine: engine, config: MyEngine.config, width: 240)
```

## Snapshotting Algorithms ("Happy Accidents")

To preserve an interesting experimental algorithm state, copy these files with a new name:

### Files to Copy
1. `RockYou/UI/Shaders/Algorithms/[Old]Algorithm.h` → `[New]Algorithm.h`
2. `RockYou/UI/Shaders/[Old]Shader.metal` → `[New]Shader.metal`
3. `RockYou/UI/Debug/Playground/[Old]Engine.swift` → `[New]Engine.swift`
4. `RockYou/UI/Debug/Playground/[Old]DebugView.swift` → `[New]DebugView.swift`

### Registration Steps
1. **DomeShatterGPU.swift** - Add case to `DomeCollapseAlgorithm` enum:
   ```swift
   case newAlgo = 3  // Next available number
   ```
   And add to `geometryModifierName` and `surfaceShaderName` switches.

2. **DomePlaygroundView.swift** - For a new category like "Happy Accidents":
   ```swift
   enum DomePlaygroundCategory: String, CaseIterable {
     case sample = "Sample"
     case flower = "Flower"
     case shatter = "Shatter"
     case accidents = "Accidents"  // New category
   }

   enum AccidentsAlgorithm: String, CaseIterable {
     case weirdRipple = "Weird Ripple"
   }
   ```
   Then add the menu and view switching logic.

3. **In copied files** - Append `_Attempt#` to all names (e.g., `_Attempt1`, `_Attempt2`):
   - Files: `RippleAlgorithm.h` → `Ripple_Attempt1Algorithm.h`
   - Class names: `RippleEngine` → `Ripple_Attempt1Engine`
   - Namespaces: `namespace ripple` → `namespace ripple_attempt1`
   - Function names: `rippleGeometryModifier` → `ripple_Attempt1GeometryModifier`
   - Enum cases: `.ripple` → `.ripple_Attempt1`
   - Include paths and macro calls

   Use incrementing numbers for each snapshot of the same base algorithm.

### Known Happy Accidents (not yet snapshotted)

**Ripple_Attempt1** - "Belly Explosion Jello Mold" (2026-01-22)
- Caused by: Simple `sin(frequency * distance - speed * time)` without wavefront gating
- Effect: Dome expands like a belly about to burst, retracts along shifting axes,
  triangles confetti off, then rebuilds into a jello-mold shape (top slightly depressed),
  falls top-down while building, ~2/3 of triangles hit y=0 and fall through
