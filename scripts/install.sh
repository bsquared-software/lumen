#!/usr/bin/env bash
# Builds Lumen in Release and installs it into /Applications, replacing any previous copy.
set -euo pipefail

cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "xcodegen is required: brew install xcodegen" >&2; exit 1; }

xcodegen generate --quiet
xcodebuild -project Lumen.xcodeproj -scheme Lumen -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build -quiet build

built="build/Build/Products/Release/Lumen.app"
installed="/Applications/Lumen.app"

if pgrep -x Lumen >/dev/null; then
  pkill -x Lumen
  sleep 1
fi

rm -rf "$installed"
ditto "$built" "$installed"
open "$installed"
echo "Installed $installed"
