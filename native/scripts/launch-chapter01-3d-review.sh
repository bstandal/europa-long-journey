#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
native_root="${script_dir:h}"
ios_root="$native_root/ios"
simulator_name="${CHAPTER01_REVIEW_SIMULATOR_NAME:-Eurocentric Chapter01 Live UI}"
derived_data="${CHAPTER01_REVIEW_DERIVED_DATA:-/tmp/eurocentric-ch01-dd}"
bundle_id="com.thelongwest.journey.nonshippinglivetest"

usage() {
  print -u2 "Usage: ${0:t} --start | --spring-resume"
}

if (( $# != 1 )); then
  usage
  exit 64
fi

case "$1" in
  --start)
    scheme="Chapter01ImmersiveCleanStart"
    extra_arguments=()
    ;;
  --spring-resume)
    scheme="Chapter01ImmersiveSpringResume"
    extra_arguments=("--chapter01-immersive-review-resume-spring")
    ;;
  *)
    usage
    exit 64
    ;;
esac

for command_name in xcodegen xcodebuild xcrun jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    print -u2 "Missing required command: $command_name"
    exit 69
  fi
done

simulator_id="$({
  xcrun simctl list devices available --json \
    | jq -r --arg name "$simulator_name" \
      '[.devices[][] | select(.isAvailable == true and .name == $name) | .udid][0] // empty'
})"

if [[ -z "$simulator_id" ]]; then
  print -u2 "Simulator not found: $simulator_name"
  print -u2 "Create the dedicated Chapter 01 simulator before launching this review build."
  exit 69
fi

(
  cd "$ios_root"
  xcodegen generate
  xcodebuild \
    -project LongWestJourney.xcodeproj \
    -scheme "$scheme" \
    -configuration NON_SHIPPING_LIVE_TEST \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath "$derived_data" \
    build
)

app_path="$derived_data/Build/Products/NON_SHIPPING_LIVE_TEST-iphonesimulator/LongWestJourney.app"
if [[ ! -d "$app_path" ]]; then
  print -u2 "Built app not found: $app_path"
  exit 70
fi

xcrun simctl boot "$simulator_id" >/dev/null 2>&1 || true
open -a Simulator --args -CurrentDeviceUDID "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl install "$simulator_id" "$app_path"
xcrun simctl terminate "$simulator_id" "$bundle_id" >/dev/null 2>&1 || true

launch_arguments=(
  "--ui-testing-reset-state"
  "--ui-testing-signed-runtime-fixture"
  "--ui-testing-signed-runtime-fixture-chapter=first-farmers"
  "--chapter01-immersive-review"
  "${extra_arguments[@]}"
)

xcrun simctl launch "$simulator_id" "$bundle_id" "${launch_arguments[@]}"

data_container="$({
  xcrun simctl get_app_container "$simulator_id" "$bundle_id" data
})"
metrics_path="$data_container/Library/Application Support/chapter01-immersive-v2/review-metrics.ndjson"

print "Chapter 01 review launched"
print "  mode: ${1#--}"
print "  simulator: $simulator_name ($simulator_id)"
print "  app: $app_path"
print "  local metrics: $metrics_path"
