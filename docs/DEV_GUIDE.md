# RockYou — Dev Guide

This is the practical guide for **building**, **debugging**, and **shipping** RockYou (iOS + macOS + watchOS bundle).

## Build & Run

### Xcode (recommended for day-to-day)

- Select scheme `RockYou`
- Run on:
  - iOS Simulator / Device
  - Mac (Designed for iPad / Mac Catalyst is not used here)
  - Watch simulator pairs as needed

### Watch widgets / complications (Smart Stack)

RockYou ships a watch WidgetKit extension target:

- **Target/Scheme**: `RockYou Watch Widgets`
- **What it provides**: accessory widgets usable as both **watch face complications** and **Smart Stack widgets**

Notes:
- The widget reads state from `WatchSurfaceSnapshotStore` (App Group `group.com.jtr.RockYou`). If the App Group capability isn't enabled for your dev team, the widget will show placeholders.
- The watch app triggers updates via `WidgetCenter.shared.reloadAllTimelines()` when new snapshots arrive.

### CLI (repeatable / CI / agent builds)

Important: when piping `xcodebuild` output, use `pipefail` so failures propagate.

```bash
set -o pipefail

PROJECT="/Users/joe/src/xcode/RockYou/RockYou.xcodeproj"
DD="/Users/joe/src/xcode/RockYou/DerivedData-CLIBuild"

# iOS simulator build (example destination id)
IPHONE_SIM="C6E07BE6-0979-4E4A-9C78-EE2793F7B924"
xcodebuild -scheme RockYou -configuration Debug -project "$PROJECT" \
  -derivedDataPath "$DD/iossim-iphone" \
  -destination "platform=iOS Simulator,id=$IPHONE_SIM" \
  build | xcbeautify
```

## WatchConnectivity (FAQ)

### Watch app not showing up in iPhone Watch app / `isWatchAppInstalled == false`

This is almost always **project configuration**, not “simulator flakiness”.

- **Fix**: iPhone app target must embed the Watch app:
  - Add a Copy Files phase named **Embed Watch Content**
  - Destination: **Wrapper**
  - Subpath: **Watch**
  - Add: `RockYou Watch App.app`
  - Enable **Code Sign On Copy**
  - Add a **target dependency** from iPhone → Watch
- **Verify**: build log contains:

```text
Validate Embedded Binary RockYou Watch App.app
```

### Simulator note

WatchConnectivity on simulators can be unreliable; validate important WC behaviors on **real devices**.

### WatchConnectivity works in one direction only

Symptoms you’ll see:

- Watch → iPhone messages work ✓
- iPhone → Watch replies or sends fail ✗
- iPhone logs: `WCSession counterpart app not installed`
- `session.isWatchAppInstalled == false` on iPhone

Cause is usually the same as above: **the Watch app is not properly embedded**, so iOS doesn’t recognize it as the companion.

### Messages time out (`WCErrorCodeTransferTimedOut`)

Common causes:

- Watch app not embedded (see above)
- iPhone app not running/foreground (since `sendMessage` requires reachability)
- Network issues (Wi‑Fi/Bluetooth)

Debug checks:

- `session.isReachable`
- `session.isPaired`
- `session.isWatchAppInstalled`

### Debug logging snippets (quick copy/paste)

On iPhone side:

```swift
NSLog("[iPhone] ✅ Session activated, reachable: \(session.isReachable), paired: \(session.isPaired), watchAppInstalled: \(session.isWatchAppInstalled)")
```

On Watch side:

```swift
NSLog("[Watch] 📶 Reachability changed: \(session.isReachable)")
```

### Simulator pairing recipe (when you must)

```bash
# Create iPhone
IPHONE=$(xcrun simctl create "iPhone 16 Pro" "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro" "com.apple.CoreSimulator.SimRuntime.iOS-18-4")

# Create Watch
WATCH=$(xcrun simctl create "Apple Watch Series 10" "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10-46mm" "com.apple.CoreSimulator.SimRuntime.watchOS-11-4")

# Pair them
xcrun simctl pair "$WATCH" "$IPHONE"
```

## Deployment (TestFlight / App Store)

See `Resources/Docs/Deployment.md`.

## Common build issues

### “Unable to find a destination matching …”

Deployment target is higher than your simulator runtime. Lower:

- `IPHONEOS_DEPLOYMENT_TARGET`
- `WATCHOS_DEPLOYMENT_TARGET`
- `MACOSX_DEPLOYMENT_TARGET`

## Regenerating the app icon (iOS + iPadOS + watchOS + macOS)

The app icon is a single Liquid Glass Icon Composer bundle, **`Resources/AppIcon.icon`**
(committed). `actool` compiles it into every platform variant plus flat PNG/`.icns`
fallbacks for pre-26 OSes; the OS applies the glass effect at runtime. It is wired into
the `RockYou` and `RockYou Watch App` targets, both with
`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.

**Source of truth:** `Resources/R_bold_monogram.svg`

- **Background**: `#662D91` (Roku purple) — supplied as the bundle fill, not baked in
- **Foreground**: pure white bold cursive `R`, inset to clear the watchOS circle

Regenerate (headless — requires Node 18+ and Xcode 26+'s `ictool`):

```bash
# From the repo root. Rebuilds Resources/AppIcon.icon in place.
python3 Scripts/build_app_icon.py

# Add glass previews (iOS + watchOS) and a flat App Store PNG while tuning:
python3 Scripts/build_app_icon.py --preview --marketing /tmp/marketing.png

# Retune the inset (smaller = more margin); the watchOS circle is the tight constraint:
python3 Scripts/build_app_icon.py --glyph-scale 0.62

# Verify the toolchain if a build can't find the icon renderer:
npx -y -p icon-composer-mcp icon-composer doctor
```

Commit the regenerated `Resources/AppIcon.icon` — no Xcode project changes are needed
unless the bundle is renamed or moved.
