-- Lightweight test for the plugin menus and sponsor dialog without KOReader.

local shown_widget
local copied_text
local opened_url
local restart_count = 0
local dirty_count = 0

local function extend_class(parent, options)
    options = options or {}
    options.__index = options
    return setmetatable(options, { __index = parent })
end

package.preload["ui/widget/confirmbox"] = function()
    return {}
end

package.preload["datastorage"] = function()
    return {
        getSettingsDir = function() return "/tmp" end,
        getPatchesDir = function() return "/tmp/patches" end,
    }
end

package.preload["device"] = function()
    return {
        getModel = function() return "Test Reader" end,
        canOpenLink = function() return false end,
        openLink = function(_, url) opened_url = url end,
        input = {
            setClipboardText = function(_, text) copied_text = text end,
        },
    }
end

package.preload["ui/widget/infomessage"] = function()
    local InfoMessage = {}
    function InfoMessage:new(options)
        options.is_info_message = true
        return options
    end
    return InfoMessage
end

package.preload["luasettings"] = function()
    local LuaSettings = {}
    function LuaSettings:open()
        return {
            readSetting = function() end,
            saveSetting = function() end,
            delSetting = function() end,
            flush = function() end,
        }
    end
    return LuaSettings
end

package.preload["ui/uimanager"] = function()
    return {
        show = function(_, widget) shown_widget = widget end,
        close = function() shown_widget = nil end,
        nextTick = function(_, callback) callback() end,
        scheduleIn = function(_, _, callback) callback() end,
        askForRestart = function() restart_count = restart_count + 1 end,
        setDirty = function() dirty_count = dirty_count + 1 end,
    }
end

package.preload["ui/widget/container/widgetcontainer"] = function()
    local WidgetContainer = {}
    WidgetContainer.extend = extend_class
    return WidgetContainer
end

package.preload["ffi/util"] = function()
    return {
        template = function(text, ...)
            local values = { ... }
            return (text:gsub("%%(%d+)", function(index)
                return tostring(values[tonumber(index)] or "")
            end))
        end,
    }
end

package.preload["logger"] = function()
    return {
        info = function() end,
        warn = function() end,
    }
end

package.preload["gettext"] = function()
    return function(text) return text end
end

package.preload["ui/widget/buttondialog"] = function()
    local ButtonDialog = {}
    function ButtonDialog:new(options)
        options.is_button_dialog = true
        return options
    end
    return ButtonDialog
end

package.preload["ui/widget/qrmessage"] = function()
    local QRMessage = {}
    function QRMessage:new(options)
        options.is_qr_message = true
        return options
    end
    return QRMessage
end

package.preload["ui/widget/imageviewer"] = function()
    local ImageViewer = {}
    function ImageViewer:new(options)
        options.is_image_viewer = true
        return options
    end
    return ImageViewer
end

package.preload["userpatch"] = function()
    return {
        arePatchesDisabled = function() return false end,
        execution_status = {},
    }
end

local Device = require("device")
local Mac1984 = assert(loadfile(arg[1] or "plugin/main.lua"))()
local plugin = Mac1984:extend{
    path = "plugin",
    version = "1.2.3",
    github = "hytaoist/macintosh1984.koplugin",
    sponsor_url = "https://example.com/sponsor",
    wechat_reward_path = "assets/sponsor/wechat-reward.jpg",
    deploy = {
        deployed_version = function() return "1.2.3" end,
    },
}

local function find_button(dialog, label)
    for _, row in ipairs(dialog.buttons or {}) do
        for _, button in ipairs(row) do
            if button.text == label then return button end
        end
    end
end

plugin:showAbout()
assert(shown_widget and shown_widget.is_button_dialog, "About did not open a button dialog")
assert(shown_widget.title:find("macintosh1984.koplugin", 1, true),
    "About did not show the renamed repository")
local sponsor_button = assert(
    find_button(shown_widget, "Sponsor this project"),
    "About is missing the sponsor module"
)

sponsor_button.callback()
assert(shown_widget and shown_widget.is_button_dialog, "Sponsor dialog did not open")
local wechat_button = assert(
    find_button(shown_widget, "Show WeChat reward code"),
    "WeChat reward button missing"
)
local qr_button = assert(find_button(shown_widget, "Show QR code"), "Sponsor QR button missing")
local copy_button = assert(find_button(shown_widget, "Copy link"), "Sponsor copy button missing")
assert(find_button(shown_widget, "Open sponsor page in browser") == nil,
    "Browser button should be hidden when the device cannot open links")

wechat_button.callback()
assert(shown_widget and shown_widget.is_image_viewer, "WeChat reward image did not open")
assert(shown_widget.file == plugin.wechat_reward_path,
    "WeChat reward image has the wrong path")
