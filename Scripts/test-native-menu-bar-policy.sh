#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/IceNativePolicy.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library \
    "$ROOT_DIR/Ice/MenuBar/Native/NativeMenuBarPolicy.swift" \
    "$ROOT_DIR/Ice/MenuBar/Native/NativeClockClickPolicy.swift" \
    "$ROOT_DIR/Tests/NativeMenuBar/PolicyTest.swift" \
    -o "$TEST_DIR/PolicyTest"
"$TEST_DIR/PolicyTest"
