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

local runtime = load_runtime()
if not runtime then
    logger.warn("Mac1984: theme runtime not found; install or re-enable the plugin")
    return
end

local ok, err = pcall(dofile, runtime)
if not ok then
    logger.warn("Mac1984: could not load runtime", runtime, err)
end
