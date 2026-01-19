# Iris System Overview

## Goal
Implement a camera-iris-style aperture for a dome surface using rigid rotating blades,
represented as a procedural mask.

Visual intent is mechanical, not fluid:
- Each blade is a solid object
- Blade edge shape is constant over time
- Motion is rotation about a fixed pivot
- Aperture opens by blades rotating away from the center

The system must work in:
- 2D (flat debug view)
- 3D (mapped onto a hemispherical dome)

Using identical math.
