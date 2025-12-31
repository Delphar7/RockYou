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

## Deployment (TestFlight / App Store)

### App Store Connect

1. Create the app entry in App Store Connect
2. Bundle id: `com.jtr.RockYou`
3. Note: the watch app is bundled with the iOS app (no separate store entry)

### CloudKit schema deployment (critical)

TestFlight/Production builds use the **Production** CloudKit environment.

1. Open CloudKit dashboard
2. Select container `iCloud.com.jtr.RockYou`
3. Ensure you are in **Development**
4. Click **Deploy Schema Changes...**
5. Verify deployment completes

### Archive

```bash
# iOS + watchOS bundle
xcodebuild archive \
  -scheme "RockYou" \
  -destination "generic/platform=iOS" \
  -archivePath ./build/RockYou-iOS.xcarchive \
  -allowProvisioningUpdates

# macOS
xcodebuild archive \
  -scheme "RockYou" \
  -destination "generic/platform=macOS" \
  -archivePath ./build/RockYou-macOS.xcarchive \
  -allowProvisioningUpdates
```

## Common build issues

### “Unable to find a destination matching …”

Deployment target is higher than your simulator runtime. Lower:

- `IPHONEOS_DEPLOYMENT_TARGET`
- `WATCHOS_DEPLOYMENT_TARGET`
- `MACOSX_DEPLOYMENT_TARGET`

## Regenerating app icons (iOS + watchOS + macOS)

**Source of truth:** `Resources/R_monogram.svg`

- **Background**: `#662D91`
- **Foreground**: pure white

Icons are stored in:

- iOS/macOS: `RockYou/Assets.xcassets/AppIcon.appiconset/`
- watchOS: `RockYou Watch App/Assets.xcassets/AppIcon.appiconset/`

To regenerate all PNGs from the SVG (including mac icon sizes), run:

```bash
# From the repo root:
python3 Scripts/regenerate_app_icons_from_svg.py --open
```

Watch-only regeneration (useful if you have a watch-specific SVG to avoid clipping in circular icons):

```bash
python3 Scripts/regenerate_app_icons_from_svg.py --svg Resources/R_monogram.watch.svg --watch-only --open
```
