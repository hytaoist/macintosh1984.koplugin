#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
if [ "${KEEP_TEST_DIR:-0}" != "1" ]; then
    trap 'rm -rf "$TMP_DIR"' EXIT
else
    printf 'Test directory: %s\n' "$TMP_DIR"
fi

(
    cd "$PROJECT_DIR"
    lua tests/recovery_test.lua "$TMP_DIR"
)
