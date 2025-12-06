#!/usr/bin/env python3
"""
Generate all required app icon sizes from a base 1024x1024 image.
Sets up Asset Catalogs for iOS and watchOS.
"""

from PIL import Image
import os
import json

# Source icon
SOURCE_ICON = os.path.expanduser("~/Desktop/RockYou_AppIcon.png")

# Asset catalog paths
IOS_ASSET_PATH = "/Users/Joe/src/xcode/RockYou/RockYou/Assets.xcassets/AppIcon.appiconset"
WATCH_ASSET_PATH = "/Users/Joe/src/xcode/RockYou/RockYou Watch App/Assets.xcassets/AppIcon.appiconset"

# iOS icon sizes: (filename, size in pixels)
IOS_ICONS = [
    ("icon-20@2x.png", 40),
    ("icon-20@3x.png", 60),
    ("icon-29@2x.png", 58),
    ("icon-29@3x.png", 87),
    ("icon-40@2x.png", 80),
    ("icon-40@3x.png", 120),
    ("icon-60@2x.png", 120),
    ("icon-60@3x.png", 180),
    ("icon-76@2x.png", 152),      # iPad
    ("icon-83.5@2x.png", 167),    # iPad Pro
    ("icon-1024.png", 1024),      # App Store
]

# watchOS icon sizes
WATCH_ICONS = [
    ("icon-24@2x.png", 48),       # 24pt @2x Notification Center
    ("icon-27.5@2x.png", 55),     # 27.5pt @2x Notification Center
    ("icon-29@2x.png", 58),       # 29pt @2x Settings
    ("icon-29@3x.png", 87),       # 29pt @3x Settings
    ("icon-30@2x.png", 60),       # 30pt @2x Notification Center (45mm)
    ("icon-32@2x.png", 64),       # 32pt @2x Notification Center (Ultra)
    ("icon-33@2x.png", 66),       # 33pt @2x Notification Center
    ("icon-40@2x.png", 80),       # 40pt @2x Home Screen
    ("icon-44@2x.png", 88),       # 44pt @2x Home Screen (45mm)
    ("icon-46@2x.png", 92),       # 46pt @2x Home Screen
    ("icon-50@2x.png", 100),      # 50pt @2x Home Screen (Ultra)
    ("icon-51@2x.png", 102),      # 51pt @2x Home Screen
    ("icon-54@2x.png", 108),      # 54pt @2x Short Look
    ("icon-86@2x.png", 172),      # 86pt @2x Short Look
    ("icon-98@2x.png", 196),      # 98pt @2x Short Look
    ("icon-108@2x.png", 216),     # 108pt @2x Short Look (Ultra)
    ("icon-117@2x.png", 234),     # 117pt @2x Short Look
    ("icon-1024.png", 1024),      # App Store
]

def generate_icons(source_path, output_dir, icon_specs):
    """Generate all icon sizes from source image."""
    os.makedirs(output_dir, exist_ok=True)

    # Load source image
    source = Image.open(source_path)
    if source.size != (1024, 1024):
        print(f"Warning: Source is {source.size}, expected 1024x1024")

    # Convert to RGBA if needed
    if source.mode != 'RGBA':
        source = source.convert('RGBA')

    generated = []
    for filename, size in icon_specs:
        output_path = os.path.join(output_dir, filename)

        # High-quality resize
        resized = source.resize((size, size), Image.Resampling.LANCZOS)

        # Save as PNG
        resized.save(output_path, 'PNG')
        generated.append((filename, size))
        print(f"  ✓ {filename} ({size}x{size})")

    return generated

def create_ios_contents_json(output_dir):
    """Create Contents.json for iOS AppIcon."""
    contents = {
        "images": [
            {"filename": "icon-20@2x.png", "idiom": "iphone", "scale": "2x", "size": "20x20"},
            {"filename": "icon-20@3x.png", "idiom": "iphone", "scale": "3x", "size": "20x20"},
            {"filename": "icon-29@2x.png", "idiom": "iphone", "scale": "2x", "size": "29x29"},
            {"filename": "icon-29@3x.png", "idiom": "iphone", "scale": "3x", "size": "29x29"},
            {"filename": "icon-40@2x.png", "idiom": "iphone", "scale": "2x", "size": "40x40"},
            {"filename": "icon-40@3x.png", "idiom": "iphone", "scale": "3x", "size": "40x40"},
            {"filename": "icon-60@2x.png", "idiom": "iphone", "scale": "2x", "size": "60x60"},
            {"filename": "icon-60@3x.png", "idiom": "iphone", "scale": "3x", "size": "60x60"},
            {"filename": "icon-20@2x.png", "idiom": "ipad", "scale": "2x", "size": "20x20"},
            {"filename": "icon-29@2x.png", "idiom": "ipad", "scale": "2x", "size": "29x29"},
            {"filename": "icon-40@2x.png", "idiom": "ipad", "scale": "2x", "size": "40x40"},
            {"filename": "icon-76@2x.png", "idiom": "ipad", "scale": "2x", "size": "76x76"},
            {"filename": "icon-83.5@2x.png", "idiom": "ipad", "scale": "2x", "size": "83.5x83.5"},
            {"filename": "icon-1024.png", "idiom": "ios-marketing", "scale": "1x", "size": "1024x1024"},
        ],
        "info": {"author": "xcode", "version": 1}
    }

    with open(os.path.join(output_dir, "Contents.json"), 'w') as f:
        json.dump(contents, f, indent=2)
    print("  ✓ Contents.json")

