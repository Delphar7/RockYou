# Rigid Blade Model

Each blade is treated as a rigid solid.

## Blade Properties
- Fixed pivot near rim
- Fixed blade-edge curve
- Local coordinate frame

## Layout
For N blades:
alpha_i = i * (2pi / N)

Pivot:
P_i = rp * [cos(alpha_i), sin(alpha_i)]
