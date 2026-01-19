# Aperture Mask

## Purpose
Defines the open hole of the iris.
This is independent from blade seams.

## Definition
Given point p in normalized disc space:

r = length(p)
R(t) = mix(R_closed, R_open, smoothstep(t))

## Mask
apertureMask(p,t) =
  smoothstep(R(t) - edgeSoftness,
             R(t) + edgeSoftness,
             r)

White = open hole
Black = covered
