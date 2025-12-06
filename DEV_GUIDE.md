# RockYou — Dev Guide

This is the practical guide for **building**, **debugging**, and **shipping** RockYou (iOS + macOS + watchOS bundle).

## Build & Run

### Xcode (recommended for day-to-day)

- Select scheme `RockYou`
- Run on:
  - iOS Simulator / Device
  - Mac (Designed for iPad / Mac Catalyst is not used here)
  - Watch simulator pairs as needed

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
cd /Users/joe/src/xcode/RockYou
python3 - <<'PY'
import json, re, subprocess
from pathlib import Path

ROOT = Path("/Users/joe/src/xcode/RockYou")
SVG_IN = ROOT / "Resources" / "R_monogram.svg"
IOS_SET = ROOT / "RockYou" / "Assets.xcassets" / "AppIcon.appiconset"
WATCH_SET = ROOT / "RockYou Watch App" / "Assets.xcassets" / "AppIcon.appiconset"

PURPLE = "#662D91"
WHITE = "#FFFFFF"

svg = SVG_IN.read_text(encoding="utf-8")
m = re.search(r'<svg\\s+[^>]*viewBox=\"0 0 1024 1024\"[^>]*>', svg)
if not m:
    raise SystemExit("Unexpected SVG format (missing 1024x1024 viewBox).")
open_tag = m.group(0)
if "style=" in open_tag:
    open_tag2 = re.sub(r'style=\"([^\"]*)\"', lambda mm: f'style=\"{mm.group(1)};color:{WHITE}\"', open_tag)
else:
    open_tag2 = open_tag[:-1] + f' style=\"color:{WHITE}\">'
svg2 = svg.replace(open_tag, open_tag2, 1)
svg2 = svg2.replace(open_tag2, open_tag2 + "\n" + f'  <rect x=\"0\" y=\"0\" width=\"1024\" height=\"1024\" fill=\"{PURPLE}\"/>', 1)

TMP = Path("/tmp/rockyou-icon-gen")
TMP.mkdir(parents=True, exist_ok=True)
SVG_TMP = TMP / "RockYou_AppIcon.svg"
SVG_TMP.write_text(svg2, encoding="utf-8")

# Render SVG -> 1024 PNG via QuickLook
subprocess.run(["qlmanage", "-t", "-s", "1024", "-o", str(TMP), str(SVG_TMP)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
BASE_PNG = TMP / (SVG_TMP.name + ".png")
if not BASE_PNG.exists():
    raise SystemExit(f"Expected {BASE_PNG} to exist after qlmanage.")

def parse_size(size_str: str) -> float:
    return float(size_str.split("x")[0])

def parse_scale(scale_str: str) -> int:
    return int(scale_str.replace("x", ""))

def load_jobs(contents_path: Path) -> dict[str, int]:
    data = json.loads(contents_path.read_text(encoding="utf-8"))
    jobs: dict[str, int] = {}
    for img in data.get("images", []):
        fn = img.get("filename")
        if not fn:
            continue
        px = int(round(parse_size(img["size"]) * parse_scale(img["scale"])))
        jobs[fn] = px
    return jobs

def gen(out_dir: Path, jobs: dict[str, int]) -> None:
    for fn, px in sorted(jobs.items()):
        out_path = out_dir / fn
        subprocess.run(["sips", "-s", "format", "png", "-z", str(px), str(px), str(BASE_PNG), "--out", str(out_path)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

ios_jobs = load_jobs(IOS_SET / "Contents.json")
watch_jobs = load_jobs(WATCH_SET / "Contents.json")

gen(IOS_SET, ios_jobs)
gen(WATCH_SET, watch_jobs)

print("✅ Regenerated all app icon PNGs from Resources/R_monogram.svg")
PY
```
