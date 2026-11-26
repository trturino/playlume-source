#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build
options=()
if [[ "${UNSIGNED:-0}" == 1 ]]; then
  options+=(CODE_SIGNING_ALLOWED=NO)
else
  : "${PROFILE_NAME:?Set PROFILE_NAME to the installed App Store provisioning profile name}"
  options+=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Apple Distribution" "PROVISIONING_PROFILE_SPECIFIER=$PROFILE_NAME")
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  [[ "$BUILD_NUMBER" =~ ^[1-9][0-9]{0,3}\.[0-9]{1,2}\.[0-9]{1,2}$ ]] || {
    echo 'BUILD_NUMBER must use Apple-compatible major.minor.patch (e.g. 2026.11.26).' >&2
    exit 1
  }
  options+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
fi
xcodebuild archive -project Moonlight.xcodeproj -scheme 'Moonlight Vision' \
  -configuration Release -destination 'generic/platform=visionOS' \
  -onlyUsePackageVersionsFromResolvedFile \
  -archivePath "${ARCHIVE_PATH:-Build/Hololink.xcarchive}" \
  -derivedDataPath DerivedData "${options[@]}" 2>&1 | tee Build/archive.log
