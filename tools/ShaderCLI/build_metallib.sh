#!/bin/bash
# build_metallib.sh — Compile project .metal files into a standalone metallib for CLI use.
#
# Usage: ./tools/ShaderCLI/build_metallib.sh
#
# Compiles all RockYou/UI/Shaders/*.metal with the correct include paths for
# algorithm headers. Shaders that depend on RealityKit (geometry modifiers,
# surface shaders) will fail to compile — that's expected. Compute kernels
# and standalone shaders will succeed.
#
# Output: /tmp/metal_build/RockYou.metallib

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHADER_DIR="$REPO_ROOT/RockYou/UI/Shaders"
BUILD_DIR="/tmp/metal_build"

mkdir -p "$BUILD_DIR"
rm -f "$BUILD_DIR"/*.air

echo "Compiling Metal shaders from $SHADER_DIR"
echo "Include path: $SHADER_DIR"
echo

succeeded=0
failed=0
failed_names=()

for metal_file in "$SHADER_DIR"/*.metal; do
  name=$(basename "$metal_file" .metal)
  air_file="$BUILD_DIR/${name}.air"

  if xcrun -sdk macosx metal -c "$metal_file" -o "$air_file" \
      -I "$SHADER_DIR" \
      -std=metal3.1 \
      -Wno-unused-variable \
      2>/dev/null; then
    echo "  OK  $name"
    ((succeeded++))
  else
    echo "  SKIP $name (compile failed — likely RealityKit-dependent)"
    ((failed++))
    failed_names+=("$name")
  fi
done

echo
echo "Compiled: $succeeded succeeded, $failed skipped"

if [[ $succeeded -eq 0 ]]; then
  echo "ERROR: No shaders compiled successfully"
  exit 1
fi

# Link all .air files into a single metallib
xcrun -sdk macosx metallib "$BUILD_DIR"/*.air -o "$BUILD_DIR/RockYou.metallib" 2>/dev/null
echo "Output: $BUILD_DIR/RockYou.metallib"

# List available functions
echo
echo "Available functions:"
xcrun metal-objdump -t "$BUILD_DIR/RockYou.metallib" 2>/dev/null \
  | awk '/FUNCTION_LIST/ { print "  " $NF }'
