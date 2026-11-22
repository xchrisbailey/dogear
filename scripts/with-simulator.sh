#!/usr/bin/env bash
# Runs a command against a throwaway iOS simulator, then always deletes it.
#
#   scripts/with-simulator.sh <command…>   creates a device, exports UDID, runs the command
#   scripts/with-simulator.sh status        lists booted devices and leftover simulator processes
#
# A leaked headless simulator keeps crashing system daemons (PosterBoard) and shows the user
# a crash dialog each time, so the device is removed on every exit path, including Ctrl-C.
# Override the device with SIM_DEVICE_TYPE / SIM_RUNTIME (simctl identifiers).
set -euo pipefail

if [[ "${1:-}" == "status" ]]; then
  echo "Booted devices:"
  xcrun simctl list devices booted | grep -E "\(Booted\)" || echo "  none"
  echo "Simulator processes:"
  pgrep -l launchd_sim || echo "  none"
  exit 0
fi

[[ $# -gt 0 ]] || { echo "usage: $0 <command…> | status" >&2; exit 64; }

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
UDID="$(xcrun simctl create "$name" "$device_type" "$runtime")"
export UDID

cleanup() {
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

xcrun simctl boot "$UDID"
"$@"
