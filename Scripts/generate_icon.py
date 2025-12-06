#!/usr/bin/env python3
"""
RockYou App Icon Generator
Generates a 1024x1024 app icon with JTR branding.
"""

from PIL import Image, ImageDraw, ImageFont
import os

# Configuration - tweak these!
ROKU_PURPLE = (109, 56, 155)  # RGB for Roku purple
SIZE = 1024
OUTPUT_PATH = os.path.expanduser("~/Desktop/RockYou_AppIcon.png")

# Font settings
FONT_SIZE = 1024  # Bigger to fill space
JT_ALPHA = 0.15  # 50% opacity for JT

def blend_color(fg_color, bg_color, alpha):
    """Blend foreground color with background at given alpha."""
    return tuple(
        int(fg * alpha + bg * (1 - alpha))
        for fg, bg in zip(fg_color, bg_color)
    )

def create_icon():
    # Create base image with Roku purple background
    img = Image.new('RGB', (SIZE, SIZE), ROKU_PURPLE)
    draw = ImageDraw.Draw(img)

    # Load fonts - thin for JT, bold for R
    try:
        # Thin font for J and T
        thin_font_options = [
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
        ]
        thin_font = None
        for font_path in thin_font_options:
            if os.path.exists(font_path):
                thin_font = ImageFont.truetype(font_path, FONT_SIZE/3)
                break

        # Bold font for R
        bold_font_options = [
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/System/Library/Fonts/Supplemental/Arial Black.ttf",
        ]
        bold_font = None
        for font_path in bold_font_options:
            if os.path.exists(font_path):
                bold_font = ImageFont.truetype(font_path, FONT_SIZE)
                break

        if thin_font is None:
            thin_font = ImageFont.load_default()
        if bold_font is None:
            bold_font = thin_font

    except Exception as e:
        print(f"Font loading error: {e}")
        thin_font = ImageFont.load_default()
        bold_font = thin_font

    # Colors
    WHITE = (255, 255, 255)
    JT_COLOR = blend_color(WHITE, ROKU_PURPLE, JT_ALPHA)

    # Measure individual letters
    j_bbox = draw.textbbox((0, 0), "J", font=thin_font)
    t_bbox = draw.textbbox((0, 0), "T", font=thin_font)
    r_bbox = draw.textbbox((0, 0), "R", font=bold_font)

    j_width = j_bbox[2] - j_bbox[0]
    t_width = t_bbox[2] - t_bbox[0]
    r_width = r_bbox[2] - r_bbox[0]

    # Letters touching - negative spacing
    spacing = -60  # More overlap to touch

    total_width = j_width + t_width + r_width + (spacing * 2)
    start_x = (SIZE - total_width) // 2

    # Vertical centering
    max_height = max(j_bbox[3] - j_bbox[1], t_bbox[3] - t_bbox[1], r_bbox[3] - r_bbox[1])
    min_height = min(j_bbox[3] - j_bbox[1], t_bbox[3] - t_bbox[1], r_bbox[3] - r_bbox[1])
    #max_y = (SIZE - max_height)
    #min_y = (SIZE - min_height)
    y = 560

    # Draw J (thin, blended)
    draw.text((start_x, y), "J", fill=JT_COLOR, font=thin_font)
    draw.text((start_x+24, y-142), "-", fill=JT_COLOR, font=thin_font)

    # Draw T (thin, blended)
    draw.text((start_x + j_width + spacing + 12, y), "T", fill=JT_COLOR, font=thin_font)

    # Draw R (bold, white, full opacity)
    draw.text((start_x + j_width + t_width + spacing * 2 - 16, -64), "R", fill=WHITE, font=bold_font)

    # Save
    img.save(OUTPUT_PATH, 'PNG')
    print(f"✅ Icon saved to: {OUTPUT_PATH}")
    print(f"   Size: {SIZE}x{SIZE}")
    print(f"   Background: RGB{ROKU_PURPLE}")
    print(f"   JT opacity: {JT_ALPHA * 100}%")
    print(f"\nOpen it with: open '{OUTPUT_PATH}'")

    return OUTPUT_PATH

if __name__ == "__main__":
    create_icon()
