#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
swiftc -parse-as-library -O \
  experiments/001_wow_fishing/probes/background-click/Adapter.swift \
  experiments/001_wow_fishing/probes/background-click/NativeWindowServerPreparation.swift \
  experiments/001_wow_fishing/probes/background-click/NativeBackgroundClickTransport.swift \
  experiments/001_wow_fishing/decision.swift \
  experiments/001_wow_fishing/motion.swift \
  experiments/001_wow_fishing/loot.swift \
  experiments/001_wow_fishing/jev.swift \
  experiments/001_wow_fishing/self_tests.swift \
  experiments/001_wow_fishing/live.swift -o /tmp/jev-fishing-live
/tmp/jev-fishing-live --self-test
# The offline tools, by absolute path so each finds the repository from its own source.
json="$PWD/experiments/002_wow_visual/runtime/JSON.swift"
tools="$PWD/experiments/001_wow_fishing"
swiftc -parse-as-library -O "$tools/analyse.swift" "$tools/dotenv.swift" "$json" -o /tmp/jev-fishing-analyse
/tmp/jev-fishing-analyse --self-test
swiftc -parse-as-library -O "$tools/record.swift" "$json" -o /tmp/jev-fishing-record
dry=$(/tmp/jev-fishing-record --dry-run --rect 0,0,10,10)  # set -e: a failing dry run stops here
printf '%s\n' "$dry" | grep -q '"model_calls": 0'
if /tmp/jev-fishing-record --dry-run --rect 0,0,0,10 2>/dev/null; then echo "record accepted a zero-width region" >&2; exit 1; fi
swiftc -parse-as-library -O "$tools/run_test_a.swift" "$tools/dotenv.swift" "$json" -o /tmp/jev-fishing-run
