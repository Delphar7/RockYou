// ExplodeShader.metal
// RockYou
//
// Explode algorithm shader: Fragments fly outward with gravity, spinning as they fall.
// Exports both geometry modifier and visibility kernel.

#include "FragmentShaderScaffold.h"
#include "Algorithms/ExplodeAlgorithm.h"

FRAGMENT_GEOMETRY_MODIFIER(explode, explode)
FRAGMENT_VISIBILITY_KERNEL(explode, explode)
