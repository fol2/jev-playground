#!/bin/sh
# Portable offline tests; no SDK downloads, credentials, captures or input events.
set -eu
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
swiftc -parse-as-library -O -D CORE_TESTS \
  experiments/001_wow_fishing/decision.swift \
  experiments/001_wow_fishing/motion.swift \
  experiments/001_wow_fishing/jev.swift \
  experiments/001_wow_fishing/tests/CoreTests.swift -o "$tmp/core-tests"
"$tmp/core-tests"
swiftc -parse-as-library -O -D CORE_TESTS \
  experiments/001_wow_fishing/motion.swift \
  experiments/001_wow_fishing/tests/MotionChecks.swift -o "$tmp/motion-checks"
"$tmp/motion-checks"
