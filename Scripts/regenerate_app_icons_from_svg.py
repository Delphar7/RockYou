#!/usr/bin/env python3
"""
Regenerate all AppIcon PNGs (iOS + macOS + watchOS) from the SVG source of truth.

Source of truth:
  Resources/R_monogram.svg

Outputs:
  - RockYou/Assets.xcassets/AppIcon.appiconset/
  - RockYou Watch App/Assets.xcassets/AppIcon.appiconset/

This script:
  1) Injects a purple background rect into the SVG and forces foreground to white via `currentColor`.
  2) Renders a 1024x1024 PNG using macOS QuickLook (`qlmanage`).
  3) Resizes into all required sizes by reading each AppIcon set's Contents.json and using `sips`.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


PURPLE = "#662D91"
WHITE = "#FFFFFF"


def repo_root() -> Path:
    # Scripts/ is at repo root / Scripts
    return Path(__file__).resolve().parent.parent


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def parse_size(size_str: str) -> float:
    # "83.5x83.5" -> 83.5
    return float(size_str.split("x", 1)[0])


def parse_scale(scale_str: str) -> int:
    # "2x" -> 2
    return int(scale_str.replace("x", ""))


def load_jobs(contents_path: Path) -> dict[str, int]:
    data = json.loads(read_text(contents_path))
    jobs: dict[str, int] = {}
    for img in data.get("images", []):
        fn = img.get("filename")
        if not fn:
            continue
        px = int(round(parse_size(img["size"]) * parse_scale(img["scale"])))
        jobs[fn] = px
    return jobs


def ensure_svg_has_1024_viewbox(svg: str) -> str:
    m = re.search(r'<svg\s+[^>]*viewBox="0 0 1024 1024"[^>]*>', svg)
    if not m:
        raise SystemExit('Unexpected SVG format (missing viewBox="0 0 1024 1024").')
    return m.group(0)


def make_icon_svg(svg_in: Path, purple: str, white: str, out_dir: Path) -> Path:
    svg = read_text(svg_in)
    open_tag = ensure_svg_has_1024_viewbox(svg)

    # Ensure the root <svg> has `style="color: #fff"` so `currentColor` paths become white.
    if "style=" in open_tag:
        open_tag2 = re.sub(
            r'style="([^"]*)"',
            lambda mm: f'style="{mm.group(1)};color:{white}"',
            open_tag,
            count=1,
        )
    else:
        open_tag2 = open_tag[:-1] + f' style="color:{white}">'

    svg2 = svg.replace(open_tag, open_tag2, 1)
    svg2 = svg2.replace(
        open_tag2,
        open_tag2 + "\n" + f'  <rect x="0" y="0" width="1024" height="1024" fill="{purple}"/>',
        1,
    )

    out_dir.mkdir(parents=True, exist_ok=True)
    svg_tmp = out_dir / "RockYou_AppIcon.svg"
    write_text(svg_tmp, svg2)
    return svg_tmp


def render_svg_to_png(svg_path: Path, tmp_dir: Path, size_px: int = 1024) -> Path:
    # qlmanage thumbnail output becomes: <name>.svg.png in the output dir.
    subprocess.run(
        ["qlmanage", "-t", "-s", str(size_px), "-o", str(tmp_dir), str(svg_path)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    png = tmp_dir / (svg_path.name + ".png")
    if not png.exists():
        raise SystemExit(f"Expected {png} to exist after qlmanage.")
    return png


def gen(out_dir: Path, base_png: Path, jobs: dict[str, int]) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for fn, px in sorted(jobs.items()):
        out_path = out_dir / fn
        subprocess.run(
            ["sips", "-s", "format", "png", "-z", str(px), str(px), str(base_png), "--out", str(out_path)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def main() -> int:
    ap = argparse.ArgumentParser(description="Regenerate RockYou app icons from Resources/R_monogram.svg")
    ap.add_argument(
        "--svg",
        default=None,
        help="Input SVG path (default: Resources/R_monogram.svg)",
    )
    ap.add_argument("--purple", default=PURPLE, help="Background color hex (default: %(default)s)")
    ap.add_argument("--white", default=WHITE, help="Foreground color hex via currentColor (default: %(default)s)")
    ap.add_argument("--open", action="store_true", help="Open the generated 1024 PNG (for quick inspection)")
    ap.add_argument(
        "--watch-only",
        action="store_true",
        help="Only regenerate watchOS icons (RockYou Watch App/Assets.xcassets/AppIcon.appiconset).",
    )
    ap.add_argument(
        "--ios-only",
        action="store_true",
        help="Only regenerate iOS+macOS icons (RockYou/Assets.xcassets/AppIcon.appiconset).",
    )
    args = ap.parse_args()

    if args.watch_only and args.ios_only:
        print("❌ Choose at most one of --watch-only or --ios-only.", file=sys.stderr)
        return 2

    root = repo_root()
    svg_in = (root / args.svg) if args.svg else (root / "Resources" / "R_monogram.svg")
    ios_set = root / "RockYou" / "Assets.xcassets" / "AppIcon.appiconset"
    watch_set = root / "RockYou Watch App" / "Assets.xcassets" / "AppIcon.appiconset"

    if not svg_in.exists():
        print(f"❌ Missing source SVG: {svg_in}", file=sys.stderr)
        return 1

    if args.watch_only:
        required = [watch_set / "Contents.json"]
    elif args.ios_only:
        required = [ios_set / "Contents.json"]
    else:
        required = [ios_set / "Contents.json", watch_set / "Contents.json"]

    for p in required:
        if not p.exists():
            print(f"❌ Missing asset Contents.json: {p}", file=sys.stderr)
            return 1

    tmp = Path("/tmp/rockyou-icon-gen")
    svg_tmp = make_icon_svg(svg_in, args.purple, args.white, tmp)
    base_png = render_svg_to_png(svg_tmp, tmp, size_px=1024)

    if args.open:
        subprocess.run(["open", str(base_png)], check=False)

    did_any = False
    if not args.watch_only:
        ios_jobs = load_jobs(ios_set / "Contents.json")
        gen(ios_set, base_png, ios_jobs)
        did_any = True

    if not args.ios_only:
        watch_jobs = load_jobs(watch_set / "Contents.json")
        gen(watch_set, base_png, watch_jobs)
        did_any = True

    if not did_any:
        print("❌ Nothing to do (unexpected flag combination).", file=sys.stderr)
        return 2

    rel = svg_in
    try:
        rel = svg_in.relative_to(root)
    except Exception:
        pass
    print(f"✅ Regenerated app icon PNGs from {rel}")
    if not args.watch_only:
        print(f"   iOS/macOS: {ios_set}")
    if not args.ios_only:
        print(f"   watchOS:   {watch_set}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
