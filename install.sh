#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(
    lua - "$SCRIPT_DIR/plugin/_meta.lua" <<'LUA'
local path = assert(arg[1], "missing _meta.lua path")
local meta = assert(dofile(path), "invalid _meta.lua")
assert(type(meta.version) == "string" and meta.version ~= "", "missing plugin version")
io.write(meta.version)
LUA
)"
PLUGIN_NAME="macintosh1984.koplugin"
LEGACY_PLUGIN_NAME="mac1984-koreader.koplugin"
THEME_PACK_NAME="Macintosh 1984"
SIMPLEUI_PACK_PREFIX="simpleui/sui_icons/packs/$THEME_PACK_NAME"
SIMPLEUI_SETTINGS_REL="simpleui/sui_settings.lua"

find_koreader_dir() {
    if [ "${1:-}" != "" ]; then
        local target="$1"
        if [ -d "$target/koreader" ]; then
            printf '%s\n' "$target/koreader"
        elif [ -f "$target/reader.lua" ]; then
            printf '%s\n' "$target"
        else
            return 1
        fi
        return 0
    fi

    for candidate in /Volumes/*; do
        if [ -d "$candidate/koreader" ]; then
            printf '%s\n' "$candidate/koreader"
            return 0
        fi
    done
    return 1
}

if ! KO_DIR="$(find_koreader_dir "${1:-}")"; then
    printf '%s\n' "KOReader directory not found." >&2
    printf '%s\n' "Usage: ./install.sh /path/to/mounted-device" >&2
    printf '%s\n' "   or: ./install.sh /path/to/koreader" >&2
    exit 1
fi

SETTINGS_DIR="$KO_DIR/settings"
THEME_DIR="$KO_DIR/.mac1984-theme"
BACKUP_DIR="$THEME_DIR/backup"
INSTALLED_FILE="$THEME_DIR/installed.tsv"
NEW_INSTALLED_FILE="$THEME_DIR/installed.tsv.new"
PLUGIN_DEST="$KO_DIR/plugins/$PLUGIN_NAME"
LEGACY_PLUGIN_DEST="$KO_DIR/plugins/$LEGACY_PLUGIN_NAME"

mkdir -p "$KO_DIR/icons" "$KO_DIR/fonts" "$KO_DIR/patches" "$KO_DIR/plugins" \
    "$THEME_DIR/runtime" "$BACKUP_DIR"
touch "$INSTALLED_FILE"
: > "$NEW_INSTALLED_FILE"

migrate_v1_backups() {
    local line
    local tag
    local relative
    local old_backup
    local new_backup

    while IFS= read -r line; do
        [ "$line" = "" ] && continue
        case "$line" in
            *$'\t'*) continue ;;
        esac
        if [[ "$line" == settings/simpleui/* ]]; then
            tag="S"
            relative="${line#settings/}"
        else
            tag="D"
            relative="$line"
        fi
        old_backup="$BACKUP_DIR/$line"
        new_backup="$BACKUP_DIR/$tag/$relative"
        if [ -f "$old_backup" ] && [ ! -f "$new_backup" ]; then
            mkdir -p "$(dirname "$new_backup")"
            mv "$old_backup" "$new_backup"
            remove_sidecar "$new_backup"
        fi
    done < "$INSTALLED_FILE"
}

copy_file() {
    # cat avoids macOS writing AppleDouble "._*" sidecars on exFAT volumes.
    cat "$1" > "$2"
}

remove_sidecar() {
    local destination="$1"
    local sidecar
    sidecar="$(dirname "$destination")/._$(basename "$destination")"
    if [ -f "$sidecar" ]; then
        rm -f "$sidecar"
    fi
}

remove_legacy_plugin() {
    if [ "$LEGACY_PLUGIN_DEST" = "$PLUGIN_DEST" ]; then
        return
    fi
    if [ -d "$LEGACY_PLUGIN_DEST" ]; then
        rm -rf "$LEGACY_PLUGIN_DEST"
        printf 'Removed legacy plugin folder: %s\n' "$LEGACY_PLUGIN_DEST"
    fi
    remove_sidecar "$LEGACY_PLUGIN_DEST"
}

clean_macos_metadata() {
    local target
    for target in "$@"; do
        [ -e "$target" ] || continue
        if [ "$(uname -s)" = "Darwin" ] && command -v xattr >/dev/null 2>&1; then
            xattr -cr "$target" 2>/dev/null || true
        fi
        if [ -d "$target" ]; then
            find "$target" -type f \( -name '._*' -o -name '.DS_Store' \) -delete
        fi
        remove_sidecar "$target"
    done
}

migrate_v1_backups

is_recorded() {
    local wanted="$1"
    awk -F '\t' -v wanted="$wanted" '
        {
            tag = $1
            rel = $2
            if (NF == 1) {
                tag = "D"
                rel = $1
            }
            if (tag ":" rel == wanted) found = 1
        }
        END { exit found ? 0 : 1 }
    ' "$INSTALLED_FILE"
}

root_for_tag() {
    case "$1" in
        D) printf '%s\n' "$KO_DIR" ;;
        S) printf '%s\n' "$SETTINGS_DIR" ;;
        *) return 1 ;;
    esac
}

install_file() {
    local source="$1"
    local tag="$2"
    local relative="$3"
    local root
    local destination
    local backup
    local id

    root="$(root_for_tag "$tag")"
    destination="$root/$relative"
    backup="$BACKUP_DIR/$tag/$relative"
    id="$tag:$relative"

    mkdir -p "$(dirname "$destination")"
    if [ -e "$destination" ] && ! is_recorded "$id"; then
        mkdir -p "$(dirname "$backup")"
        copy_file "$destination" "$backup"
        remove_sidecar "$backup"
    fi
    copy_file "$source" "$destination"
    remove_sidecar "$destination"
    printf '%s\t%s\n' "$tag" "$relative" >> "$NEW_INSTALLED_FILE"
}

install_simpleui_settings() {
    local settings="$SETTINGS_DIR/$SIMPLEUI_SETTINGS_REL"
    local backup="$BACKUP_DIR/S/$SIMPLEUI_SETTINGS_REL"
    local tmp="${settings}.mac1984.tmp"
    local id="S:$SIMPLEUI_SETTINGS_REL"

    if [ ! -f "$settings" ]; then
        printf '%s\n' "SimpleUI settings not found; the icon pack will still be available in SimpleUI."
        return
    fi

    if ! is_recorded "$id"; then
        mkdir -p "$(dirname "$backup")"
        copy_file "$settings" "$backup"
        remove_sidecar "$backup"
    fi

    awk -v theme_prefix="$THEME_PACK_NAME/" '
        {
            line = $0
            if (line ~ /sui_icons\/packs\//) {
                prefix = line
                sub(/sui_icons\/packs\/.*/, "", prefix)
                rest = line
                sub(/^.*sui_icons\/packs\//, "", rest)
                sub(/\/.*/, "", rest)
                line = prefix "sui_icons/packs/" theme_prefix substr(line, index(line, "sui_icons/packs/") + length("sui_icons/packs/") + length(rest) + 1)
            }
            if (line ~ /^[[:space:]]*\["simpleui_ui_font_name"\][[:space:]]*=/) {
                match(line, /^[[:space:]]*/)
                line = substr(line, 1, RLENGTH) "[\"simpleui_ui_font_name\"] = \"ChicagoFLF\","
            }
            print line
        }
    ' "$settings" > "$tmp"
    mv "$tmp" "$settings"
    remove_sidecar "$settings"
    printf '%s\t%s\n' "S" "$SIMPLEUI_SETTINGS_REL" >> "$NEW_INSTALLED_FILE"
}

