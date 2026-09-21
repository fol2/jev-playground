#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
swiftc -parse-as-library -O \
  experiments/001_wow_fishing/probes/background-click/Adapter.swift \
  experiments/001_wow_fishing/probes/background-click/NativeWindowServerPreparation.swift \
  experiments/001_wow_fishing/probes/background-click/NativeBackgroundClickTransport.swift \
  experiments/001_wow_fishing/motion.swift \
  experiments/001_wow_fishing/loot.swift \
  experiments/001_wow_fishing/jev.swift \
  experiments/001_wow_fishing/live.swift -o /tmp/jev-fishing-live
/tmp/jev-fishing-live --self-test
