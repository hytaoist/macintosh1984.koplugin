-- Compatibility helpers for the mac1984-koreader -> macintosh1984 rename.
--
-- The plugin directory name is the stable identity used by KOReader and
-- Storefront. Keep the legacy directory readable while new installs use the
-- macintosh1984.koplugin name.

local M = {}

M.NEW_DIRNAME = "macintosh1984.koplugin"
M.LEGACY_DIRNAME = "mac1984-koreader.koplugin"

local function path_join(parent, child)
    if not child or child == "" then return parent end
    if parent:sub(-1) == "/" then return parent .. child end
    return parent .. "/" .. child
end

function M.dirname(path)
    return tostring(path or ""):match("([^/]+)$")
end

function M.parent(path)
    return tostring(path or ""):match("^(.*)/[^/]+$")
end

function M.is_new(path)
    return M.dirname(path) == M.NEW_DIRNAME
end

function M.is_legacy(path)
    return M.dirname(path) == M.LEGACY_DIRNAME
end

function M.legacy_sibling(path)
    local parent = M.parent(path)
    if not parent then return nil end
    return path_join(parent, M.LEGACY_DIRNAME)
end

function M.new_sibling(path)
    local parent = M.parent(path)
    if not parent then return nil end
    return path_join(parent, M.NEW_DIRNAME)
end

local function default_file_exists(path)
    local file = io.open(path, "rb")
    if not file then return false end
    file:close()
    return true
end

local function is_complete_plugin(path, file_exists)
    return file_exists(path_join(path, "_meta.lua"))
        and file_exists(path_join(path, "main.lua"))
end

-- Returns one of:
--   "superseded", new_path    -- this legacy copy must stay dormant
--   "legacy_present", path    -- this new copy should offer cleanup
--   nil
function M.conflict(plugin_path, options)
    options = options or {}
    local file_exists = options.file_exists or default_file_exists
    local is_plugin_disabled = options.is_plugin_disabled or function() return false end

    if M.is_legacy(plugin_path) then
        local new_path = M.new_sibling(plugin_path)
        if new_path
            and not is_plugin_disabled(M.NEW_DIRNAME:gsub("%.koplugin$", ""))
            and is_complete_plugin(new_path, file_exists) then
            return "superseded", new_path
        end
    elseif M.is_new(plugin_path) then
        local legacy_path = M.legacy_sibling(plugin_path)
        if legacy_path and is_complete_plugin(legacy_path, file_exists) then
            return "legacy_present", legacy_path
        end
    end
    return nil
end

local function lfs_module()
    local ok, module = pcall(require, "libs/libkoreader-lfs")
    if ok and module then return module end
    ok, module = pcall(require, "lfs")
    if ok then return module end
    error("Mac1984 compat: lfs is unavailable")
end

local function remove_tree(path, lfs)
    local mode = lfs.attributes(path, "mode")
    if not mode then return true end
    if mode ~= "directory" then
        return os.remove(path) ~= nil
    end

    local ok = true
    for name in lfs.dir(path) do
        if name ~= "." and name ~= ".." then
            if not remove_tree(path_join(path, name), lfs) then
                ok = false
            end
        end
    end
    if ok then
        return lfs.rmdir(path) ~= nil
    end
    return false
end

local function remove_sidecar(path)
    local parent = M.parent(path)
    local basename = M.dirname(path)
    if parent and basename then
        os.remove(path_join(parent, "._" .. basename))
    end
end

-- Deletes only the legacy sibling of a new installation. Callers must confirm
-- with the user first. Theme backups live outside the plugin directory and are
-- deliberately left untouched.
function M.remove_legacy(plugin_path, options)
    options = options or {}
    if not M.is_new(plugin_path) then
        return false, "Only a macintosh1984.koplugin installation can remove the legacy folder"
    end

    local legacy_path = M.legacy_sibling(plugin_path)
    local file_exists = options.file_exists or default_file_exists
    if not legacy_path or not is_complete_plugin(legacy_path, file_exists) then
        return false, "Legacy plugin folder was not found"
    end

    local ok, lfs = pcall(lfs_module)
    if not ok then
        return false, lfs
    end
    local ok_call, removed = pcall(remove_tree, legacy_path, lfs)
    if not ok_call then
        return false, tostring(removed)
    end
    if not removed then
        return false, "Could not remove " .. legacy_path
    end
    remove_sidecar(legacy_path)
    return true, legacy_path
end

return M
