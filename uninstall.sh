#!/usr/bin/env bash
set -eu

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
    printf '%s\n' "Usage: ./uninstall.sh /path/to/mounted-device" >&2
    printf '%s\n' "   or: ./uninstall.sh /path/to/koreader" >&2
    exit 1
fi

SETTINGS_DIR="$KO_DIR/settings"
THEME_DIR="$KO_DIR/.mac1984-theme"
BACKUP_DIR="$THEME_DIR/backup"
INSTALLED_FILE="$THEME_DIR/installed.tsv"
PLUGIN_DEST="$KO_DIR/plugins/$PLUGIN_NAME"
LEGACY_PLUGIN_DEST="$KO_DIR/plugins/$LEGACY_PLUGIN_NAME"

if [ ! -f "$INSTALLED_FILE" ]; then
    printf '%s\n' "Installation manifest not found: $INSTALLED_FILE" >&2
    printf '%s\n' "Nothing was changed." >&2
    exit 1
fi

copy_file() {
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

restore_simpleui_settings() {
    local settings="$SETTINGS_DIR/$SIMPLEUI_SETTINGS_REL"
    local backup="$BACKUP_DIR/S/$SIMPLEUI_SETTINGS_REL"
    local tmp="${settings}.mac1984.tmp"
    local original_pack
    local original_font

    [ -f "$settings" ] || return
    [ -f "$backup" ] || return

    original_pack="$(
        awk '
            {
                p = index($0, "sui_icons/packs/")
                if (p > 0) {
                    rest = substr($0, p + length("sui_icons/packs/"))
                    slash = index(rest, "/")
                    if (slash > 0) {
                        print substr(rest, 1, slash - 1)
                        exit
                    }
                }
            }
        ' "$backup"
    )"
    [ "$original_pack" != "" ] || return

    original_font="$(
        sed -n 's/.*\["simpleui_ui_font_name"\] = "\([^"]*\)".*/\1/p' "$backup" \
            | head -n 1
    )"

    awk -v theme_prefix="sui_icons/packs/$THEME_PACK_NAME/" \
        -v original_prefix="sui_icons/packs/$original_pack/" \
        -v original_font="$original_font" '
        {
            gsub(theme_prefix, original_prefix)
            if ($0 ~ /^[[:space:]]*\["simpleui_ui_font_name"\][[:space:]]*=/) {
                if (index($0, "\"ChicagoFLF\"") > 0 && original_font != "") {
                    match($0, /^[[:space:]]*/)
                    print substr($0, 1, RLENGTH) "[\"simpleui_ui_font_name\"] = \"" original_font "\","
                    next
                }
            }
            print
        }
    ' "$settings" > "$tmp"
    mv "$tmp" "$settings"
    remove_sidecar "$settings"
}

RESTORED=0
REMOVED=0

restore_simpleui_settings

while IFS=$'\t' read -r tag relative extra; do
    if [ "$tag" = "" ] || [ "$tag" = "$relative" ]; then
        continue
    fi
    if [ "$relative" = "" ]; then
        relative="$tag"
        tag="D"
    fi
    if [ "$tag" = "S" ] && [ "$relative" = "$SIMPLEUI_SETTINGS_REL" ]; then
        continue
    fi

    case "$tag" in
        D) root="$KO_DIR" ;;
        S) root="$SETTINGS_DIR" ;;
        *) continue ;;
    esac

    destination="$root/$relative"
    backup="$BACKUP_DIR/$tag/$relative"
    if [ ! -f "$backup" ]; then
        if [ "$tag" = "D" ] && [ -f "$BACKUP_DIR/$relative" ]; then
            backup="$BACKUP_DIR/$relative"
        elif [ "$tag" = "S" ] && [ -f "$BACKUP_DIR/settings/$relative" ]; then
            backup="$BACKUP_DIR/settings/$relative"
        fi
    fi
    if [ -f "$backup" ]; then
        mkdir -p "$(dirname "$destination")"
        copy_file "$backup" "$destination"
        RESTORED=$((RESTORED + 1))
    elif [ -f "$destination" ]; then
        rm -f "$destination"
        REMOVED=$((REMOVED + 1))
    fi
    remove_sidecar "$destination"
done < "$INSTALLED_FILE"

# The plugin folder is managed separately from the deployed theme manifest.
rm -rf "$PLUGIN_DEST"
rm -rf "$LEGACY_PLUGIN_DEST"
rm -rf "$THEME_DIR"
remove_sidecar "$PLUGIN_DEST"
remove_sidecar "$LEGACY_PLUGIN_DEST"
remove_sidecar "$THEME_DIR"
remove_sidecar "$SETTINGS_DIR/$SIMPLEUI_PACK_PREFIX"
remove_sidecar "$KO_DIR/patches/2-mac1984.lua"
remove_sidecar "$KO_DIR/fonts/Mac1984Chicago.ttf"
remove_sidecar "$SETTINGS_DIR/$SIMPLEUI_SETTINGS_REL"
rm -f "$SETTINGS_DIR/mac1984-koreader.lua"
remove_sidecar "$SETTINGS_DIR/mac1984-koreader.lua"

rmdir "$KO_DIR/icons" 2>/dev/null || true
rmdir "$KO_DIR/plugins" 2>/dev/null || true
rmdir "$SETTINGS_DIR/$SIMPLEUI_PACK_PREFIX" 2>/dev/null || true
rmdir "$SETTINGS_DIR/simpleui/sui_icons/packs" 2>/dev/null || true
rmdir "$SETTINGS_DIR/simpleui/sui_icons" 2>/dev/null || true
rmdir "$SETTINGS_DIR/simpleui" 2>/dev/null || true
rmdir "$SETTINGS_DIR" 2>/dev/null || true

printf '\nMacintosh 1984 theme removed.\n'
printf '  Deleted:  %s files\n' "$REMOVED"
printf '  Restored: %s files\n\n' "$RESTORED"
printf 'Fully quit and restart KOReader.\n'
