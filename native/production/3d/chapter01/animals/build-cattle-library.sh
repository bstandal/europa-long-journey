#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUTPUT_DIR="$SCRIPT_DIR/outputs"
BLENDER_EXECUTABLE=${BLENDER_EXECUTABLE:-/opt/homebrew/bin/blender}

ACTUAL_VERSION=$($BLENDER_EXECUTABLE --version | sed -n '1p')
if [ "$ACTUAL_VERSION" != "Blender 5.2.0 LTS" ]; then
  echo "Expected Blender 5.2.0 LTS, found: $ACTUAL_VERSION" >&2
  exit 1
fi
if ! $BLENDER_EXECUTABLE --version | grep -q 'build hash: fbe6228777e7'; then
  echo "Blender build hash does not match fbe6228777e7" >&2
  exit 1
fi

export SOURCE_DATE_EPOCH=315532800
export PYTHONHASHSEED=0
export PXR_WORK_THREAD_LIMIT=1
export TBB_NUM_THREADS=1

build_lod() {
  destination=$1
  lod=$2
  preview=$3
  mkdir -p "$destination"
  "$BLENDER_EXECUTABLE" \
    --background \
    --threads 1 \
    --python "$SCRIPT_DIR/generate_chapter01_cattle.py" \
    -- "$destination" "$lod" "$preview"
  find "$destination" -type f -exec touch -t 198001010000 {} +
  source_name="chapter01-cattle-library-lod${lod}.usdc"
  package_name="chapter01-cattle-library-lod${lod}.usdz"
  package_candidate="$destination/.chapter01-cattle-library-lod${lod}-$$.usdz"
  (
    cd "$destination"
    /usr/bin/usdzip --arkitAsset "$source_name" "$(basename "$package_candidate")"
  )
  touch -t 198001010000 "$package_candidate"
  mv -f "$package_candidate" "$destination/$package_name"
  /usr/bin/usdchecker --arkit "$destination/$package_name"
  /usr/bin/python3 "$SCRIPT_DIR/validate_cattle_usd.py" \
    --lod "$lod" \
    --usdc "$destination/$source_name" \
    --usdz "$destination/$package_name"
}

REPRO_DIR=$(mktemp -d "${TMPDIR:-/tmp}/chapter01-cattle-repro.XXXXXX")
cleanup_repro() {
  find "$REPRO_DIR" -depth -delete
}
trap cleanup_repro EXIT HUP INT TERM

build_lod "$OUTPUT_DIR" 0 1
build_lod "$OUTPUT_DIR" 1 0
build_lod "$REPRO_DIR" 0 0
build_lod "$REPRO_DIR" 1 0

for lod in 0 1
do
  cmp "$OUTPUT_DIR/chapter01-cattle-library-lod${lod}.usdc" "$REPRO_DIR/chapter01-cattle-library-lod${lod}.usdc"
  cmp "$OUTPUT_DIR/chapter01-cattle-library-lod${lod}.usdz" "$REPRO_DIR/chapter01-cattle-library-lod${lod}.usdz"
  cmp "$OUTPUT_DIR/chapter01-cattle-library-lod${lod}-report.json" "$REPRO_DIR/chapter01-cattle-library-lod${lod}-report.json"
done
for texture in "$OUTPUT_DIR"/textures/*.png
do
  cmp "$texture" "$REPRO_DIR/textures/$(basename "$texture")"
done

/usr/bin/python3 "$SCRIPT_DIR/write_cattle_manifest.py" --animal-dir "$SCRIPT_DIR"

echo "ANIMAL_RIG_CANDIDATE built, ARKit-validated and reproduced byte-identically at $OUTPUT_DIR"
