# Seam Geometry

## Blade Edge Curve
Blade edge is a circular arc in blade-local space.
It never changes shape.

## Evaluation
For each blade:
1. Rotate point into blade frame
2. Rotate around pivot by delta(t)
3. Compute distance to arc
4. Gate by arc angle
5. Convert distance to seam intensity

Final seam = max over blades
