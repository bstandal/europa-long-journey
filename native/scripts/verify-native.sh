#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
NATIVE_ROOT="${SCRIPT_DIR:h}"

node "$NATIVE_ROOT/scripts/sync-product-metadata.mjs" --check
node "$NATIVE_ROOT/scripts/verify-web-source-inventory.mjs"
node "$NATIVE_ROOT/scripts/build-source-asset-provenance.mjs" --check
node "$NATIVE_ROOT/scripts/validate-delivery-plan.mjs"
node "$NATIVE_ROOT/scripts/validate-native-asset-provenance.mjs"
node "$NATIVE_ROOT/scripts/visual-asset-production.mjs" validate-contract
/usr/bin/python3 "$NATIVE_ROOT/scripts/validate-harvest-central-grain-underlay-authority.py"
/usr/bin/python3 "$NATIVE_ROOT/scripts/validate-harvest-central-grain-underlay-authority.test.py"
node "$NATIVE_ROOT/scripts/validate-harvest-local-composite.mjs"
node "$NATIVE_ROOT/scripts/validate-harvest-parallax-qa.mjs"
node "$NATIVE_ROOT/scripts/validate-physical-device-protocol.mjs"
node "$NATIVE_ROOT/scripts/validate-thread-sanitizer-receipt.mjs"
node "$NATIVE_ROOT/scripts/validate-first-farmers-claim-register.mjs"
node --test "$NATIVE_ROOT/scripts"/*.test.mjs
node "$NATIVE_ROOT/blueprint/enrich.mjs" --check
node "$NATIVE_ROOT/blueprint/generate-editor-approval-brief.mjs" --check
node --test "$NATIVE_ROOT/phase1"/*.test.mjs
node "$NATIVE_ROOT/phase1/validate.mjs"
node --test "$NATIVE_ROOT/phase2"/*.test.mjs
node "$NATIVE_ROOT/phase2/validate-first-farmers-draft.mjs"
node "$NATIVE_ROOT/phase2/generate-first-farmers-chapter.mjs" --check
node "$NATIVE_ROOT/phase2/generate-first-farmers-payload.mjs" --check

NARRATION_ROOT="$NATIVE_ROOT/audio/narration"
uv run --project "$NARRATION_ROOT" --frozen --offline \
  python -m unittest discover -s "$NARRATION_ROOT/test" -v
uv run --project "$NARRATION_ROOT" --frozen --offline \
  python "$NARRATION_ROOT/pipeline.py" validate
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 \
  uv run --project "$NARRATION_ROOT" --frozen --offline \
  python "$NARRATION_ROOT/v5_pipeline.py" validate --offline --deep-v4 >/dev/null
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1 \
  uv run --project "$NARRATION_ROOT" --frozen --offline \
  python "$NARRATION_ROOT/v6_pipeline.py" validate --offline >/dev/null
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1 \
  uv run --project "$NARRATION_ROOT" --frozen --offline \
  python "$NARRATION_ROOT/v7_pipeline.py" validate --offline >/dev/null
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1 \
  uv run --project "$NARRATION_ROOT" --frozen --offline \
  python "$NARRATION_ROOT/v8_pipeline.py" validate --offline >/dev/null
uv run --project "$NARRATION_ROOT" --frozen --offline \
  python "$NARRATION_ROOT/v10_openvoice_v2_evidence.py" validate >/dev/null
uv run --project "$NARRATION_ROOT" --frozen --offline \
  python "$NARRATION_ROOT/v11_narration_candidate_evidence.py" validate >/dev/null
uv run --project "$NARRATION_ROOT" --frozen --offline \
  python "$NARRATION_ROOT/v11_voxcpm2_terminal_evidence.py" validate >/dev/null
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1 \
  uv run --project "$NARRATION_ROOT" --frozen --offline \
  python "$NARRATION_ROOT/v12_voxcpm2_presynthesis.py" validate >/dev/null
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 \
  uv run --project "$NARRATION_ROOT" --frozen --offline \
  python "$NARRATION_ROOT/pipeline.py" preflight --offline >/dev/null
node "$NATIVE_ROOT/tooling/src/audio-production-cli.mjs" preflight
node "$NATIVE_ROOT/tooling/src/harvest-responsive-audio-cli.mjs" validate
node "$NATIVE_ROOT/tooling/src/longhouse-responsive-audio-cli.mjs" validate
node "$NATIVE_ROOT/tooling/src/continent-remade-responsive-audio-cli.mjs" validate
node "$NATIVE_ROOT/tooling/src/more-mouths-responsive-audio-cli.mjs" validate
node "$NATIVE_ROOT/tooling/src/household-crosses-responsive-audio-cli.mjs" validate
node "$NATIVE_ROOT/tooling/src/three-records-responsive-audio-cli.mjs" validate

cd "$NATIVE_ROOT/tooling"
npm test
npm run validate:blueprint
npm run validate:costs

cd "$NATIVE_ROOT/ios"
xcodegen generate

cd "$NATIVE_ROOT/tooling"
npm run validate:ios

cd "$NATIVE_ROOT/ios"
swift test
xcodebuild -quiet \
  -project LongWestJourney.xcodeproj \
  -scheme LongWestJourney \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO \
  clean build test

RELEASE_DERIVED="$(mktemp -d "${TMPDIR:-/tmp}/long-west-release-boundary.XXXXXX")"
trap 'rm -rf -- "$RELEASE_DERIVED"' EXIT
xcodebuild -quiet \
  -project LongWestJourney.xcodeproj \
  -scheme LongWestJourney \
  -configuration Release \
  -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$RELEASE_DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build
RELEASE_APP="$RELEASE_DERIVED/Build/Products/Release-iphonesimulator/LongWestJourney.app"
node "$NATIVE_ROOT/scripts/validate-release-app-boundary.mjs" --app "$RELEASE_APP"