copy_plugin_tree() {
    local source_root="$1"
    local destination_root="$2"
    rm -rf "$destination_root"
    mkdir -p "$destination_root"
    while IFS= read -r source; do
        local relative="${source#"$source_root"/}"
        local destination="$destination_root/$relative"
        mkdir -p "$(dirname "$destination")"
        copy_file "$source" "$destination"
        remove_sidecar "$destination"
    done < <(find "$source_root" -type f ! -name '.DS_Store' ! -name '._*' | sort)
}

# Install the Storefront-compatible wrapper. The stable patch below loads the
# newest available runtime from this directory on every KOReader restart.
copy_plugin_tree "$SCRIPT_DIR/plugin" "$PLUGIN_DEST"
mkdir -p "$PLUGIN_DEST/assets"
while IFS= read -r source; do
    relative="${source#"$SCRIPT_DIR/assets/"}"
    destination="$PLUGIN_DEST/assets/$relative"
    mkdir -p "$(dirname "$destination")"
    copy_file "$source" "$destination"
    remove_sidecar "$destination"
done < <(find "$SCRIPT_DIR/assets/icons" "$SCRIPT_DIR/assets/simpleui-icons" \
    "$SCRIPT_DIR/assets/fonts" "$SCRIPT_DIR/assets/sponsor" \
    -type f ! -name '.DS_Store' ! -name '._*' | sort)
