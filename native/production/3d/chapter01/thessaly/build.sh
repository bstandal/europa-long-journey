#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BLENDER_EXECUTABLE=${BLENDER_EXECUTABLE:-/opt/homebrew/bin/blender}
export PXR_WORK_THREAD_LIMIT=1
export TBB_NUM_THREADS=1

if [ ! -x "$BLENDER_EXECUTABLE" ]; then
  echo "Blender executable not found: $BLENDER_EXECUTABLE" >&2
  exit 1
fi

BLENDER_VERSION=$($BLENDER_EXECUTABLE --version | sed -n '1s/^Blender //p')
if [ "$BLENDER_VERSION" != "5.2.0 LTS" ]; then
  echo "Expected Blender 5.2.0 LTS, found: $BLENDER_VERSION" >&2
  exit 1
fi

mkdir -p "$SCRIPT_DIR/outputs"

"$BLENDER_EXECUTABLE" \
  --background \
  --factory-startup \
  --threads 1 \
  --python "$SCRIPT_DIR/build_thessaly.py" \
  -- \
  --output-dir "$SCRIPT_DIR/outputs" \
  --bindings "$SCRIPT_DIR/entity-bindings.json"

"$BLENDER_EXECUTABLE" \
  --background \
  --factory-startup \
  --threads 1 \
  --python "$SCRIPT_DIR/validate_thessaly.py" \
  -- \
  --asset "$SCRIPT_DIR/outputs/thessaly-household-store.usdc" \
  --lod1 "$SCRIPT_DIR/outputs/thessaly-household-store-lod1.usdc" \
  --lod2 "$SCRIPT_DIR/outputs/thessaly-household-store-lod2.usdc" \
  --package "$SCRIPT_DIR/outputs/thessaly-household-store.usdz" \
  --bindings "$SCRIPT_DIR/entity-bindings.json"
