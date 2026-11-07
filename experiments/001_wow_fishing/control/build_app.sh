#!/bin/sh
# Build the fishing agent and the control panel app, then open the panel.
# Start the agent yourself from Terminal (it needs Screen Recording and Accessibility):
#   /tmp/jev-fishing-agent "$PWD"
#   sh experiments/001_wow_fishing/control/build_app.sh [--no-open]
set -eu
cd "$(dirname "$0")/../../.."
app="$HOME/Applications/JevFishingControl.app"
mkdir -p "$app/Contents/MacOS"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.jev-playground.fishing-control</string>
  <key>CFBundleName</key><string>Jev 釣魚控制台</string>
  <key>CFBundleExecutable</key><string>JevFishingControl</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Lowest priority: a build beside a live fishing run must not slow its capture.
nice -n 20 swiftc -parse-as-library -O experiments/001_wow_fishing/control/FishingControl.swift -o "$app/Contents/MacOS/JevFishingControl"
nice -n 20 swiftc -parse-as-library -O experiments/001_wow_fishing/control/FishingAgent.swift -o /tmp/jev-fishing-agent
echo "$app"
[ "${1:-}" = "--no-open" ] || open "$app" --args -root "$PWD"
