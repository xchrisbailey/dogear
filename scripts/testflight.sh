#!/usr/bin/env bash
# Archives Dogear and uploads it to App Store Connect for TestFlight.
#
# Signing is cloud-managed: with an App Store Connect API key (Admin role), xcodebuild registers
# the bundle ID and creates the distribution certificate and profile as needed.
#
# Needs: ASC_KEY_ID and ASC_ISSUER_ID in the environment, and the key at
# ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8 (override with ASC_KEY_PATH).
# Usage: scripts/testflight.sh [build-number]   (defaults to a UTC timestamp, always increasing)
set -euo pipefail

cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
[[ -f "$ASC_KEY_PATH" ]] || { echo "API key not found at $ASC_KEY_PATH" >&2; exit 1; }

BUILD_NUMBER="${1:-$(date -u +%Y%m%d%H%M)}"
OUT=".build/testflight"
ARCHIVE="$OUT/Dogear.xcarchive"
rm -rf "$OUT" && mkdir -p "$OUT"

auth=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

# Resolve the Nix wrapper so XcodeGen finds its bundled resources (see AGENTS.md).
"$(readlink -f "$(command -v xcodegen)")" generate

xcodebuild archive \
  -project Dogear.xcodeproj -scheme Dogear -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${auth[@]}"

cat > "$OUT/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>signingStyle</key><string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  "${auth[@]}"

echo "Uploaded build $BUILD_NUMBER. It appears in App Store Connect → TestFlight once processing finishes."
