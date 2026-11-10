-- Stable Macintosh 1984 loader.
--
-- Storefront can replace either the legacy mac1984-koreader.koplugin folder or
-- the current macintosh1984.koplugin folder during an OTA update. This tiny
-- user patch stays in place and always prefers the current runtime.

local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")

local PLUGIN_DIRNAMES = {
    "macintosh1984.koplugin",
    "mac1984-koreader.koplugin",
}

local function is_known_plugin(dirname)
    for _index, name in ipairs(PLUGIN_DIRNAMES) do
        if dirname == name then return true end
    end
    return false
end

local function is_file(path)
    return lfs.attributes(path, "mode") == "file"
end

local function is_dir(path)
    return lfs.attributes(path, "mode") == "directory"
end

local function remove_tree(path)
    if not is_dir(path) then
        os.remove(path)
        return
    end
    for name in lfs.dir(path) do
        if name ~= "." and name ~= ".." then
            remove_tree(path .. "/" .. name)
        end
    end
    lfs.rmdir(path)
end

-- An interrupted OTA update can leave the plugin folder missing while the
-- previous version sits next to it. Restore it so the theme and the plugin
-- menu come back on the next start.
local function recover_interrupted_update()
    local ok_storage, DataStorage = pcall(require, "datastorage")
    if not ok_storage or type(DataStorage) ~= "table" then return end
    local ok_dir, data_dir = pcall(DataStorage.getDataDir, DataStorage)
    if not ok_dir or not data_dir then return end

    local plugins_dir = data_dir .. "/plugins/"
    for _index, dirname in ipairs(PLUGIN_DIRNAMES) do
        local current = plugins_dir .. dirname
        local old = current .. ".old"
        local pending = current .. ".new"
        if is_dir(current) then
            remove_tree(old)
            remove_tree(pending)
        elseif is_dir(old) then
            remove_tree(pending)
            if os.rename(old, current) then
                logger.warn("Mac1984: restored the plugin folder after an interrupted update")
            end
        end
    end
end

local function load_from_plugin_path()
    local roots = {}
    for entry in package.path:gmatch("[^;]+") do
        local root, dirname = entry:match("^(.*)/([^/]+%.koplugin)/")
        if root and is_known_plugin(dirname) then
            roots[dirname] = roots[dirname] or {}
            table.insert(roots[dirname], root .. "/" .. dirname)
        end
    end

    for _index, dirname in ipairs(PLUGIN_DIRNAMES) do
        for _root_index, plugin_root in ipairs(roots[dirname] or {}) do
            local runtime = plugin_root .. "/theme/apply.lua"
            if is_file(runtime) then return runtime end
        end
    end
end

local function load_runtime()
    local runtime = load_from_plugin_path()
    if runtime then return runtime end

    local DataStorage = require("datastorage")
    local data_dir = DataStorage:getDataDir()
    local candidates = {
        data_dir .. "/plugins/macintosh1984.koplugin/theme/apply.lua",
        data_dir .. "/plugins/mac1984-koreader.koplugin/theme/apply.lua",
        data_dir .. "/.mac1984-theme/runtime/apply.lua",
    }
    for _index, candidate in ipairs(candidates) do
        if is_file(candidate) then return candidate end
    end
end

local ok_recover, recover_error = pcall(recover_interrupted_update)
if not ok_recover then
    logger.warn("Mac1984: could not recover an interrupted update:", recover_error)
end

local runtime = load_runtime()
if not runtime then
    logger.warn("Mac1984: theme runtime not found; install or re-enable the plugin")
    return
end

local ok, err = pcall(dofile, runtime)
if not ok then
    logger.warn("Mac1984: could not load runtime", runtime, err)
end
