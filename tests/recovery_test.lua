-- Tests the startup recovery of an interrupted OTA update.
--
-- The update swaps the plugin folder by renaming it. A crash between the two
-- renames leaves the previous version next to a missing plugin folder, so the
-- stable user patch has to restore it.

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

package.preload["logger"] = function()
    return {
        info = function() end,
        warn = function() end,
    }
end

package.preload["libs/libkoreader-lfs"] = function()
    return fake_lfs
end

local data_dir = root .. "/data"
package.preload["datastorage"] = function()
    return {
        getDataDir = function() return data_dir end,
    }
end

local plugins_dir = data_dir .. "/plugins"
local plugin_dir = plugins_dir .. "/macintosh1984.koplugin"
local old_dir = plugin_dir .. ".old"
local new_dir = plugin_dir .. ".new"

-- An interrupted update: the plugin folder is gone, the previous version and
-- the freshly extracted copy are still next to it.
command_ok("mkdir -p " .. shell_quote(old_dir))
command_ok("mkdir -p " .. shell_quote(new_dir))
write(old_dir .. "/_meta.lua", "return { version = '1.3.0' }\n")
write(new_dir .. "/_meta.lua", "return { version = '1.3.1' }\n")

dofile("patches/2-mac1984.lua")

assert(is_dir(plugin_dir), "the plugin folder was not restored")
assert(is_file(plugin_dir .. "/_meta.lua"), "the restored plugin folder is empty")
assert(not is_dir(old_dir), "the previous plugin copy was not removed")
assert(not is_dir(new_dir), "the pending plugin copy was not removed")

-- A completed installation only needs the leftovers cleaned up.
command_ok("mkdir -p " .. shell_quote(old_dir))
command_ok("mkdir -p " .. shell_quote(new_dir))
write(plugin_dir .. "/_meta.lua", "return { version = '1.3.1' }\n")

dofile("patches/2-mac1984.lua")

assert(is_dir(plugin_dir), "the installed plugin folder was removed")
assert(not is_dir(old_dir), "the previous plugin copy survived a completed install")
assert(not is_dir(new_dir), "the pending plugin copy survived a completed install")

print("recovery test OK")
