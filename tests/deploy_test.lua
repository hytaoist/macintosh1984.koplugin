-- Tests the Storefront payload deployment against a fake KOReader data tree.
-- A small POSIX-backed lfs shim keeps the test independent of LuaFileSystem.

local plugin_dir = assert(arg[1], "plugin directory")
local data_dir = assert(arg[2], "fake KOReader data directory")
local settings_dir = assert(arg[3], "fake KOReader settings directory")

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function command_ok(command)
    local first = os.execute(command)
    return first == true or first == 0
end

local function is_file(path)
    return command_ok("test -f " .. shell_quote(path))
end

local function is_dir(path)
    return command_ok("test -d " .. shell_quote(path))
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

function fake_lfs.mkdir(path)
    return command_ok("mkdir " .. shell_quote(path))
end

function fake_lfs.rmdir(path)
    return command_ok("rmdir " .. shell_quote(path))
end

package.preload["libs/libkoreader-lfs"] = function() return fake_lfs end
package.preload["util"] = function()
    return {
        makePath = function(path)
            return command_ok("mkdir -p " .. shell_quote(path))
        end,
    }
end
package.preload["ffi/util"] = function() return {} end

local Deploy = assert(loadfile("plugin/deploy.lua"))()
local options = { data_dir = data_dir, settings_dir = settings_dir }

