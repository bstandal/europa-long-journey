#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CHAPTER_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
CHARACTER_DIR="$CHAPTER_ROOT/characters"
OUTPUT_DIR="$CHARACTER_DIR/outputs"
BLENDER_EXECUTABLE=${BLENDER_EXECUTABLE:-/opt/homebrew/bin/blender}

: "${CHAPTER01_MPFB_REPOSITORY:?Set CHAPTER01_MPFB_REPOSITORY to the pinned MPFB v2.0.15 checkout}"
: "${CHAPTER01_MAKEHUMAN_ASSETS_ROOT:?Set CHAPTER01_MAKEHUMAN_ASSETS_ROOT to the pinned MakeHuman assets checkout}"
: "${CHAPTER01_SKIN_TEXTURES_ROOT:?Set CHAPTER01_SKIN_TEXTURES_ROOT to the three resolved pinned skin textures}"

ACTUAL_VERSION=$($BLENDER_EXECUTABLE --version | sed -n '1p')
if [ "$ACTUAL_VERSION" != "Blender 5.2.0 LTS" ]; then
  echo "Expected Blender 5.2.0 LTS, found: $ACTUAL_VERSION" >&2
  exit 1
fi
if ! $BLENDER_EXECUTABLE --version | grep -q 'build hash: fbe6228777e7'; then
  echo "Blender build hash does not match fbe6228777e7" >&2
  exit 1
fi

MPFB_COMMIT=$(git -C "$CHAPTER01_MPFB_REPOSITORY" rev-parse HEAD)
if [ "$MPFB_COMMIT" != "f4f4f1ffa8203585730a7ce433b66738777ba168" ]; then
  echo "MPFB commit mismatch: $MPFB_COMMIT" >&2
  exit 1
fi
MAKEHUMAN_COMMIT=$(git -C "$CHAPTER01_MAKEHUMAN_ASSETS_ROOT" rev-parse HEAD)
if [ "$MAKEHUMAN_COMMIT" != "8cf9645b975a98eea056b140df11a1d278da0d10" ]; then
  echo "MakeHuman assets commit mismatch: $MAKEHUMAN_COMMIT" >&2
  exit 1
fi

check_hash() {
  expected=$1
  source_file=$2
  actual=$(shasum -a 256 "$source_file" | awk '{print $1}')
  if [ "$actual" != "$expected" ]; then
    echo "Hash mismatch for $source_file: expected $expected, found $actual" >&2
    exit 1
  fi
}

check_hash e897c4cc1b6ad5d10a7d2b2be92402feda4e772e6582dfaf0a1e8fc4621d8097 "$CHAPTER01_SKIN_TEXTURES_ROOT/middleage_lightskinned_male_diffuse2.png"
check_hash 39c505ca224387bef0b20cd2bf513c3997c27c7e7434447228c9991b87cb8d01 "$CHAPTER01_SKIN_TEXTURES_ROOT/middleage_lightskinned_female_diffuse2.png"
check_hash 03efe1f6b0ae52429649dcefc9dcaef6058032f874a251169cc3e2ed473c3874 "$CHAPTER01_SKIN_TEXTURES_ROOT/young_lightskinned_male_diffuse2.png"

MPFB_WORKSPACE=$(CDPATH= cd -- "$CHAPTER01_MPFB_REPOSITORY/.." && pwd)
export BLENDER_USER_CONFIG=${CHAPTER01_BLENDER_USER_CONFIG:-$MPFB_WORKSPACE/config}
export BLENDER_USER_SCRIPTS=${CHAPTER01_BLENDER_USER_SCRIPTS:-$MPFB_WORKSPACE/scripts}
export SOURCE_DATE_EPOCH=315532800
export PYTHONHASHSEED=0
export PXR_WORK_THREAD_LIMIT=1
export TBB_NUM_THREADS=1

build_one() {
  destination=$1
  mkdir -p "$destination"
  "$BLENDER_EXECUTABLE" \
    --background \
    --threads 1 \
    --python "$SCRIPT_DIR/generate_hero_characters.py" \
    -- "$destination"
  find "$destination" -type f -exec touch -t 198001010000 {} +
  package_candidate="$destination/.chapter01-hero-character-library-$$.usdz"
  (
    cd "$destination"
    /usr/bin/usdzip --arkitAsset chapter01-hero-character-library.usdc "$(basename "$package_candidate")"
  )
  touch -t 198001010000 "$package_candidate"
  mv -f "$package_candidate" "$destination/chapter01-hero-character-library.usdz"
  /usr/bin/usdchecker --arkit "$destination/chapter01-hero-character-library.usdz"
  /usr/bin/python3 "$SCRIPT_DIR/validate_hero_character_usd.py" \
    --usdc "$destination/chapter01-hero-character-library.usdc" \
    --usdz "$destination/chapter01-hero-character-library.usdz"
}

CHAPTER01_REPRO_DIR=$(mktemp -d "${TMPDIR:-/tmp}/chapter01-hero-repro.XXXXXX")
cleanup_repro() {
  find "$CHAPTER01_REPRO_DIR" -depth -delete
}
trap cleanup_repro EXIT HUP INT TERM
build_one "$OUTPUT_DIR"
build_one "$CHAPTER01_REPRO_DIR"

cmp "$OUTPUT_DIR/chapter01-hero-character-library.usdc" "$CHAPTER01_REPRO_DIR/chapter01-hero-character-library.usdc"
cmp "$OUTPUT_DIR/chapter01-hero-character-library.usdz" "$CHAPTER01_REPRO_DIR/chapter01-hero-character-library.usdz"
for texture in "$OUTPUT_DIR"/textures/*.png
do
  cmp "$texture" "$CHAPTER01_REPRO_DIR/textures/$(basename "$texture")"
done

/usr/bin/python3 "$SCRIPT_DIR/write_hero_character_manifest.py" \
  --chapter-root "$CHAPTER_ROOT" \
  --character-dir "$CHARACTER_DIR"

echo "HERO_RIG_CANDIDATE built, validated and reproduced byte-identically at $OUTPUT_DIR"
