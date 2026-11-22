#!/usr/bin/env bash
# Generates the Xcode project, then builds or tests the app.
#   scripts/app.sh build     builds the app on a throwaway simulator
#   scripts/app.sh compile   builds the app and its tests for the simulator without booting one
#   scripts/app.sh test      compile, then runs seam 2 on a throwaway simulator
# XCODEBUILD_EXTRA_ARGS adds flags to every xcodebuild call.
# APP_VERBOSE=1 prints xcodebuild's full log instead of only warnings and errors.
set -euo pipefail
cd "$(dirname "$0")/.."

action="${1:-}"
[[ "$action" == build || "$action" == compile || "$action" == test ]] ||
  { echo "usage: $0 build|compile|test" >&2; exit 64; }

note() { [[ -z "${APP_VERBOSE:-}" ]] || echo "app.sh: $*" >&2; }

# The Nix xcodegen wrapper only finds its bundled resources through its resolved path.
note "generating the project"
"$(readlink -f "$(command -v xcodegen)")" generate --quiet

read -ra extra <<< "${XCODEBUILD_EXTRA_ARGS:-}"
[[ -n "${APP_VERBOSE:-}" ]] || extra+=(-quiet)

# No device needed to compile, so a simulator's boot never holds up a build failure. A generic
# destination would build every architecture; this machine's is the one its simulators run.
compile() {
  note "compiling the app and its tests"
  xcodebuild build-for-testing -project Dogear.xcodeproj -scheme Dogear \
    -destination "generic/platform=iOS Simulator" -derivedDataPath .build/DD \
    "ARCHS=$(uname -m)" ${extra[@]+"${extra[@]}"}
}

# ${extra[@]+…} keeps macOS's bash 3.2 from failing on an empty array under set -u.
on_simulator() {
  exec scripts/with-simulator.sh sh -c '
    xcodebuild "$@" -project Dogear.xcodeproj -scheme Dogear \
      -destination "id=$UDID" -derivedDataPath .build/DD
  ' sh "$@" ${extra[@]+"${extra[@]}"}
}

case "$action" in
  build) on_simulator build ;;
  compile) compile ;;
  test)
    compile
    on_simulator test-without-building
    ;;
esac
