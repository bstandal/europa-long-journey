#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../../../.." && pwd)
BLENDER_BIN=${BLENDER_BIN:-/opt/homebrew/bin/blender}
export SOURCE_DATE_EPOCH=315532800
export PYTHONHASHSEED=0
export PXR_WORK_THREAD_LIMIT=1
export TBB_NUM_THREADS=1

exec "$BLENDER_BIN" \
  --background \
  --factory-startup \
  --python "$SCRIPT_DIR/enhance_cells.py" \
  -- \
  --repo-root "$REPO_ROOT" \
  --config "$SCRIPT_DIR/placements.json" \
  --output "$SCRIPT_DIR/generated" \
  --render-previews \
  --verify-reproducible
