#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
PLUGIN_NAME="macintosh1984.koplugin"
STAGE_DIR="$DIST_DIR/.stage"
PLUGIN_STAGE="$STAGE_DIR/$PLUGIN_NAME"
STANDALONE_NAME="macintosh1984"
STANDALONE_STAGE="$STAGE_DIR/$STANDALONE_NAME"

VERSION="$(
    lua - "$SCRIPT_DIR/plugin/_meta.lua" <<'LUA'
local path = assert(arg[1], "missing _meta.lua path")
local meta = assert(dofile(path), "invalid _meta.lua")
assert(type(meta.version) == "string" and meta.version ~= "", "missing plugin version")
io.write(meta.version)
LUA
)"

PLUGIN_ARCHIVE="$DIST_DIR/macintosh1984-v$VERSION.koplugin.zip"
STANDALONE_ARCHIVE="$DIST_DIR/macintosh1984-v$VERSION.zip"
ZIP_BUILDER="$SCRIPT_DIR/tools/make_zip.py"

rm -rf "$STAGE_DIR"
mkdir -p "$PLUGIN_STAGE" "$STANDALONE_STAGE"

# Storefront payload: the ZIP root must be a .koplugin directory with _meta.lua.
cp -R "$SCRIPT_DIR/plugin/." "$PLUGIN_STAGE/"
mkdir -p "$PLUGIN_STAGE/assets"
cp -R "$SCRIPT_DIR/assets/icons" "$SCRIPT_DIR/assets/simpleui-icons" \
    "$SCRIPT_DIR/assets/sponsor" "$PLUGIN_STAGE/assets/"
mkdir -p "$PLUGIN_STAGE/assets/fonts"
cp "$SCRIPT_DIR/assets/fonts/ChicagoFLF.ttf" \
    "$SCRIPT_DIR/assets/fonts/LICENSE-ChicagoFLF.txt" \
    "$PLUGIN_STAGE/assets/fonts/"
cp "$SCRIPT_DIR/patches/2-mac1984.lua" "$PLUGIN_STAGE/loader.lua"
cp "$SCRIPT_DIR/LICENSE" "$PLUGIN_STAGE/LICENSE"

# Standalone payload keeps the human-readable installer and source layout.
cp "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/README.zh-CN.md" \
    "$SCRIPT_DIR/DEVELOPMENT.md" "$SCRIPT_DIR/LICENSE" \
    "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/uninstall.sh" "$STANDALONE_STAGE/"
cp -R "$SCRIPT_DIR/assets" "$SCRIPT_DIR/patches" "$SCRIPT_DIR/plugin" \
    "$SCRIPT_DIR/preview" "$SCRIPT_DIR/tests" "$SCRIPT_DIR/tools" "$STANDALONE_STAGE/"
chmod +x "$STANDALONE_STAGE/install.sh" "$STANDALONE_STAGE/uninstall.sh"

find "$STAGE_DIR" -name '.DS_Store' -delete
find "$STAGE_DIR" -name '._*' -delete
find "$STAGE_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "$STAGE_DIR" -type f -name '*.pyc' -delete

rm -f "$PLUGIN_ARCHIVE" "$STANDALONE_ARCHIVE" "$DIST_DIR/SHA256SUMS"
python3 "$ZIP_BUILDER" "$PLUGIN_STAGE" "$PLUGIN_NAME" "$PLUGIN_ARCHIVE"
python3 "$ZIP_BUILDER" "$STANDALONE_STAGE" "$STANDALONE_NAME" "$STANDALONE_ARCHIVE"

if ! unzip -Z1 "$PLUGIN_ARCHIVE" | grep -q "^$PLUGIN_NAME/_meta.lua$"; then
    printf 'Storefront archive validation failed: missing %s/_meta.lua\n' "$PLUGIN_NAME" >&2
    exit 1
fi
if unzip -Z1 "$PLUGIN_ARCHIVE" \
    | grep -Eq '^mac1984-koreader([.]koplugin)?/'; then
    printf 'Storefront archive validation failed: wrong ZIP root\n' >&2
    exit 1
fi

(
    cd "$DIST_DIR"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$(basename "$PLUGIN_ARCHIVE")" "$(basename "$STANDALONE_ARCHIVE")" \
            > SHA256SUMS
    else
        shasum -a 256 "$(basename "$PLUGIN_ARCHIVE")" "$(basename "$STANDALONE_ARCHIVE")" \
            > SHA256SUMS
    fi
)

PLUGIN_FILES="$(find "$PLUGIN_STAGE" -type f | wc -l | tr -d ' ')"
printf 'Built Storefront package: %s (%s files)\n' "$PLUGIN_ARCHIVE" "$PLUGIN_FILES"
printf 'Built standalone package: %s\n' "$STANDALONE_ARCHIVE"
printf 'Checksums: %s\n' "$DIST_DIR/SHA256SUMS"