assert(shown_widget.fullscreen == true, "WeChat reward image should use fullscreen mode")
assert(shown_widget.with_title_bar == true, "WeChat reward image needs its close title bar")

plugin:showSponsor()
qr_button = assert(find_button(shown_widget, "Show QR code"), "Sponsor QR button missing")
copy_button = assert(find_button(shown_widget, "Copy link"), "Sponsor copy button missing")
qr_button.callback()
assert(shown_widget and shown_widget.is_qr_message, "Sponsor QR code did not open")
assert(shown_widget.text == plugin.sponsor_url, "Sponsor QR code has the wrong URL")

plugin:showSponsor()
copy_button = assert(find_button(shown_widget, "Copy link"), "Sponsor copy button missing")
copy_button.callback()
assert(copied_text == plugin.sponsor_url, "Sponsor link was not copied")
assert(shown_widget and shown_widget.is_info_message, "Copy confirmation was not shown")

Device.canOpenLink = function() return true end
plugin:showSponsor()
local browser_button = assert(
    find_button(shown_widget, "Open sponsor page in browser"),
    "Browser button is missing on capable devices"
)
browser_button.callback()
assert(opened_url == plugin.sponsor_url, "Sponsor page was not opened")

plugin.sponsor_url = nil
plugin:showSponsor()
wechat_button = assert(
    find_button(shown_widget, "Show WeChat reward code"),
    "WeChat reward button missing without a sponsor URL"
)
assert(find_button(shown_widget, "Show QR code") == nil,
    "URL QR button should be hidden without a sponsor URL")
assert(find_button(shown_widget, "Copy link") == nil,
    "Copy button should be hidden without a sponsor URL")
wechat_button.callback()
assert(shown_widget and shown_widget.is_image_viewer,
    "Image-only sponsor configuration did not open the WeChat reward code")

local reader_settings = {}
G_reader_settings = {
    isFalse = function(_, name) return reader_settings[name] == false end,
    readSetting = function(_, name) return reader_settings[name] end,
    saveSetting = function(_, name, value) reader_settings[name] = value end,
    flush = function() end,
}

assert(plugin:setLegacyPluginDisabled(true), "legacy plugin was not disabled")
assert(reader_settings.plugins_disabled.mac1984_koreader == nil)
assert(reader_settings.plugins_disabled["mac1984-koreader"] == true,
    "legacy plugin disable key is wrong")
assert(plugin:setLegacyPluginDisabled(true) == false,
    "unchanged legacy plugin state should not be rewritten")
assert(plugin:setLegacyPluginDisabled(false), "legacy plugin was not re-enabled")
assert(reader_settings.plugins_disabled["mac1984-koreader"] == nil,
    "legacy plugin disable key was not removed")

local function new_state(initial)
    local values = initial or {}
    return {
        readSetting = function(_, name) return values[name] end,
        saveSetting = function(_, name, value) values[name] = value end,
        delSetting = function(_, name) values[name] = nil end,
        flush = function() end,
    }, values
end

local function new_startup_plugin(path, state, deployed_before, current)
    local stats = { deploy = 0, sync = 0 }
    local plugin = Mac1984:extend{
        path = path,
        version = "1.2.5",
        state = state,
        deploy = {
            is_deployed = function() return deployed_before end,
            is_current = function() return current ~= false end,
            deploy = function()
                stats.deploy = stats.deploy + 1
                return {}
            end,
            sync_simpleui = function()
                stats.sync = stats.sync + 1
                return true
            end,
            deployed_version = function() return "1.2.5" end,
        },
    }
    return plugin, stats
end

-- Reproduce the KPW6 report: payload and patch are already deployed, the
-- patch did not run, and the menu therefore used to remain unthemed forever.
_G._mac1984_theme_loaded = nil
_G._mac1984_theme_error = nil
restart_count = 0
local deployed_state, deployed_values = new_state()
local deployed_plugin, deployed_stats = new_startup_plugin(
    "tests/fixtures/fallback-plugin",
    deployed_state,
    true
)
deployed_plugin:initializeTheme()
assert(_G._mac1984_fallback_test_loaded,
    "plugin fallback did not load when the startup patch was skipped")
assert(deployed_values.deployed_version == "1.2.5",
    "fallback startup did not record the deployed version")
assert(restart_count == 0,
    "an already-deployed fallback startup should not repeatedly ask for a restart")
assert(deployed_stats.deploy == 0,
    "an up-to-date deployment should skip the full asset copy")
assert(deployed_stats.sync == 1,
    "an up-to-date deployment should still refresh SimpleUI settings")

