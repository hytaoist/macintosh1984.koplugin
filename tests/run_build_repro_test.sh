#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cd "$PROJECT_DIR"
./build.sh >/dev/null
VERSION="$(lua -e 'io.write(assert(dofile("plugin/_meta.lua")).version)')"
STANDALONE_ARCHIVE="dist/macintosh1984-v$VERSION.zip"
PLUGIN_ARCHIVE="dist/macintosh1984-v$VERSION.koplugin.zip"
cp dist/SHA256SUMS "$TMP_DIR/first.sums"
cp dist/*.zip "$TMP_DIR/"

if ! unzip -Z1 "$STANDALONE_ARCHIVE" \
    | grep -q '^macintosh1984/DEVELOPMENT.md$'; then
    printf 'Standalone archive validation failed: missing DEVELOPMENT.md\n' >&2
    exit 1
fi

if ! unzip -Z1 "$PLUGIN_ARCHIVE" \
    | grep -q '^macintosh1984.koplugin/_meta.lua$'; then
    printf 'Storefront archive validation failed: missing new ZIP root\n' >&2
    exit 1
fi

if unzip -Z1 "$PLUGIN_ARCHIVE" | grep -q '^mac1984-koreader.koplugin/'; then
    printf 'Storefront archive validation failed: legacy ZIP root is present\n' >&2
    exit 1
fi

./build.sh >/dev/null
cmp -s "$TMP_DIR/first.sums" dist/SHA256SUMS
for archive in dist/*.zip; do
    cmp -s "$TMP_DIR/$(basename "$archive")" "$archive"
done

printf 'build reproducibility test OK\n'
