-- Tests runtime options that intentionally skip some or all widget patches.
-- Run once per mode so each scenario starts with an unpatched Lua state.

local mode = assert(
    os.getenv("MAC1984_TEST_MODE"),
    "MAC1984_TEST_MODE must be safe or no_font"
)

local settings = {}
if mode == "safe" then
    settings.mac1984_safe_mode = true
elseif mode == "no_font" then
    settings.mac1984_ui_font = false
else
    error("unknown test mode: " .. mode)
end

local plugin_patches = {}
local simpleui_style_loaded = false

package.preload["logger"] = function()
    return {
        info = function() end,
        warn = function() end,
    }
end

package.preload["ffi/blitbuffer"] = function()
    return {
        COLOR_BLACK = "black",
        COLOR_WHITE = "white",
    }
end

package.preload["device"] = function()
    return {
        screen = {
            scaleBySize = function(_, value) return math.max(1, math.floor(value * 1.5)) end,
            getWidth = function() return 1072 end,
            getHeight = function() return 1448 end,
        },
    }
end

package.preload["ui/font"] = function()
    return {
        fontmap = { cfont = "NotoSans-Regular.ttf" },
        getFace = function(_, name)
            return { name = name }
        end,
    }
end

package.preload["fontlist"] = function()
    return { fontdir = "fonts" }
end

package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function(path)
            if path == "fonts/Mac1984Chicago.ttf" then return "file" end
        end,
    }
end

package.preload["ui/size"] = function()
    return {
        border = {},
        line = {},
        radius = {},
        padding = { small = 3, large = 15, button = 6 },
    }
end

package.preload["ui/widget/container/framecontainer"] = function()
    local FrameContainer = {
        bordersize = 1,
        radius = 8,
        color = "gray",
    }
    function FrameContainer:new(options)
        return options
    end
    function FrameContainer:getSize()
        return { w = 680, h = 420 }
    end
    function FrameContainer:paintTo() end
    return FrameContainer
end

package.preload["ui/widget/titlebar"] = function()
    local TitleBar = {
        align = "left",
        title_face_fullscreen = { name = "stock" },
    }
    function TitleBar:paintTo() end
    return TitleBar
end

package.preload["ui/widget/button"] = function()
    local Button = {}
    function Button:init()
        self.frame = {}
    end
    function Button:_doFeedbackHighlight() end
    function Button:_undoFeedbackHighlight() end
    return Button
end

package.preload["ui/widget/iconbutton"] = function()
    return {
        onTapIconButton = function() end,
    }
end

package.preload["ui/widget/buttontable"] = function()
    return {
        sep_width = 1,
        addVerticalSeparator = function() end,
    }
end

package.preload["ui/widget/touchmenu"] = function()
    local TouchMenu = {}
    local TouchMenuBar = {}
    function TouchMenuBar:paintTo() end
    function TouchMenu:init()
        return TouchMenuBar
    end
    return TouchMenu
end

package.preload["userpatch"] = function()
    local userpatch = {}
    function userpatch.registerPatchPluginFunc(name, func)
        plugin_patches[name] = func
    end
    function userpatch.getUpValue(func, name)
        local index = 1
        while true do
            local up_name, value = debug.getupvalue(func, index)
            if not up_name then return nil end
            if up_name == name then return value, index end
            index = index + 1
        end
    end
    return userpatch
end

package.preload["ui/widget/menu"] = function()
    return { line_color = "gray" }
end

package.preload["features/sui_style"] = function()
    simpleui_style_loaded = true
    return {
        BORDER_SZ = 0,
        COLOR = {},
        applyPack = function() return {} end,
    }
end

G_reader_settings = {
    isFalse = function(_, name) return settings[name] == false end,
    nilOrTrue = function(_, name) return settings[name] ~= false end,
    readSetting = function(_, name) return settings[name] end,
}

dofile(assert(arg[1], "theme runtime path"))

local Font = require("ui/font")
local TitleBar = require("ui/widget/titlebar")
local Size = require("ui/size")
local FrameContainer = require("ui/widget/container/framecontainer")
local Menu = require("ui/widget/menu")

assert(plugin_patches.simpleui, "SimpleUI integration hook was not registered")
plugin_patches.simpleui()

if mode == "safe" then
    assert(Font.fontmap.cfont == "Mac1984Chicago.ttf",
        "safe mode should still map the UI font")
    assert(TitleBar.title_face_fullscreen.name == "smalltfont",
        "safe mode should still refresh title faces")
    assert(Size.radius.window == nil, "safe mode changed widget size tokens")
    assert(FrameContainer.radius == 8, "safe mode changed frame styling")
    assert(Menu.line_color == "gray", "safe mode changed menu styling")
    assert(not simpleui_style_loaded, "safe mode applied SimpleUI style tokens")
else
    assert(Font.fontmap.cfont == "NotoSans-Regular.ttf",
        "disabled UI font was still replaced")
    assert(TitleBar.title_face_fullscreen.name == "stock",
        "disabled UI font still refreshed title faces")
    assert(Size.radius.window == 0, "widget patches did not run with the stock font")
    assert(Menu.line_color == "black", "menu styling was not applied")
    assert(simpleui_style_loaded, "SimpleUI style tokens were not applied")
end

print("apply options test OK (" .. mode .. ")")