-- A fresh installation still needs one full restart so files copied after
-- startup are picked up.
_G._mac1984_theme_loaded = nil
_G._mac1984_fallback_test_loaded = nil
restart_count = 0
local fresh_state = new_state()
local fresh_plugin, fresh_stats = new_startup_plugin(
    "tests/fixtures/fallback-plugin",
    fresh_state,
    false
)
fresh_plugin:initializeTheme()
assert(_G._mac1984_fallback_test_loaded, "fresh-install fallback did not run")
assert(restart_count == 1, "fresh installation did not request the required restart")
assert(fresh_stats.deploy == 1, "fresh installation did not run a full deployment")

-- A missing deployed file must fall back to a full deployment without asking
-- for another restart.
_G._mac1984_theme_loaded = nil
_G._mac1984_fallback_test_loaded = nil
restart_count = 0
local repair_state = new_state()
local repair_plugin, repair_stats = new_startup_plugin(
    "tests/fixtures/fallback-plugin",
    repair_state,
    true,
    false
)
repair_plugin:initializeTheme()
assert(repair_stats.deploy == 1, "an incomplete deployment was not repaired")
assert(restart_count == 0, "repairing an existing install should not force a restart")

-- Disabling the theme must not load a runtime.
_G._mac1984_theme_loaded = nil
_G._mac1984_fallback_test_loaded = nil
local disabled_state = new_state({ disabled = true })
local disabled_plugin = new_startup_plugin(
    "tests/fixtures/fallback-plugin",
    disabled_state,
    true
)
disabled_plugin:initializeTheme()
assert(_G._mac1984_fallback_test_loaded == nil,
    "disabled theme unexpectedly loaded its runtime")

-- Runtime failures should be stored and visible in diagnostics.
_G._mac1984_theme_loaded = nil
_G._mac1984_theme_error = nil
local broken_state, broken_values = new_state()
local broken_plugin = new_startup_plugin(
    "tests/fixtures/missing-runtime",
    broken_state,
    true
)
broken_plugin:initializeTheme()
assert(type(broken_values.last_theme_error) == "string",
    "runtime load failures were not persisted")
broken_plugin:showDiagnostics()
assert(shown_widget and shown_widget.is_info_message,
    "diagnostics did not open an info message")
assert(shown_widget.text:find("Theme runtime: not loaded", 1, true),
    "diagnostics did not report the runtime state")
assert(shown_widget.text:find("Last error:", 1, true),
    "diagnostics did not include the last error")

-- Theme settings are exposed in the menu and persist immediately.
plugin.state = new_state()
local menu_items = plugin:getSubMenu()
local function find_menu_item(label)
    for _, item in ipairs(menu_items) do
        if item.text == label then return item end
        for _, child in ipairs(item.sub_item_table or {}) do
            if child.text == label then return child end
        end
    end
end

plugin.conflict_kind = "legacy_present"
plugin.conflict_path = "/tmp/plugins/mac1984-koreader.koplugin"
menu_items = plugin:getSubMenu()
assert(find_menu_item("Remove old plugin folder"),
    "duplicate legacy plugin cleanup is missing from the menu")
plugin.conflict_kind = nil
plugin.conflict_path = nil

local pinstripes = assert(
    find_menu_item("Pinstripe title bars"),
    "pinstripe setting is missing from the menu"
)
assert(pinstripes.checked_func() == true, "pinstripes should default to enabled")
local dirty_before = dirty_count
pinstripes.callback()
assert(reader_settings.mac1984_pinstripes == false, "pinstripe setting was not saved")
assert(pinstripes.checked_func() == false, "pinstripe checkbox did not update")
assert(dirty_count > dirty_before, "live setting did not request a refresh")

local shadows = assert(find_menu_item("Window shadows"), "shadow setting is missing")
shadows.callback()
assert(reader_settings.mac1984_shadows == false, "shadow setting was not saved")

local ui_font = assert(find_menu_item("Use ChicagoFLF UI font"), "font setting is missing")
local restart_before_font = restart_count
ui_font.callback()
assert(reader_settings.mac1984_ui_font == false, "UI font setting was not saved")
assert(restart_count == restart_before_font + 1, "font change did not request a restart")

local safe_mode = assert(find_menu_item("Safe mode (skip UI patches)"), "safe mode is missing")
assert(safe_mode.checked_func() == false, "safe mode should default to disabled")
local restart_before_safe = restart_count
safe_mode.callback()
assert(reader_settings.mac1984_safe_mode == true, "safe mode setting was not saved")
assert(restart_count == restart_before_safe + 1, "safe mode did not request a restart")

print("main test OK")
