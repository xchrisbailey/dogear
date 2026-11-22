#!/usr/bin/env bash
# Generates the Xcode project and builds or tests the app on a throwaway simulator.
#   scripts/app.sh build | test     build or test on a throwaway simulator
#   scripts/app.sh resolve          only fetch the app's packages (no simulator)
# XCODEBUILD_EXTRA_ARGS adds flags to the build/test call, e.g. -showBuildTimingSummary.
# APP_VERBOSE=1 prints xcodebuild's full log instead of only warnings and errors.
set -euo pipefail
cd "$(dirname "$0")/.."

action="${1:-}"
[[ "$action" == build || "$action" == test || "$action" == resolve ]] ||
  { echo "usage: $0 build|test|resolve" >&2; exit 64; }

# The Nix xcodegen wrapper only finds its bundled resources through its resolved path.
[[ -z "${APP_VERBOSE:-}" ]] || echo "app.sh: generating the project" >&2
"$(readlink -f "$(command -v xcodegen)")" generate --quiet

# Same place the build below looks for checkouts (<derivedDataPath>/SourcePackages).
if [[ "$action" == resolve ]]; then
  exec xcodebuild -resolvePackageDependencies -project Dogear.xcodeproj -scheme Dogear \
    -clonedSourcePackagesDirPath .build/DD/SourcePackages
fi

read -ra extra <<< "${XCODEBUILD_EXTRA_ARGS:-}"
[[ -n "${APP_VERBOSE:-}" ]] || extra+=(-quiet)

# ${extra[@]+…} keeps macOS's bash 3.2 from failing on an empty array under set -u.
exec scripts/with-simulator.sh sh -c '
  xcodebuild "$@" -project Dogear.xcodeproj -scheme Dogear \
    -destination "id=$UDID" -derivedDataPath .build/DD
' sh "$action" ${extra[@]+"${extra[@]}"}
