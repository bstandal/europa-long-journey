#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LIBRARY_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BLENDER_BIN=${CHAPTER01_BLENDER_BIN:-/opt/homebrew/bin/blender}
USDCHECKER_BIN=${CHAPTER01_USDCHECKER_BIN:-/usr/bin/usdchecker}

if [ ! -x "$BLENDER_BIN" ]; then
  echo "Blender 5.2 executable not found: $BLENDER_BIN" >&2
  exit 1
fi
if [ ! -x "$USDCHECKER_BIN" ]; then
  echo "usdchecker not found: $USDCHECKER_BIN" >&2
  exit 1
fi

BUILD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/chapter01-animation-library.XXXXXX")
BUILD_A="$BUILD_ROOT/a"
BUILD_B="$BUILD_ROOT/b"
mkdir -p "$BUILD_A" "$BUILD_B"
trap 'rm -rf "$BUILD_ROOT"' EXIT HUP INT TERM

generate() {
  destination=$1
  "$BLENDER_BIN" --background --factory-startup \
    --python "$SCRIPT_DIR/generate_animation_library.py" -- \
    --library-dir "$LIBRARY_DIR" \
    --output-dir "$destination"
  test -s "$destination/chapter01-directed-animation-library.usdc"
  test -s "$destination/chapter01-directed-animation-library.usdz"
  test -s "$destination/chapter01-directed-animation-library.blend"
  "$BLENDER_BIN" --background --factory-startup \
    --python "$SCRIPT_DIR/validate_animation_library.py" -- \
    --library-dir "$LIBRARY_DIR" \
    --output-dir "$destination"
  test -s "$destination/validation-report.json"
  "$USDCHECKER_BIN" --arkit -t "$destination/chapter01-directed-animation-library.usdc"
  "$USDCHECKER_BIN" --arkit -t "$destination/chapter01-directed-animation-library.usdz"
  CHAPTER01_ANIMATION_USDZ_PATH="$destination/chapter01-directed-animation-library.usdz" \
    swift -e 'import Foundation; import RealityKit; let environment = ProcessInfo.processInfo.environment; guard let path = environment["CHAPTER01_ANIMATION_USDZ_PATH"] else { exit(2) }; let entity = try Entity.load(contentsOf: URL(fileURLWithPath: path)); var profileResources = 0; func walk(_ item: Entity) { let hasNamedClip = item.availableAnimations.compactMap(\.name).contains { $0.contains("/Clip_") }; if ["adult_a", "adult_b", "youth"].contains(item.name), hasNamedClip { profileResources += 1 }; for child in item.children { walk(child) } }; walk(entity); guard profileResources == 51 else { FileHandle.standardError.write(Data("Expected 51 named RealityKit profile resources, found \(profileResources)\n".utf8)); exit(3) }; print("RealityKit named animation resources: \(profileResources)")'
}

generate "$BUILD_A"
generate "$BUILD_B"

for filename in \
  chapter01-directed-animation-library.usdc \
  chapter01-directed-animation-library.usdz \
  validation-report.json
do
  cmp "$BUILD_A/$filename" "$BUILD_B/$filename"
done

BLEND_IDENTICAL=OPEN
if cmp -s \
  "$BUILD_A/chapter01-directed-animation-library.blend" \
  "$BUILD_B/chapter01-directed-animation-library.blend"
then
  BLEND_IDENTICAL=PASS
fi

mkdir -p "$LIBRARY_DIR/generated"
cp "$BUILD_A/chapter01-directed-animation-library.usdc" "$LIBRARY_DIR/generated/"
cp "$BUILD_A/chapter01-directed-animation-library.usdz" "$LIBRARY_DIR/generated/"
cp "$BUILD_A/chapter01-directed-animation-library.blend" "$LIBRARY_DIR/generated/"
cp "$BUILD_A/validation-report.json" "$LIBRARY_DIR/generated/"

python3 "$SCRIPT_DIR/write_manifest.py" \
  --library-dir "$LIBRARY_DIR" \
  --blend-byte-identical "$BLEND_IDENTICAL"

echo "Chapter 01 directed animation library: PASS"
