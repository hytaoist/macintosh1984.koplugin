#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

REPO="${GITHUB_REPO:-hytaoist/macintosh1984.koplugin}"
VERSION="$(
    lua - "$SCRIPT_DIR/plugin/_meta.lua" <<'LUA'
local path = assert(arg[1], "missing _meta.lua path")
local meta = assert(dofile(path), "invalid _meta.lua")
io.write(meta.version)
LUA
)"
TAG="v$VERSION"
BRANCH="${GITHUB_BRANCH:-main}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    printf 'This directory is not a Git repository. Initialize it before publishing.\n' >&2
    exit 1
}
gh auth status >/dev/null 2>&1 || {
    printf 'GitHub CLI is not authenticated. Run: gh auth login\n' >&2
    exit 1
}
if [ -n "$(git status --porcelain)" ]; then
    printf 'Working tree is not clean. Commit the release changes first.\n' >&2
    exit 1
fi

./build.sh

if ! gh repo view "$REPO" >/dev/null 2>&1; then
    if [ "${CREATE_GITHUB_REPO:-0}" != "1" ]; then
        printf 'Repository %s does not exist. Re-run with CREATE_GITHUB_REPO=1 to create it.\n' "$REPO" >&2
        exit 1
    fi
    gh repo create "$REPO" --public --source=. --remote=origin --push
fi

if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "git@github.com:$REPO.git"
fi

git push origin "$BRANCH"
gh repo edit "$REPO" \
    --add-topic koreader-plugin \
    --add-topic koreader \
    --add-topic kindle >/dev/null

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
    git tag -a "$TAG" -m "Macintosh 1984 $TAG"
fi
git push origin "$TAG"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" \
        "dist/macintosh1984-$TAG.koplugin.zip" \
        "dist/macintosh1984-$TAG.zip" \
        "dist/SHA256SUMS" \
        --repo "$REPO" --clobber
else
    gh release create "$TAG" \
        "dist/macintosh1984-$TAG.koplugin.zip" \
        "dist/macintosh1984-$TAG.zip" \
        "dist/SHA256SUMS" \
        --repo "$REPO" \
        --title "Macintosh 1984 $TAG" \
        --generate-notes
fi

printf 'Published: https://github.com/%s/releases/tag/%s\n' "$REPO" "$TAG"
