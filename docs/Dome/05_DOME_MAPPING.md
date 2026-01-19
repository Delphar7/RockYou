# Dome Mapping

Mask is evaluated in object space.

For surface normal n:
theta = atan2(n.z, n.x)
rho = acos(n.y)
r = rho / (pi/2)

p = r * [cos(theta), sin(theta)]

Feed p into aperture + seam masks.
