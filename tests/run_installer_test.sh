#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="$(
    lua - "$PROJECT_DIR/plugin/_meta.lua" <<'LUA'
local path = assert(arg[1], "missing _meta.lua path")
local meta = assert(dofile(path), "invalid _meta.lua")
io.write(meta.version)
LUA
)"
TMP_DIR="$(mktemp -d)"
if [ "${KEEP_TEST_DIR:-0}" != "1" ]; then
    trap 'rm -rf "$TMP_DIR"' EXIT
else
    printf 'Test directory: %s\n' "$TMP_DIR"
fi

KO_DIR="$TMP_DIR/Kindle/koreader"
SETTINGS_DIR="$KO_DIR/settings/simpleui"
mkdir -p "$KO_DIR/icons" "$KO_DIR/fonts" \
    "$SETTINGS_DIR/sui_icons/packs/Solar Mono"
touch "$KO_DIR/reader.lua"
printf 'STOCK\n' > "$KO_DIR/icons/appbar.menu.svg"
printf '%s\n' \
    'return {' \
    '    ["simpleui_ui_font_name"] = "OpenDyslexic",' \
    '    ["simpleui_sysicon_menu"] = "./settings/simpleui/sui_icons/packs/Solar Mono/menu.svg",' \
    '    ["user_choice"] = "keep",' \
    '    ["changed_after_install"] = false,' \
    '}' \
    > "$SETTINGS_DIR/sui_settings.lua"

LEGACY_PLUGIN_DIR="$KO_DIR/plugins/mac1984-koreader.koplugin"
mkdir -p "$LEGACY_PLUGIN_DIR/theme"
printf 'return { name = "mac1984" }\n' > "$LEGACY_PLUGIN_DIR/_meta.lua"
printf 'return {}\n' > "$LEGACY_PLUGIN_DIR/main.lua"
printf '_G.legacy_plugin_should_be_removed = true\n' \
    > "$LEGACY_PLUGIN_DIR/theme/apply.lua"

"$PROJECT_DIR/install.sh" "$KO_DIR" >/dev/null

PLUGIN_DIR="$KO_DIR/plugins/macintosh1984.koplugin"
THEME_DIR="$KO_DIR/.mac1984-theme"
SETTINGS_FILE="$SETTINGS_DIR/sui_settings.lua"

test ! -e "$LEGACY_PLUGIN_DIR"
test -f "$PLUGIN_DIR/_meta.lua"
test -f "$PLUGIN_DIR/main.lua"
test -f "$PLUGIN_DIR/assets/icons/appbar.menu.svg"
test -f "$PLUGIN_DIR/assets/sponsor/wechat-reward.jpg"
test -f "$PLUGIN_DIR/loader.lua"
test -f "$KO_DIR/patches/2-mac1984.lua"
test -f "$KO_DIR/fonts/Mac1984Chicago.ttf"
test -f "$SETTINGS_DIR/sui_icons/packs/Macintosh 1984/pack.lua"
test "$(cat "$THEME_DIR/version")" = "$VERSION"
test "$(cat "$THEME_DIR/backup/D/icons/appbar.menu.svg")" = "STOCK"
grep -Fq $'D\ticons/appbar.menu.svg' "$THEME_DIR/installed.tsv"
grep -Fq $'S\tsimpleui/sui_settings.lua' "$THEME_DIR/installed.tsv"
grep -Fq 'packs/Macintosh 1984/' "$SETTINGS_FILE"
grep -Fq '"ChicagoFLF"' "$SETTINGS_FILE"
if find "$KO_DIR" -name '._*' -print -quit | grep -q .; then
    printf 'AppleDouble sidecar found after install\n' >&2
    exit 1
fi

# Fake the directory sidecars macOS can create on exFAT. Reinstall must clean
# the theme-owned metadata without touching unrelated files.
touch "$KO_DIR/plugins/._mac1984-koreader.koplugin"
touch "$KO_DIR/plugins/._macintosh1984.koplugin"
touch "$PLUGIN_DIR/._assets"
touch "$THEME_DIR/._version"
touch "$SETTINGS_DIR/sui_icons/packs/._Macintosh 1984"

# Reinstalling must not replace the original backup with the themed icon.
"$PROJECT_DIR/install.sh" "$KO_DIR" >/dev/null
test "$(cat "$THEME_DIR/backup/D/icons/appbar.menu.svg")" = "STOCK"
if find "$KO_DIR" -name '._*' -print -quit | grep -q .; then
    printf 'AppleDouble sidecar survived reinstall\n' >&2
    exit 1
fi

awk '{
    gsub(/\["changed_after_install"\] = false/, "[\"changed_after_install\"] = true")
    print
}' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
touch "$KO_DIR/plugins/._mac1984-koreader.koplugin"
touch "$KO_DIR/plugins/._macintosh1984.koplugin"
touch "$THEME_DIR/._version"
touch "$SETTINGS_DIR/sui_icons/packs/._Macintosh 1984"
touch "$KO_DIR/settings/mac1984-koreader.lua"

# A stale legacy copy must also be removed by uninstall.
mkdir -p "$LEGACY_PLUGIN_DIR"
touch "$LEGACY_PLUGIN_DIR/_meta.lua" "$LEGACY_PLUGIN_DIR/main.lua"
"$PROJECT_DIR/uninstall.sh" "$KO_DIR" >/dev/null

test "$(cat "$KO_DIR/icons/appbar.menu.svg")" = "STOCK"
test ! -e "$PLUGIN_DIR"
test ! -e "$LEGACY_PLUGIN_DIR"
test ! -e "$THEME_DIR"
test ! -e "$KO_DIR/settings/mac1984-koreader.lua"
if find "$KO_DIR" -name '._*' -print -quit | grep -q .; then
    printf 'AppleDouble sidecar survived uninstall\n' >&2
    exit 1
fi
grep -Fq 'packs/Solar Mono/' "$SETTINGS_FILE"
grep -Fq '"OpenDyslexic"' "$SETTINGS_FILE"
grep -Fq '["user_choice"] = "keep"' "$SETTINGS_FILE"
grep -Fq '["changed_after_install"] = true' "$SETTINGS_FILE"

printf 'installer test OK\n'
