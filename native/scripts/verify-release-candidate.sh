#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  echo "Usage: verify-release-candidate.sh <Release.app> <approved-trust-receipt.json> <approved-essential-receipt.json>" >&2
  exit 2
fi

SCRIPT_DIRECTORY=${0%/*}
node "$SCRIPT_DIRECTORY/validate-release-app-boundary.mjs" \
  --app "$1" \
  --mode release-candidate \
  --approved-trust-receipt "$2" \
  --approved-essential-receipt "$3"