local function read(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local function write(path, data)
    local file = assert(io.open(path, "wb"))
    file:write(data)
    file:close()
end

local icon_path = data_dir .. "/icons/appbar.menu.svg"
local font_path = data_dir .. "/fonts/Mac1984Chicago.ttf"
local runtime_path = data_dir .. "/.mac1984-theme/runtime/apply.lua"
local settings_path = settings_dir .. "/simpleui/sui_settings.lua"
local pack_path = settings_dir
    .. "/simpleui/sui_icons/packs/Macintosh 1984/pack.lua"

assert(not Deploy.is_deployed("1.2.0", options), "empty tree should not be deployed")
assert(is_file(plugin_dir .. "/loader.lua"), "test fixture loader is missing")

local report, err = Deploy.deploy(plugin_dir, "1.2.0", options)
assert(report, err)
assert(Deploy.is_deployed("1.2.0", options), "fresh deployment was not detected")
assert(report.copied > 100, "expected all theme assets to be copied")
assert(is_file(icon_path), "KOReader icon was not deployed")
assert(is_file(font_path), "font was not deployed")
assert(is_file(runtime_path), "runtime was not deployed")
assert(is_file(pack_path), "SimpleUI pack was not deployed")
assert(read(settings_path):find("Macintosh 1984/", 1, true), "SimpleUI pack was not selected")
assert(read(settings_path):find('"ChicagoFLF"', 1, true), "SimpleUI font was not selected")
assert(is_file(data_dir .. "/.mac1984-theme/backup/D/icons/appbar.menu.svg"),
    "stock icon was not backed up")
assert(is_file(data_dir .. "/.mac1984-theme/backup/S/simpleui/sui_settings.lua"),
    "SimpleUI settings were not backed up")
assert(Deploy.installed_count(options) > 100,
    "installed file count did not include the theme payload")
assert(Deploy.is_current("1.2.0", options), "complete deployment was not current")
assert(not Deploy.is_current("9.9.9", options),
    "a different version should not be current")

-- The startup fast path still refreshes the SimpleUI selection without
-- copying the icon set again.
write(settings_path, [[return {
    ["simpleui_ui_font_name"] = "OpenDyslexic",
    ["simpleui_sysicon_menu"] = "./settings/simpleui/sui_icons/packs/Solar Mono/menu.svg",
}
]])
assert(Deploy.sync_simpleui(options), "SimpleUI settings sync failed")
assert(read(settings_path):find("Macintosh 1984/", 1, true),
    "SimpleUI pack was not refreshed on the fast path")
assert(read(settings_path):find('"ChicagoFLF"', 1, true),
    "SimpleUI font was not refreshed on the fast path")

assert(Deploy.set_ui_font(false, options), "could not disable the SimpleUI font")
assert(read(settings_path):find('"OpenDyslexic"', 1, true),
    "the original SimpleUI font was not restored")
assert(read(settings_path):find("Macintosh 1984/", 1, true),
    "disabling the UI font also changed the icon pack")
assert(Deploy.set_ui_font(true, options), "could not re-enable the SimpleUI font")
assert(read(settings_path):find('"ChicagoFLF"', 1, true),
    "the SimpleUI font was not re-applied")

-- Deleting any tracked file must make the next startup repair the payload.
command_ok("rm -f " .. shell_quote(icon_path))
assert(not Deploy.is_current("1.2.0", options),
    "a missing deployed file was still reported as current")
report, err = Deploy.deploy(plugin_dir, "1.2.0", options)
assert(report, err)
assert(is_file(icon_path), "missing deployed file was not repaired")

local first_theme_icon = read(icon_path)
write(plugin_dir .. "/assets/icons/appbar.menu.svg", "THEME V2\n")
report, err = Deploy.deploy(plugin_dir, "1.3.0", options)
assert(report, err)
assert(Deploy.deployed_version(options) == "1.3.0", "version marker did not advance")
assert(read(icon_path) == "THEME V2\n", "OTA asset was not refreshed")
assert(read(data_dir .. "/.mac1984-theme/backup/D/icons/appbar.menu.svg") == "STOCK\n",
    "OTA update replaced the original backup")
assert(first_theme_icon ~= "STOCK\n", "test fixture did not start with the theme icon")

local restored = Deploy.uninstall(options)
assert(restored > 100, "uninstall did not restore/remove the expected files")
assert(read(icon_path) == "STOCK\n", "stock icon was not restored")
assert(read(settings_path):find("Solar Mono/", 1, true), "SimpleUI pack was not restored")
assert(read(settings_path):find('"OpenDyslexic"', 1, true), "SimpleUI font was not restored")
assert(not is_file(plugin_dir .. "/assets/icons/appbar.menu.svg.mac1984.tmp"),
    "temporary file was left")
assert(not is_dir(data_dir .. "/.mac1984-theme"), "theme data directory was not removed")

-- Upgrade a v1.1 standalone manifest, whose records have no D/S prefix and
-- whose backups live directly under backup/<KOReader-relative-path>.
command_ok("mkdir -p " .. shell_quote(data_dir .. "/.mac1984-theme/backup/icons"))
command_ok("mkdir -p " .. shell_quote(
    data_dir .. "/.mac1984-theme/backup/settings/simpleui"
))
write(
    data_dir .. "/.mac1984-theme/installed.tsv",
    "icons/appbar.menu.svg\nsettings/simpleui/sui_settings.lua\n"
)
write(data_dir .. "/.mac1984-theme/backup/icons/appbar.menu.svg", "STOCK\n")
write(
    data_dir .. "/.mac1984-theme/backup/settings/simpleui/sui_settings.lua",
    [[return {
    ["simpleui_ui_font_name"] = "OpenDyslexic",
    ["simpleui_sysicon_menu"] = "./settings/simpleui/sui_icons/packs/Solar Mono/menu.svg",
}
]]
)
write(icon_path, "LEGACY THEME\n")
write(settings_path, [[return {
    ["simpleui_ui_font_name"] = "ChicagoFLF",
    ["simpleui_sysicon_menu"] = "./settings/simpleui/sui_icons/packs/Macintosh 1984/menu.svg",
}
]])

report, err = Deploy.deploy(plugin_dir, "1.2.0", options)
assert(report, err)
assert(read(data_dir .. "/.mac1984-theme/backup/D/icons/appbar.menu.svg") == "STOCK\n",
    "legacy icon backup was not migrated")
Deploy.uninstall(options)
assert(read(icon_path) == "STOCK\n", "legacy icon backup was not restored")
assert(read(settings_path):find("Solar Mono/", 1, true),
    "legacy SimpleUI settings were not restored")

print("deployment test OK")
