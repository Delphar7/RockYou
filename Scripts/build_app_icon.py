#!/usr/bin/env python3
"""Build the RockYou Liquid Glass `.icon` bundle from the SVG monogram.

Source of truth:
  Resources/R_bold_monogram.svg   (the bold cursive R on a 1024 canvas)

This is the modern replacement for `regenerate_app_icons_from_svg.py`. Instead of
rasterizing ~25 flat PNGs across two asset catalogs, it produces ONE Icon Composer
`.icon` bundle (icon.json + Assets/) that Xcode compiles (via actool) into every
platform variant + a legacy fallback, with Liquid Glass applied by the OS at runtime.

Pipeline (fully headless, no GUI):
  1. Force the glyph white. The bold monogram is a two-path design: an inner path with
     `fill="currentColor"` plus an outer silhouette path with NO fill (which would
     default to black). We rewrite currentColor AND inject the foreground color into any
     fill-less path, yielding a clean solid-white silhouette. The purple background is
     supplied as the bundle fill, not baked into the art.
  2. `icon-composer create` -> AppIcon.icon at --glyph-scale. The bold art runs close to
     the canvas edges, so it is inset (0.62) to clear both the rounded-rect corners and
     the tighter watchOS circular crop from one shared layer -- no separate watch art.
  3. Optional: render Liquid Glass previews (iOS rounded-rect + watchOS circle) and a
     flat, no-alpha App Store marketing PNG -- both via Apple's `ictool`.

The resulting `AppIcon.icon` is committed; the Xcode build compiles it. Re-run this
only when the source art changes.

Requirements: Node 18+, and Icon Composer's `ictool` (ships inside Xcode 26+). Run
`npx -y -p icon-composer-mcp icon-composer doctor` to verify.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

PURPLE = "#662D91"  # Roku brand purple
WHITE = "#FFFFFF"
# Pin the (unofficial, beta-era) CLI for reproducible bundles.
CLI_PKG = "icon-composer-mcp@1.1.0"
BUNDLE_NAME = "AppIcon"


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def white_glyph_svg(svg_in: Path, white: str, out_dir: Path) -> Path:
    """Emit a copy of the monogram with every path forced to `white` (transparent bg)."""
    svg = svg_in.read_text(encoding="utf-8")
    if 'viewBox="0 0 1024 1024"' not in svg:
        raise SystemExit('Unexpected SVG format (missing viewBox="0 0 1024 1024").')
    # 1) Paths authored with the theme color. Rewriting directly is also more robust than
    #    relying on a rasterizer to resolve CSS `color`/`currentColor`.
    svg = svg.replace("currentColor", white)

    # 2) Any <path> with no fill attribute defaults to black (the bold silhouette path).
    #    Inject the foreground color so the whole glyph renders as one solid white shape.
    #    Path data never contains '>', so matching the opening tag with [^>]* is safe.
    def ensure_fill(match: "re.Match[str]") -> str:
        tag = match.group(0)
        if re.search(r"\bfill\s*=", tag):
            return tag
        return tag.replace("<path", f'<path fill="{white}"', 1)

    svg = re.sub(r"<path\b[^>]*>", ensure_fill, svg)

    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / "RockYou_glyph_white.svg"
    out.write_text(svg, encoding="utf-8")
    return out


def icon_composer(*args: str) -> None:
    subprocess.run(["npx", "-y", "-p", CLI_PKG, "icon-composer", *args], check=True)


def main() -> int:
    ap = argparse.ArgumentParser(description="Build RockYou's Liquid Glass .icon bundle.")
    ap.add_argument("--svg", default=None, help="Input SVG (default: Resources/R_bold_monogram.svg)")
    ap.add_argument("--out", default=None, help="Output dir for the bundle (default: Resources/)")
    ap.add_argument("--purple", default=PURPLE, help="Background fill hex (default: %(default)s)")
    ap.add_argument("--white", default=WHITE, help="Glyph foreground hex (default: %(default)s)")
    ap.add_argument(
        "--glyph-scale",
        type=float,
        default=0.62,
        help=(
            "Glyph scale written to icon.json position.scale. The bold monogram art runs "
            "close to the canvas edges, so it is inset to clear both the rounded-rect "
            "corners and the tighter watchOS circle. 0.62 clears both. (default: %(default)s)"
        ),
    )
    ap.add_argument("--preview", action="store_true", help="Render iOS + watchOS glass previews.")
    ap.add_argument("--marketing", default=None, help="Path to write a flat App Store PNG.")
    args = ap.parse_args()

    root = repo_root()
    svg_in = Path(args.svg) if args.svg else root / "Resources" / "R_bold_monogram.svg"
    out_dir = Path(args.out) if args.out else root / "Resources"

    if not svg_in.exists():
        print(f"\u274c Missing source SVG: {svg_in}", file=sys.stderr)
        return 1

    tmp = Path("/tmp/rockyou-icon-gen")
    glyph = white_glyph_svg(svg_in, args.white, tmp)

    out_dir.mkdir(parents=True, exist_ok=True)
    bundle = out_dir / f"{BUNDLE_NAME}.icon"
    if bundle.exists():
        shutil.rmtree(bundle)

    icon_composer(
        "create",
        str(glyph),
        str(out_dir),
        "--bg-color",
        args.purple,
        "--bundle-name",
        BUNDLE_NAME,
        "--glyph-scale",
        str(args.glyph_scale),
    )
    print(f"\u2705 Built {bundle}")

    if args.preview:
        for platform in ("iOS", "watchOS"):
            png = tmp / f"preview_{platform}.png"
            icon_composer("render", str(bundle), str(png), "--platform", platform)
            print(f"   preview ({platform}): {png}")

    if args.marketing:
        icon_composer("export-marketing", str(bundle), args.marketing)
        print(f"   marketing: {args.marketing}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
