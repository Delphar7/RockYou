# RockYou — Design & Architecture Guide

This doc captures the “keep-us-honest” rules that reduce rot: **ownership**, **platform hygiene**, and **gesture safety**.

## Tenets

- **No duplication**: if two platforms share meaning, factor shared logic (even if implementations differ).
- **No dead code**: delete unused experiments and debug-only runtime behavior unless it proves a real dev need.
- **Clear ownership**: avoid subtle SwiftUI modifier chains where multiple layers “kind of” own the same gesture or state.

## Platform pattern (no `#if` sprawl)

### File naming rule (critical)

Within a single target, **Swift filename basenames must be unique**. If two files share a basename (even in different folders), Xcode can collide intermediates (e.g. `Name.stringsdata`).

For platform variants:

- Common impl: `Name.swift`
- Per-OS impl: `Name+iOS.swift`, `Name+macOS.swift`, `Name+watchOS.swift`
- Keep the **type name** the same across variants; only filenames differ.

### Directory layout

- Prefer:
  - `Shared/Platform/*`
  - `Shared/UI/Platform/*`
  - `RockYou/UI/Platform/*` for main-app-only features
- Prefer build-time file inclusion/exclusion over sprinkling `#if os(...)` inside already platform-locked files.

## Gesture safety (Sweep / Tooltip / AppStrip)

### Principles

- Prefer deterministic unit tests around extracted logic (state machines) over brittle UI automation.
- When changing gesture-sensitive code, use timeline logging to compare **pre/post** sequences.

### Debug timeline (how to use)

Timeline events are debug-only and are intended to make “what happened?” obvious during refactors:

- `Sweep:*` — press lifecycle (`pressBegan`, `overlayShown`, `dragCancel`, `complete`, `pressEnded`, etc.)
- `Tooltip:*` — show/dismiss lifecycle
- `AppStrip:*` — scroll activity used to suppress sweep/tooltip side-effects

### Regression checklist (high signal)

- **Quick tap** on a sweepable control:
  - should trigger `onQuickTap` (if provided) or the platform’s tooltip behavior
- **Hold to complete**:
  - overlay shows, completion occurs, and cleanup always runs
- **Drag cancel**:
  - cancels reliably and doesn’t “hang” visuals
- **AppStrip scroll suppression**:
  - while scrolling, sweep/tooltip effects are suppressed

## DPad interaction model (shared)

The D-pad is a shared primitive (`Shared/UI/DPadView.swift`):

- **Tap classification** is based on initial touch location:
  - inner radius → `OK`
  - ring quadrants → arrow key
  - outside → ignore
- **Drag ramp**: normalized distance \(u \in [0, 1]\) mapped through a non-linear curve so small drags are gentle and large drags ramp faster.
- **Visual travel**: stick travel is roughly **half** physical drag travel (so it feels weighted).

## Material button “chrome” (iOS + macOS)

Watch intentionally uses simpler affordances.

The material button look is decomposed into:

- **Surface**: base fill + lighting gradient + non-directional micro-texture
- **Lip / bevel**: thin outer highlight + inner shadow
- **Depth cue**: bottom-weighted lift shadow that collapses on press

Implementation lives in code (`RockYou/UI/Components/MaterialButtonEffect.swift`) so iteration doesn’t touch mainline UI flows.

## Watch UX (high-level)

The watch is for **quick control** (most interactions are D-pad + OK + volume):

- 3 pages: Quick Actions, Navigation, Media
- Crown drives volume
- Device selection is a small, high-signal control (capsule header)
