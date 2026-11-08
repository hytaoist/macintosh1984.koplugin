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

make_plugin() {
    local root="$1"
    local name="$2"
    local source="$3"
    mkdir -p "$root/$name/theme"
    printf '_G.mac1984_loader_test_loaded = "%s"\n' "$source" \
        > "$root/$name/theme/apply.lua"
}

run_case() {
    local name="$1"
    local data_dir="$2"
    local expected="$3"
    shift 3
    (
        cd "$PROJECT_DIR"
        lua tests/loader_test.lua "$data_dir" "$expected" "$@"
    )
    printf 'loader case OK: %s\n' "$name"
}

DATA_A="$TMP_DIR/data-a"
NEW_A="$TMP_DIR/new-a"
mkdir -p "$DATA_A/plugins"
make_plugin "$NEW_A" "macintosh1984.koplugin" "new"
run_case "new package path" "$DATA_A" "new" "$NEW_A/macintosh1984.koplugin"

DATA_B="$TMP_DIR/data-b"
LEGACY_B="$TMP_DIR/legacy-b"
mkdir -p "$DATA_B/plugins"
make_plugin "$LEGACY_B" "mac1984-koreader.koplugin" "legacy"
run_case "legacy package path" "$DATA_B" "legacy" \
    "$LEGACY_B/mac1984-koreader.koplugin"

DATA_C="$TMP_DIR/data-c"
BOTH_C="$TMP_DIR/both-c"
mkdir -p "$DATA_C/plugins"
make_plugin "$BOTH_C" "macintosh1984.koplugin" "new"
make_plugin "$BOTH_C" "mac1984-koreader.koplugin" "legacy"
run_case "new wins over legacy" "$DATA_C" "new" \
    "$BOTH_C/mac1984-koreader.koplugin" "$BOTH_C/macintosh1984.koplugin"

DATA_D="$TMP_DIR/data-d"
mkdir -p "$DATA_D/plugins"
make_plugin "$DATA_D/plugins" "macintosh1984.koplugin" "new"
make_plugin "$DATA_D/plugins" "mac1984-koreader.koplugin" "legacy"
run_case "data-dir fallback prefers new" "$DATA_D" "new"

DATA_E="$TMP_DIR/data-e"
mkdir -p "$DATA_E/plugins"
make_plugin "$DATA_E/plugins" "mac1984-koreader.koplugin" "legacy"
run_case "data-dir fallback supports legacy" "$DATA_E" "legacy"

printf 'loader test OK\n'
