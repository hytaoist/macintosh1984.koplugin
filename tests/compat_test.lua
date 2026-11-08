-- Tests plugin-directory compatibility and legacy cleanup without KOReader.

local root = assert(arg[1], "test root")

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function command_ok(command)
    local result = os.execute(command)
    return result == true or result == 0
end

local function is_file(path)
    return command_ok("test -f " .. shell_quote(path))
end

local function is_dir(path)
    return command_ok("test -d " .. shell_quote(path))
end

local function file_exists(path)
    local file = io.open(path, "rb")
    if not file then return false end
    file:close()
    return true
end

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local fake_lfs = {}

function fake_lfs.attributes(path, attribute)
    local value
    if is_dir(path) then
        value = { mode = "directory" }
    elseif is_file(path) then
        value = { mode = "file" }
    end
    if value and attribute then return value[attribute] end
    return value
end

function fake_lfs.dir(path)
    local entries = { ".", ".." }
    local pipe = io.popen(
        "find " .. shell_quote(path) .. " -mindepth 1 -maxdepth 1 -print | sort"
    )
    if pipe then
        for entry in pipe:lines() do
            table.insert(entries, entry:match("[^/]+$"))
        end
        pipe:close()
    end
    local index = 0
    return function()
        index = index + 1
        return entries[index]
    end
end

function fake_lfs.rmdir(path)
    return command_ok("rmdir " .. shell_quote(path))
end

package.preload["libs/libkoreader-lfs"] = function() return fake_lfs end

local Compat = assert(loadfile("plugin/compat.lua"))()
local plugins = root .. "/plugins"
local new_plugin = plugins .. "/" .. Compat.NEW_DIRNAME
local legacy_plugin = plugins .. "/" .. Compat.LEGACY_DIRNAME
local theme_dir = root .. "/.mac1984-theme"
local state_file = root .. "/settings/mac1984-koreader.lua"

command_ok("mkdir -p " .. shell_quote(new_plugin))
command_ok("mkdir -p " .. shell_quote(legacy_plugin .. "/theme"))
command_ok("mkdir -p " .. shell_quote(theme_dir .. "/backup/D/icons"))
command_ok("mkdir -p " .. shell_quote(root .. "/settings"))
write(new_plugin .. "/_meta.lua", "return { version = '1.3.0' }\n")
write(new_plugin .. "/main.lua", "return {}\n")
write(legacy_plugin .. "/_meta.lua", "return { version = '1.2.6' }\n")
write(legacy_plugin .. "/main.lua", "return {}\n")
write(legacy_plugin .. "/theme/apply.lua", "return {}\n")
write(plugins .. "/._" .. Compat.LEGACY_DIRNAME, "SIDECAR\n")
write(theme_dir .. "/backup/D/icons/appbar.menu.svg", "STOCK\n")
write(state_file, "return {}\n")

local kind, path = Compat.conflict(new_plugin, { file_exists = file_exists })
assert(kind == "legacy_present", "new plugin did not detect the legacy folder")
assert(path == legacy_plugin, "legacy conflict path is wrong")

kind, path = Compat.conflict(legacy_plugin, { file_exists = file_exists })
assert(kind == "superseded", "legacy plugin did not yield to the new folder")
assert(path == new_plugin, "superseded path is wrong")

kind = Compat.conflict(legacy_plugin, {
    file_exists = file_exists,
    is_plugin_disabled = function(dirname)
        return dirname == "macintosh1984"
    end,
})
assert(kind == nil, "a disabled new plugin should not supersede the legacy copy")

local ok, removed = Compat.remove_legacy(legacy_plugin, { file_exists = file_exists })
assert(not ok, "legacy installation unexpectedly removed a folder")
assert(is_dir(legacy_plugin), "legacy folder was removed by the wrong installation")

ok, removed = Compat.remove_legacy(new_plugin, { file_exists = file_exists })
assert(ok, removed)
assert(removed == legacy_plugin, "cleanup removed the wrong folder")
assert(not is_dir(legacy_plugin), "legacy plugin folder was not removed")
assert(not is_file(plugins .. "/._" .. Compat.LEGACY_DIRNAME),
    "legacy plugin sidecar was not removed")
assert(is_dir(new_plugin), "current plugin folder was removed")
assert(is_file(theme_dir .. "/backup/D/icons/appbar.menu.svg"),
    "theme backups were removed with the legacy plugin")
assert(is_file(state_file), "plugin settings were removed with the legacy plugin")

print("compat test OK")
