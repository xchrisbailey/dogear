#!/usr/bin/env bash
# Generates the Xcode project and builds or tests the app on a throwaway simulator.
#   scripts/app.sh build | test
set -euo pipefail
cd "$(dirname "$0")/.."

action="${1:-}"
[[ "$action" == build || "$action" == test ]] || { echo "usage: $0 build|test" >&2; exit 64; }

# The Nix xcodegen wrapper only finds its bundled resources through its resolved path.
"$(readlink -f "$(command -v xcodegen)")" generate --quiet

exec scripts/with-simulator.sh sh -c '
  xcodebuild "$0" -project Dogear.xcodeproj -scheme Dogear \
    -destination "id=$UDID" -derivedDataPath .build/DD -quiet
' "$action"