def create_watch_contents_json(output_dir):
    """Create Contents.json for watchOS AppIcon."""
    contents = {
        "images": [
            {"filename": "icon-24@2x.png", "idiom": "watch", "role": "notificationCenter", "scale": "2x", "size": "24x24", "subtype": "38mm"},
            {"filename": "icon-27.5@2x.png", "idiom": "watch", "role": "notificationCenter", "scale": "2x", "size": "27.5x27.5", "subtype": "42mm"},
            {"filename": "icon-29@2x.png", "idiom": "watch", "role": "companionSettings", "scale": "2x", "size": "29x29"},
            {"filename": "icon-29@3x.png", "idiom": "watch", "role": "companionSettings", "scale": "3x", "size": "29x29"},
            {"filename": "icon-30@2x.png", "idiom": "watch", "role": "notificationCenter", "scale": "2x", "size": "30x30", "subtype": "45mm"},
            {"filename": "icon-32@2x.png", "idiom": "watch", "role": "notificationCenter", "scale": "2x", "size": "32x32", "subtype": "49mm"},
            {"filename": "icon-33@2x.png", "idiom": "watch", "role": "notificationCenter", "scale": "2x", "size": "33x33", "subtype": "44mm/45mm/49mm/Ultra"},
            {"filename": "icon-40@2x.png", "idiom": "watch", "role": "appLauncher", "scale": "2x", "size": "40x40", "subtype": "38mm"},
            {"filename": "icon-44@2x.png", "idiom": "watch", "role": "appLauncher", "scale": "2x", "size": "44x44", "subtype": "40mm"},
            {"filename": "icon-46@2x.png", "idiom": "watch", "role": "appLauncher", "scale": "2x", "size": "46x46", "subtype": "41mm"},
            {"filename": "icon-50@2x.png", "idiom": "watch", "role": "appLauncher", "scale": "2x", "size": "50x50", "subtype": "44mm"},
            {"filename": "icon-51@2x.png", "idiom": "watch", "role": "appLauncher", "scale": "2x", "size": "51x51", "subtype": "45mm"},
            {"filename": "icon-54@2x.png", "idiom": "watch", "role": "appLauncher", "scale": "2x", "size": "54x54", "subtype": "49mm"},
            {"filename": "icon-86@2x.png", "idiom": "watch", "role": "quickLook", "scale": "2x", "size": "86x86", "subtype": "38mm"},
            {"filename": "icon-98@2x.png", "idiom": "watch", "role": "quickLook", "scale": "2x", "size": "98x98", "subtype": "42mm"},
            {"filename": "icon-108@2x.png", "idiom": "watch", "role": "quickLook", "scale": "2x", "size": "108x108", "subtype": "44mm"},
            {"filename": "icon-117@2x.png", "idiom": "watch", "role": "quickLook", "scale": "2x", "size": "117x117", "subtype": "45mm/49mm"},
            {"filename": "icon-1024.png", "idiom": "watch-marketing", "scale": "1x", "size": "1024x1024"},
        ],
        "info": {"author": "xcode", "version": 1}
    }

    with open(os.path.join(output_dir, "Contents.json"), 'w') as f:
        json.dump(contents, f, indent=2)
    print("  ✓ Contents.json")

def main():
    print(f"Source: {SOURCE_ICON}")

    if not os.path.exists(SOURCE_ICON):
        print(f"❌ Source icon not found: {SOURCE_ICON}")
        return

    print("\n📱 Generating iOS icons...")
    generate_icons(SOURCE_ICON, IOS_ASSET_PATH, IOS_ICONS)
    create_ios_contents_json(IOS_ASSET_PATH)

    print("\n⌚ Generating watchOS icons...")
    generate_icons(SOURCE_ICON, WATCH_ASSET_PATH, WATCH_ICONS)
    create_watch_contents_json(WATCH_ASSET_PATH)

    print("\n✅ All icons generated!")
    print(f"   iOS: {IOS_ASSET_PATH}")
    print(f"   Watch: {WATCH_ASSET_PATH}")
    print("\nRe-archive in Xcode and validate again.")

if __name__ == "__main__":
    main()
