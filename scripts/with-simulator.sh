#!/usr/bin/env bash
# Runs a command against a throwaway iOS simulator, then always deletes it.
#
#   scripts/with-simulator.sh <command…>   creates a device, exports UDID, runs the command
#   scripts/with-simulator.sh status        lists booted devices and leftover simulator processes
#   scripts/with-simulator.sh create        only creates a device and prints its UDID
#
# A leaked headless simulator keeps crashing system daemons (PosterBoard) and shows the user
# a crash dialog each time, so the device is removed on every exit path, including Ctrl-C.
# Override the device with SIM_DEVICE_TYPE / SIM_RUNTIME (simctl identifiers).
#
# CI boots its device early, in the background, because a cold boot there takes one to eight
# minutes: it runs `create`, starts the boot, and passes the device back in as SIM_UDID. A
# device handed over that way is the caller's to delete (CI's whole machine is thrown away).
set -euo pipefail

if [[ "${1:-}" == "status" ]]; then
  echo "Booted devices:"
  xcrun simctl list devices booted | grep -E "\(Booted\)" || echo "  none"
  echo "Simulator processes:"
  pgrep -l launchd_sim || echo "  none"
  exit 0
fi

[[ $# -gt 0 ]] || { echo "usage: $0 <command…> | status | create" >&2; exit 64; }

# APP_VERBOSE=1 narrates each stage, so a timestamped log shows which one is slow.
note() { [[ -z "${APP_VERBOSE:-}" ]] || echo "with-simulator: $*" >&2; }

if [[ -n "${SIM_UDID:-}" ]]; then
  # Possibly still booting: xcodebuild waits for its destination, so the build overlaps it.
  note "using $SIM_UDID, started by the caller"
  export UDID="$SIM_UDID"
  exec "$@"
fi

note "listing runtimes"
# Pick the device type from the runtime's own supported list: the newest device type
# installed isn't always one the newest runtime can boot.
read -r runtime device_type < <(xcrun simctl list runtimes available -j | python3 -c '
import json, os, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS"]
want = os.environ.get("SIM_RUNTIME")
runtime = next(r for r in runtimes if r["identifier"] == want) if want else runtimes[-1]
types = [t for t in runtime["supportedDeviceTypes"] if t["productFamily"] == "iPhone"]
pros = [t for t in types if "Pro" in t["name"] and "Max" not in t["name"]] or types
print(runtime["identifier"], os.environ.get("SIM_DEVICE_TYPE") or pros[-1]["identifier"])
')

name="dogear-$(basename "$PWD")-$$"
note "creating $device_type on $runtime"
UDID="$(xcrun simctl create "$name" "$device_type" "$runtime")"
export UDID

if [[ "$1" == "create" ]]; then
  echo "$UDID"
  exit 0
fi

cleanup() {
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

note "booting $UDID"
xcrun simctl boot "$UDID"
note "booted, running the command"
"$@"
