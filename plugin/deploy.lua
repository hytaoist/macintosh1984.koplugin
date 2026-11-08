-- Installs the theme payload outside the plugin directory.
--
-- Storefront replaces plugin directories atomically during OTA updates. Theme
-- assets therefore live in stable KOReader locations and are refreshed from
-- the currently loaded plugin version on startup.

local M = {}

local THEME_DIR = ".mac1984-theme"
local VERSION_FILE = THEME_DIR .. "/version"
local MANIFEST_FILE = THEME_DIR .. "/installed.tsv"
local BACKUP_DIR = THEME_DIR .. "/backup"
local LOADER_REL = "patches/2-mac1984.lua"
local RUNTIME_REL = THEME_DIR .. "/runtime/apply.lua"
local FONT_REL = "fonts/Mac1984Chicago.ttf"
local SIMPLEUI_PACK = "Macintosh 1984"
local SIMPLEUI_PACK_REL = "simpleui/sui_icons/packs/" .. SIMPLEUI_PACK
local SIMPLEUI_SETTINGS_REL = "simpleui/sui_settings.lua"

local function ui_font_enabled()
    if G_reader_settings and type(G_reader_settings.isFalse) == "function" then
        local ok, disabled = pcall(G_reader_settings.isFalse, G_reader_settings, "mac1984_ui_font")
        if ok then return not disabled end
    end
    return true
end

local function lfs_module()
    local ok, module = pcall(require, "libs/libkoreader-lfs")
    if ok and module then return module end
    ok, module = pcall(require, "lfs")
    if ok then return module end
    error("Mac1984 deploy: lfs is unavailable")
end

local function util_modules()
    local ok_util, util = pcall(require, "util")
    local ok_ffi, ffiutil = pcall(require, "ffi/util")
    return ok_util and util or nil, ok_ffi and ffiutil or nil
end

local function path_join(parent, child)
    if not child or child == "" then return parent end
    if parent:sub(-1) == "/" then return parent .. child end
    return parent .. "/" .. child
end

local function parent_dir(path)
    return path:match("^(.*)/[^/]+$") or "."
end

local function file_exists(path)
    return lfs_module().attributes(path, "mode") == "file"
end

local function dir_exists(path)
    return lfs_module().attributes(path, "mode") == "directory"
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local data = file:read("*a")
    file:close()
    return data
end

local function write_file(path, data)
    local tmp = path .. ".mac1984.tmp"
    local file = io.open(tmp, "wb")
    if not file then return false end
    local ok = file:write(data)
    file:close()
    if not ok then
        os.remove(tmp)
        return false
    end
    os.remove(path)
    if not os.rename(tmp, path) then
        os.remove(tmp)
        return false
    end
    return true
end

local function make_path(path)
    local _util = util_modules()
    if _util and type(_util.makePath) == "function" then
        _util.makePath(path)
        return true
    end

    local lfs = lfs_module()
    local current = path:sub(1, 1) == "/" and "" or "."
    for part in path:gmatch("[^/]+") do
        current = current .. "/" .. part
        local mode = lfs.attributes(current, "mode")
        if mode ~= "directory" then
            if mode or not lfs.mkdir(current) then return false end
        end
    end
    return true
end

local function remove_sidecar(path)
    local sidecar = path_join(parent_dir(path), "._" .. path:match("[^/]+$"))
    if file_exists(sidecar) then os.remove(sidecar) end
end

local function copy_file(source, destination)
    if not file_exists(source) then return false end
    if not make_path(parent_dir(destination)) then return false end

    local _, ffiutil = util_modules()
    if ffiutil and type(ffiutil.copyFile) == "function" then
        local err = ffiutil.copyFile(source, destination)
        if not err then
            remove_sidecar(destination)
            return true
        end
    end

    local data = read_file(source)
    if not data then return false end
    local ok = write_file(destination, data)
    if ok then remove_sidecar(destination) end
    return ok
end

local function remove_file(path)
    if file_exists(path) then
        os.remove(path)
        remove_sidecar(path)
    end
end

local function remove_tree(path)
    if not dir_exists(path) then
        remove_file(path)
        return
    end
    local lfs = lfs_module()
    for name in lfs.dir(path) do
        if name ~= "." and name ~= ".." then
            local child = path_join(path, name)
            if dir_exists(child) then
                remove_tree(child)
            else
                remove_file(child)
            end
        end
    end
    lfs.rmdir(path)
end

local function sorted_files(root, relative, output)
    relative = relative or ""
    output = output or {}
    local dir = relative == "" and root or path_join(root, relative)
    if not dir_exists(dir) then return output end

    local entries = {}
    for name in lfs_module().dir(dir) do
        if name ~= "." and name ~= ".." and name ~= ".DS_Store" then
            table.insert(entries, name)
        end
    end
    table.sort(entries)

    for _index, name in ipairs(entries) do
        local child_rel = relative == "" and name or (relative .. "/" .. name)
        local child_path = path_join(root, child_rel)
        local mode = lfs_module().attributes(child_path, "mode")
        if mode == "directory" then
            sorted_files(root, child_rel, output)
        elseif mode == "file" and name:sub(1, 2) ~= "._" then
            table.insert(output, child_rel)
        end
    end
    return output
