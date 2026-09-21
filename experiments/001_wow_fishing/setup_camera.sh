#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
# A disposable build: no persistent service, capture archive or provider calls.
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/jev-camera-setup.XXXXXX")
trap 'rm -f "$build_dir/setup-camera"; rmdir "$build_dir"' EXIT HUP INT TERM
swiftc -parse-as-library -O \
  experiments/001_wow_fishing/probes/background-click/Adapter.swift \
  experiments/001_wow_fishing/probes/background-click/NativeWindowServerPreparation.swift \
  experiments/001_wow_fishing/probes/background-click/NativeBackgroundClickTransport.swift \
  experiments/001_wow_fishing/setup_camera.swift -o "$build_dir/setup-camera"
"$build_dir/setup-camera" "$@"
