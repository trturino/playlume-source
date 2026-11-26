#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc Hololink/StereoDepthSettings.swift Tests/StereoDepthSettingsTests.swift -o "$test_dir/settings"
"$test_dir/settings"
xcrun swiftc Hololink/StereoVideoColorProfile.swift Tests/StereoVideoColorTests.swift -o "$test_dir/color"
"$test_dir/color"