end

local function data_root(options)
    if options.data_dir then return options.data_dir end
    return require("datastorage"):getDataDir()
end

local function settings_root(options)
    if options.settings_dir then return options.settings_dir end
    return require("datastorage"):getSettingsDir()
end

local function roots(options)
    return {
        D = data_root(options),
        S = settings_root(options),
    }
end

local function record_id(record)
    return record.tag .. ":" .. record.rel
end

local function read_manifest(path)
    local records = {}
    local seen = {}
    local text = read_file(path)
    if not text then return records end
    for line in text:gmatch("[^\r\n]+") do
        if line ~= "" then
            local tag, rel = line:match("^([DS])\t(.+)$")
            local legacy_rel
            if not tag then
                legacy_rel = line
                if line:sub(1, #"settings/simpleui/") == "settings/simpleui/" then
                    tag = "S"
                    rel = line:sub(#"settings/" + 1)
                else
                    tag = "D"
                    rel = line
                end
            end
            local id = tag .. ":" .. rel
            if not seen[id] then
                table.insert(records, { tag = tag, rel = rel, legacy_rel = legacy_rel })
                seen[id] = true
            end
        end
    end
    return records
end

local function write_manifest(path, records)
    local lines = {}
    for _index, record in ipairs(records) do
        table.insert(lines, record.tag .. "\t" .. record.rel)
    end
    return write_file(path, table.concat(lines, "\n") .. (#lines > 0 and "\n" or ""))
end

local function backup_path(theme_dir, record)
    return path_join(theme_dir, "backup/" .. record.tag .. "/" .. record.rel)
end

local function migrate_legacy_backups(theme_dir, records)
    for _index, record in ipairs(records) do
        if record.legacy_rel then
            local old_backup = path_join(theme_dir, "backup/" .. record.legacy_rel)
            local new_backup = backup_path(theme_dir, record)
            if file_exists(old_backup) and not file_exists(new_backup) then
                if not make_path(parent_dir(new_backup)) then return false end
                if not os.rename(old_backup, new_backup) and not copy_file(old_backup, new_backup) then
                    return false
                end
            end
            record.legacy_rel = nil
        end
    end
    return true
end

local function backup_if_needed(destination, theme_dir, record, old_ids)
    local id = record_id(record)
    if old_ids[id] or not file_exists(destination) then return true end
    return copy_file(destination, backup_path(theme_dir, record))
end

local function restore_record(destination, theme_dir, record)
    local backup = backup_path(theme_dir, record)
    if file_exists(backup) then
        local ok = copy_file(backup, destination)
        if ok then remove_file(backup) end
        return ok
    end
    remove_file(destination)
    return true
end

local function collect_desired(plugin_dir, options)
    local desired = {}
    local function add(tag, rel, source)
        table.insert(desired, { tag = tag, rel = rel, source = source })
    end

    add("D", LOADER_REL, path_join(plugin_dir, "loader.lua"))
    add("D", RUNTIME_REL, path_join(plugin_dir, "theme/apply.lua"))
    add("D", FONT_REL, path_join(plugin_dir, "assets/fonts/ChicagoFLF.ttf"))

    for _index, rel in ipairs(sorted_files(path_join(plugin_dir, "assets/icons"))) do
        add("D", "icons/" .. rel,
            path_join(path_join(plugin_dir, "assets/icons"), rel))
    end

    for _index, rel in ipairs(sorted_files(path_join(plugin_dir, "assets/simpleui-icons"))) do
        add("S", SIMPLEUI_PACK_REL .. "/" .. rel,
            path_join(path_join(plugin_dir, "assets/simpleui-icons"), rel))
    end

    if file_exists(path_join(settings_root(options), SIMPLEUI_SETTINGS_REL)) then
        add("S", SIMPLEUI_SETTINGS_REL)
    end
    return desired
end

local function apply_simpleui_settings(settings_path, theme_dir, already_tracked, with_font)
    if not file_exists(settings_path) then return true end

    local record = { tag = "S", rel = SIMPLEUI_SETTINGS_REL }
    if not already_tracked then
        local old_ids = {}
        if not backup_if_needed(settings_path, theme_dir, record, old_ids) then return false end
    end

    local text = read_file(settings_path)
    if not text then return false end
    local original_text = text
    text = text:gsub("(sui_icons/packs/)[^/\"]+/", "%1" .. SIMPLEUI_PACK .. "/")
    if with_font ~= false then
        text = text:gsub("(%[\"simpleui_ui_font_name\"%]%s*=%s*\")[^\"]*(\")",
            "%1ChicagoFLF%2")
    end
    if text == original_text then return true end
    return write_file(settings_path, text)
end

local function restore_simpleui_settings(settings_path, backup)
    if not file_exists(settings_path) or not file_exists(backup) then return false end
    local original = read_file(backup)
    local current = read_file(settings_path)
    if not original or not current then return false end

    local original_pack = original:match("sui_icons/packs/([^/\"]+)/")
    local original_font = original:match(
        "%[\"simpleui_ui_font_name\"%]%s*=%s*\"([^\"]*)\""
    )
    if original_pack then
        current = current:gsub("(sui_icons/packs/)[^/\"]+/",
            "%1" .. original_pack:gsub("%%", "%%%%") .. "/")
    end
    if original_font then
        current = current:gsub("(%[\"simpleui_ui_font_name\"%]%s*=%s*\")[^\"]*(\")",
            "%1" .. original_font:gsub("%%", "%%%%") .. "%2")
    end
    return write_file(settings_path, current)
end

local function restore_simpleui_font(settings_path, backup)
    if not file_exists(settings_path) or not file_exists(backup) then return false end
    local original = read_file(backup)
    local current = read_file(settings_path)
    if not original or not current then return false end

    local original_font = original:match(
        "%[\"simpleui_ui_font_name\"%]%s*=%s*\"([^\"]*)\""
    )
    if not original_font then return false end
    local original_text = current
    current = current:gsub("(%[\"simpleui_ui_font_name\"%]%s*=%s*\")[^\"]*(\")",
        "%1" .. original_font:gsub("%%", "%%%%") .. "%2")
    if current == original_text then return true end
    return write_file(settings_path, current)
end

local function restore_old_record(theme_dir, all_roots, record)
    local root = all_roots[record.tag]
    if not root then return true end
    local destination = path_join(root, record.rel)
    if record.tag == "S" and record.rel == SIMPLEUI_SETTINGS_REL then
        local backup = backup_path(theme_dir, record)
        if file_exists(backup) and restore_simpleui_settings(destination, backup) then
            remove_file(backup)
            return true
        end
    end
    return restore_record(destination, theme_dir, record)
end

local function apply_simpleui_pack_api(pack_dir)
    local ok, SimpleUIStyle = pcall(require, "features/sui_style")
    if not ok or type(SimpleUIStyle) ~= "table"
        or type(SimpleUIStyle.applyPack) ~= "function" then
        return false
    end
    local ok_apply, applied = pcall(SimpleUIStyle.applyPack, pack_dir)
    return ok_apply and type(applied) == "table"
end

function M.is_deployed(version, options)
    options = options or {}
    local data = data_root(options)
    if (read_file(path_join(data, VERSION_FILE)) or ""):gsub("%s+$", "") ~= version then
        return false
    end
    return file_exists(path_join(data, LOADER_REL))
        and file_exists(path_join(data, RUNTIME_REL))
        and file_exists(path_join(data, FONT_REL))
end

function M.deployed_version(options)
    options = options or {}
    local version = read_file(path_join(data_root(options), VERSION_FILE))
    return version and version:gsub("%s+$", "") or nil
end

function M.installed_count(options)
    options = options or {}
    local records = read_manifest(path_join(data_root(options), MANIFEST_FILE))
    return #records
end

function M.is_current(version, options)
    options = options or {}
    if not M.is_deployed(version, options) then return false end

    local all_roots = roots(options)
    local records = read_manifest(path_join(all_roots.D, MANIFEST_FILE))
    if #records == 0 then return false end

    local has_simpleui_settings = false
    for _index, record in ipairs(records) do
        local root = all_roots[record.tag]
        if not root or not file_exists(path_join(root, record.rel)) then
            return false
        end
        if record.tag == "S" and record.rel == SIMPLEUI_SETTINGS_REL then
            has_simpleui_settings = true
        end
    end

    -- SimpleUI may have been installed after the theme. In that case the
    -- settings file still needs its first backup and pack selection.
    if file_exists(path_join(all_roots.S, SIMPLEUI_SETTINGS_REL))
        and not has_simpleui_settings then
        return false
    end
    return true
end

function M.sync_simpleui(options)
    options = options or {}
    local all_roots = roots(options)
    local settings_path = path_join(all_roots.S, SIMPLEUI_SETTINGS_REL)
    if not file_exists(settings_path) then return true end

    local theme_dir = path_join(all_roots.D, THEME_DIR)
    local records = read_manifest(path_join(all_roots.D, MANIFEST_FILE))
    local tracked = {}
    for _index, record in ipairs(records) do
        tracked[record_id(record)] = true
    end
    local record = { tag = "S", rel = SIMPLEUI_SETTINGS_REL }
    if not tracked[record_id(record)] then return false end
    local ok_settings = apply_simpleui_settings(
        settings_path, theme_dir, true, ui_font_enabled()
    )
    if ok_settings then
        apply_simpleui_pack_api(path_join(all_roots.S, SIMPLEUI_PACK_REL))
    end
    return ok_settings
end

function M.set_ui_font(enabled, options)
    options = options or {}
    local all_roots = roots(options)
    local settings_path = path_join(all_roots.S, SIMPLEUI_SETTINGS_REL)
    if not file_exists(settings_path) then return true end

    local theme_dir = path_join(all_roots.D, THEME_DIR)
    if enabled then
        local records = read_manifest(path_join(all_roots.D, MANIFEST_FILE))
        local tracked = {}
        for _index, record in ipairs(records) do
            tracked[record_id(record)] = true
        end
        local record = { tag = "S", rel = SIMPLEUI_SETTINGS_REL }
        return apply_simpleui_settings(
            settings_path, theme_dir, tracked[record_id(record)], true
        )
    end

    local backup = backup_path(theme_dir, { tag = "S", rel = SIMPLEUI_SETTINGS_REL })
    return restore_simpleui_font(settings_path, backup)
end

function M.deploy(plugin_dir, version, options)
    options = options or {}
    local all_roots = roots(options)
    local theme_dir = path_join(all_roots.D, THEME_DIR)
    local manifest_path = path_join(all_roots.D, MANIFEST_FILE)
    local old_records = read_manifest(manifest_path)
    if not migrate_legacy_backups(theme_dir, old_records) then
        return nil, "Could not migrate backups from the standalone installer"
    end
    local old_ids = {}
    for _index, record in ipairs(old_records) do
        old_ids[record_id(record)] = true
    end

    local desired = collect_desired(plugin_dir, options)
    local desired_ids = {}
    local report = {
        copied = 0,
        simpleui_applied = false,
        settings_updated = false,
    }

    if not make_path(theme_dir) then
        return nil, "Could not create " .. theme_dir
    end

    for _index, record in ipairs(desired) do
        local root = all_roots[record.tag]
        local destination = path_join(root, record.rel)
        if not backup_if_needed(destination, theme_dir, record, old_ids) then
            return nil, "Could not back up " .. destination
        end
        if record.source then
            if not copy_file(record.source, destination) then
                return nil, "Could not install " .. record.source
            end
            report.copied = report.copied + 1
        end
        desired_ids[record_id(record)] = true
    end

    local settings_path = path_join(all_roots.S, SIMPLEUI_SETTINGS_REL)
    if file_exists(settings_path) then
        local settings_record = { tag = "S", rel = SIMPLEUI_SETTINGS_REL }
        if not apply_simpleui_settings(
            settings_path,
            theme_dir,
            old_ids[record_id(settings_record)],
            ui_font_enabled()
        ) then
            return nil, "Could not update " .. settings_path
        end
        if not desired_ids[record_id(settings_record)] then
            table.insert(desired, settings_record)
            desired_ids[record_id(settings_record)] = true
        end
        report.settings_updated = true
    end

    local pack_dir = path_join(all_roots.S, SIMPLEUI_PACK_REL)
    report.simpleui_applied = apply_simpleui_pack_api(pack_dir)
    if report.simpleui_applied and file_exists(settings_path) then
        local settings_record = { tag = "S", rel = SIMPLEUI_SETTINGS_REL }
        if not desired_ids[record_id(settings_record)] then
            table.insert(desired, settings_record)
            desired_ids[record_id(settings_record)] = true
        end
    end

    for _index, record in ipairs(old_records) do
        if not desired_ids[record_id(record)] then
            if not restore_old_record(theme_dir, all_roots, record) then
                return nil, "Could not remove stale file " .. record.rel
            end
        end
    end

    if not write_manifest(manifest_path, desired) then
        return nil, "Could not write " .. manifest_path
    end
    if not write_file(path_join(all_roots.D, VERSION_FILE), version .. "\n") then
        return nil, "Could not write the theme version marker"
    end

    return report
end

function M.uninstall(options)
    options = options or {}
    local all_roots = roots(options)
    local theme_dir = path_join(all_roots.D, THEME_DIR)
    local records = read_manifest(path_join(all_roots.D, MANIFEST_FILE))
    if not migrate_legacy_backups(theme_dir, records) then
        return nil, "Could not migrate backups from the standalone installer"
    end
    local restored = 0

    for index = #records, 1, -1 do
        local record = records[index]
        if restore_old_record(theme_dir, all_roots, record) then
            restored = restored + 1
        end
    end
    remove_file(path_join(all_roots.D, MANIFEST_FILE))
    remove_file(path_join(all_roots.D, VERSION_FILE))
    remove_tree(theme_dir)
    return restored
end

return M
