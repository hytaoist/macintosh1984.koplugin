-- Lightweight smoke test for the theme runtime. It mocks only the KOReader
-- modules touched by plugin/theme/apply.lua, so it can run on a normal
-- development machine without a device runtime.

local warnings = {}
local painted_rects = 0
local plugin_patches = {}

package.preload["logger"] = function()
    return {
        info = function() end,
        warn = function(...)
            table.insert(warnings, table.concat({ ... }, " "))
        end,
    }
end

package.preload["ffi/blitbuffer"] = function()
    return {
        COLOR_BLACK = "black",
        COLOR_WHITE = "white",
        COLOR_DARK_GRAY = "dark-gray",
        isColor8 = function() return true end,
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
        fontmap = {},
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
        padding = { small = 3, large = 15 },
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
        return { w = self.width or 680, h = self.height or 420 }
    end
    function FrameContainer:paintTo()
        painted_rects = painted_rects + 1
    end
    return FrameContainer
end

package.preload["ui/widget/titlebar"] = function()
    local TitleBar = { align = "left" }
    function TitleBar:paintTo()
        painted_rects = painted_rects + 1
    end
    return TitleBar
end

package.preload["ui/widget/button"] = function()
    local Button = {}
    function Button:init()
        self.frame = {}
    end
    function Button:_doFeedbackHighlight()
        self.original_highlight_called = true
    end
    function Button:_undoFeedbackHighlight()
        self.original_unhighlight_called = true
    end
    return Button
end

package.preload["ui/widget/iconbutton"] = function()
    local IconButton = {}
    function IconButton:onTapIconButton()
        self.original_tap_called = true
    end
    return IconButton
end

package.preload["ui/widget/buttontable"] = function()
    local ButtonTable = { sep_width = 1 }
    function ButtonTable:addVerticalSeparator(black_line)
        self.last_separator_was_black = black_line
    end
    return ButtonTable
end

package.preload["ui/widget/touchmenu"] = function()
    local TouchMenu = {}
    local TouchMenuBar = {}
    function TouchMenuBar:paintTo()
        painted_rects = painted_rects + 1
    end
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

local settings = {}
G_reader_settings = {
    isFalse = function(_, name) return settings[name] == false end,
    nilOrTrue = function(_, name) return settings[name] ~= false end,
    readSetting = function(_, name) return settings[name] end,
}

local patch_path = arg[1] or "plugin/theme/apply.lua"
dofile(patch_path)

assert(#warnings == 0, "Patch produced warnings: " .. table.concat(warnings, " | "))

local Font = require("ui/font")
local Size = require("ui/size")
local FrameContainer = require("ui/widget/container/framecontainer")
local TitleBar = require("ui/widget/titlebar")
local Button = require("ui/widget/button")
local IconButton = require("ui/widget/iconbutton")
local ButtonTable = require("ui/widget/buttontable")
local TouchMenu = require("ui/widget/touchmenu")
local Menu = require("ui/widget/menu")
local userpatch = require("userpatch")
local TouchMenuBar = userpatch.getUpValue(TouchMenu.init, "TouchMenuBar")

assert(Font.fontmap.cfont == "Mac1984Chicago.ttf", "UI font was not mapped")
assert(TitleBar.title_face_fullscreen
    and TitleBar.title_face_fullscreen.name == "smalltfont",
    "TitleBar faces were not refreshed for the themed font")
assert(Size.radius.window == 0, "Window radius was not squared")
assert(Menu.line_color == "black", "Menu rules were not themed")
assert(TouchMenuBar, "TouchMenuBar was not patched")
assert(plugin_patches.simpleui, "SimpleUI integration hook was not registered")

local square_frame = FrameContainer.new({}, { radius = 12 })
assert(square_frame.radius == 0, "Explicit frame radius was not squared")

local bb = {
    paintRect = function()
        painted_rects = painted_rects + 1
    end,
}

local frame = {
    background = "white",
    bordersize = Size.border.window,
    width = 680,
    height = 420,
    getSize = FrameContainer.getSize,
}
FrameContainer.paintTo(frame, bb, 20, 30)
assert(painted_rects > 0, "Frame shadow was not painted")

local titlebar = {
    dimen = { w = 800, h = 110 },
    title_group = { getSize = function() return { w = 800, h = 70 } end },
    title_widget = { getWidth = function() return 220 end },
}
TitleBar.paintTo(titlebar, bb, 0, 0)

local button = { bordersize = 0 }
Button.init(button)
assert(button.frame.inner_bordersize == Size.border.default, "Button outline was not applied")

local unlaid_button = { [1] = {} }
Button._doFeedbackHighlight(unlaid_button)
Button._undoFeedbackHighlight(unlaid_button)
assert(not unlaid_button.original_highlight_called, "Button highlight should be skipped without geometry")
assert(not unlaid_button.original_unhighlight_called, "Button unhighlight should be skipped without geometry")

local laid_button = { [1] = { dimen = { x = 0, y = 0, w = 10, h = 10 } } }
Button._doFeedbackHighlight(laid_button)
Button._undoFeedbackHighlight(laid_button)
assert(laid_button.original_highlight_called, "Button highlight should work with geometry")
assert(laid_button.original_unhighlight_called, "Button unhighlight should work with geometry")

local callback_called = false
local unlaid_icon = {
    allow_flash = true,
    image = {},
    callback = function() callback_called = true end,
}
assert(IconButton.onTapIconButton(unlaid_icon) == true, "Icon fallback should handle the tap")
assert(callback_called, "Icon callback should run without geometry")
assert(not unlaid_icon.original_tap_called, "Icon flash path should be skipped without geometry")

local laid_icon = {
    allow_flash = true,
    dimen = { x = 0, y = 0 },
    image = { dimen = { x = 0, y = 0, w = 10, h = 10 } },
    callback = function() end,
}
IconButton.onTapIconButton(laid_icon)
assert(laid_icon.original_tap_called, "Icon flash path should run with geometry")

local button_table = {}
ButtonTable.addVerticalSeparator(button_table)
assert(button_table.last_separator_was_black == true, "Dialog separator was not black")

local menubar = { width = 1072, height = 90 }
TouchMenuBar.paintTo(menubar, bb, 0, 0)
assert(painted_rects > 10, "Expected several painted primitives")

-- SimpleUI can apply its saved font after plugin startup. The plugin hook must
-- put Chicago back into every themed slot.
Font.fontmap.smalltfont = "OpenDyslexic.otf"
plugin_patches.simpleui()
assert(Font.fontmap.smalltfont == "Mac1984Chicago.ttf", "SimpleUI overrode the UI font")

print("patch smoke test OK")
