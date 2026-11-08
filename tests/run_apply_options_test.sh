#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

(
    cd "$PROJECT_DIR"
    for mode in safe no_font; do
        MAC1984_TEST_MODE="$mode" lua tests/apply_options_test.lua \
            plugin/theme/apply.lua
    done
)