copy_file "$SCRIPT_DIR/patches/2-mac1984.lua" "$PLUGIN_DEST/loader.lua"
copy_file "$SCRIPT_DIR/LICENSE" "$PLUGIN_DEST/LICENSE"
remove_sidecar "$PLUGIN_DEST/loader.lua"
remove_sidecar "$PLUGIN_DEST/LICENSE"

install_file "$SCRIPT_DIR/patches/2-mac1984.lua" "D" "patches/2-mac1984.lua"
install_file "$SCRIPT_DIR/plugin/theme/apply.lua" "D" ".mac1984-theme/runtime/apply.lua"
install_file "$SCRIPT_DIR/assets/fonts/ChicagoFLF.ttf" "D" "fonts/Mac1984Chicago.ttf"

ICON_COUNT=0
while IFS= read -r icon; do
    install_file "$icon" "D" "icons/$(basename "$icon")"
    ICON_COUNT=$((ICON_COUNT + 1))
done < <(find "$SCRIPT_DIR/assets/icons" -type f -name '*.svg' | sort)

install_file "$SCRIPT_DIR/assets/simpleui-icons/pack.lua" "S" "$SIMPLEUI_PACK_PREFIX/pack.lua"
SIMPLEUI_ICON_COUNT=0
while IFS= read -r icon; do
    install_file "$icon" "S" "$SIMPLEUI_PACK_PREFIX/$(basename "$icon")"
    SIMPLEUI_ICON_COUNT=$((SIMPLEUI_ICON_COUNT + 1))
done < <(find "$SCRIPT_DIR/assets/simpleui-icons" -type f -name '*.svg' | sort)
install_simpleui_settings

mkdir -p "$THEME_DIR/runtime"
mv "$NEW_INSTALLED_FILE" "$INSTALLED_FILE"
printf '%s\n' "$VERSION" > "$THEME_DIR/version"

clean_macos_metadata "$PLUGIN_DEST" "$THEME_DIR" \
    "$SETTINGS_DIR/$SIMPLEUI_PACK_PREFIX"
remove_sidecar "$KO_DIR/patches/2-mac1984.lua"
remove_sidecar "$KO_DIR/fonts/Mac1984Chicago.ttf"
remove_sidecar "$SETTINGS_DIR/$SIMPLEUI_SETTINGS_REL"
remove_legacy_plugin

printf '\nMacintosh 1984 for KOReader %s installed.\n' "$VERSION"
printf '  KOReader: %s\n' "$KO_DIR"
printf '  Plugin:   %s\n' "$PLUGIN_DEST"
printf '  Icons:    %s\n' "$ICON_COUNT"
printf '  SimpleUI: %s icons + Macintosh 1984 pack\n' "$SIMPLEUI_ICON_COUNT"
printf '  Font:     ChicagoFLF\n\n'
printf 'Fully quit and restart KOReader to apply the theme.\n'
printf 'To remove it later, run: ./uninstall.sh "%s"\n' "$KO_DIR"
