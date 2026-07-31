#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CHAPTER_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BLENDER_BIN=${BLENDER_BIN:-/opt/homebrew/bin/blender}
EXPECTED_VERSION="Blender 5.2.0 LTS"

ACTUAL_VERSION=$($BLENDER_BIN --version | sed -n '1p')
if [ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" ]; then
  echo "Required $EXPECTED_VERSION, found $ACTUAL_VERSION" >&2
  exit 1
fi

SOURCE_DATE_EPOCH=315532800
export SOURCE_DATE_EPOCH
PYTHONHASHSEED=0
export PYTHONHASHSEED

$BLENDER_BIN --background --factory-startup --python "$SCRIPT_DIR/build_aegean_crossing.py"

OUTPUT_ROOT="$CHAPTER_ROOT/generated/aegean-crossing-v1"
for asset in \
  "$OUTPUT_ROOT/aegean-crossing-lod0.usda" \
  "$OUTPUT_ROOT/aegean-crossing-lod0.usd" \
  "$OUTPUT_ROOT/aegean-crossing-lod0.usdc" \
  "$OUTPUT_ROOT/aegean-crossing-lod0.usdz" \
  "$OUTPUT_ROOT/aegean-crossing-lod1.usda" \
  "$OUTPUT_ROOT/aegean-crossing-lod1.usd" \
  "$OUTPUT_ROOT/aegean-crossing-lod1.usdc" \
  "$OUTPUT_ROOT/aegean-crossing-lod1.usdz"
do
  /usr/bin/usdchecker "$asset"
done

/usr/bin/usdzip "$OUTPUT_ROOT/aegean-crossing-lod0.usdz" -l -
/usr/bin/usdzip "$OUTPUT_ROOT/aegean-crossing-lod1.usdz" -l -

echo "Aegean crossing assets generated and validated at $OUTPUT_ROOT"
