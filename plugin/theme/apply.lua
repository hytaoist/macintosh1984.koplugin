-- Macintosh 1984 runtime for KOReader.
--
-- This file is copied into KOReader's stable theme data directory by the
-- Macintosh 1984 plugin. The installed patch is intentionally tiny and only
-- loads this runtime, so Storefront can replace the plugin while the user patch
-- remains stable.

local logger = require("logger")

if G_reader_settings:isFalse("mac1984_enabled") then
    _G._mac1984_theme_status = "disabled"
    logger.info("Mac1984: disabled by settings.reader.lua")
    return
end

if _G._mac1984_theme_loaded then
    _G._mac1984_theme_status = "loaded"
    logger.info("Mac1984: theme runtime already loaded")
    return
end
_G._mac1984_theme_loaded = true
_G._mac1984_theme_status = "loading"
_G._mac1984_theme_error = nil

local UI_FONT_FILE = "Mac1984Chicago.ttf"
local FONT_SLOTS = {
    "cfont",
    "tfont",
    "smalltfont",
    "x_smalltfont",
    "ffont",
    "smallffont",
    "largeffont",
    "rifont",
    "pgfont",
    "hfont",
    "infofont",
    "smallinfofont",
    "smallinfofontbold",
    "x_smallinfofont",
    "xx_smallinfofont",
}

local function apply_ui_font()
    if G_reader_settings:isFalse("mac1984_ui_font") then
        return false, "disabled"
    end
    local Font = require("ui/font")
    local FontList = require("fontlist")
    local lfs = require("libs/libkoreader-lfs")
    local font_path = FontList.fontdir .. "/" .. UI_FONT_FILE
    if lfs.attributes(font_path, "mode") ~= "file" then
        return false, font_path
    end
    for _i, slot in ipairs(FONT_SLOTS) do
        Font.fontmap[slot] = UI_FONT_FILE
    end
    return true
end

local function refresh_titlebar_faces()
    local ok_tb, TitleBar = pcall(require, "ui/widget/titlebar")
    if not ok_tb or not TitleBar then return end
    local Font = require("ui/font")
    local slots = {
        { field = "title_face_fullscreen",     face = "smalltfont" },
        { field = "title_face_not_fullscreen", face = "x_smalltfont" },
        { field = "subtitle_face",             face = "xx_smallinfofont" },
        { field = "info_text_face",            face = "x_smallinfofont" },
    }
    for _i, slot in ipairs(slots) do
        local ok_face, face = pcall(Font.getFace, Font, slot.face)
        if ok_face and face then
            TitleBar[slot.field] = face
        end
    end
end

local function apply_simpleui_tokens()
    local ok, SimpleUIStyle = pcall(require, "features/sui_style")
    if not ok or type(SimpleUIStyle) ~= "table" then
        return false
    end
    local Screen = require("device").screen
    SimpleUIStyle.BORDER_SZ = math.max(2, math.floor(Screen:scaleBySize(2)))
    local Blitbuffer = require("ffi/blitbuffer")
    if type(SimpleUIStyle.COLOR) == "table" then
        SimpleUIStyle.COLOR.text_primary = Blitbuffer.COLOR_BLACK
        SimpleUIStyle.COLOR.text_dim = Blitbuffer.COLOR_BLACK
        SimpleUIStyle.COLOR.surface = Blitbuffer.COLOR_WHITE
        SimpleUIStyle.COLOR.surface_gray = Blitbuffer.COLOR_WHITE
        SimpleUIStyle.COLOR.gray = Blitbuffer.COLOR_BLACK
        SimpleUIStyle.COLOR.gray_strong = Blitbuffer.COLOR_BLACK
    end
    return true
end

local function apply_theme()
    local Blitbuffer = require("ffi/blitbuffer")
    local Device = require("device")
    local Screen = Device.screen
    local Size = require("ui/size")

    local has_ui_font, font_path = apply_ui_font()
    if not has_ui_font then
        if font_path == "disabled" then
            logger.info("Mac1984: UI font replacement disabled")
        else
            logger.warn("Mac1984: font not found at", font_path, "- using stock UI font")
        end
    else
        -- The runtime may load after KOReader has already required TitleBar,
        -- especially when startup patches are disabled. Refresh the cached
        -- title faces so the fallback path also uses the themed font.
        refresh_titlebar_faces()
    end

    if G_reader_settings:readSetting("mac1984_safe_mode") == true then
        logger.info("Mac1984: safe mode enabled; skipping widget patches")
        return
    end

    -- Square windows, heavier rules, and compact controls. Button radii are
    -- kept slightly rounded because round-rect controls are also period-correct.
    Size.border.default = math.max(1, math.floor(Screen:scaleBySize(1)))
    Size.border.button = math.max(2, math.floor(Screen:scaleBySize(2)))
    Size.border.window = math.max(2, math.floor(Screen:scaleBySize(2)))
    Size.line.thick = math.max(2, math.floor(Screen:scaleBySize(2)))
    Size.radius.default = 0
    Size.radius.window = 0
    Size.radius.button = math.max(4, math.floor(Screen:scaleBySize(6)))

    local FrameContainer = require("ui/widget/container/framecontainer")
    FrameContainer.bordersize = Size.border.window
    FrameContainer.radius = 0
    FrameContainer.color = Blitbuffer.COLOR_BLACK
    FrameContainer.focus_border_size = Size.border.window * 2
    FrameContainer.focus_border_color = Blitbuffer.COLOR_BLACK

    local orig_frame_new = FrameContainer.new
    FrameContainer.new = function(class, options)
        if type(options) == "table" then
            options.radius = 0
        end
        return orig_frame_new(class, options)
    end

    local orig_frame_paint = FrameContainer.paintTo
    FrameContainer.paintTo = function(self, bb, x, y)
        local shadows = G_reader_settings:nilOrTrue("mac1984_shadows")
        local size_ok, size = pcall(self.getSize, self)
        local screen_w = Screen:getWidth()
        local screen_h = Screen:getHeight()
        local is_large_frame = size_ok and size
            and (self.background and (self.bordersize or 0) > 0)
            and size.w > screen_w * 0.30
            and size.w < screen_w * 0.98
            and size.h > Screen:scaleBySize(70)
            and size.h < screen_h * 0.98
        if shadows and is_large_frame then
            local offset = math.max(2, math.floor(Screen:scaleBySize(3)))
            bb:paintRect(
                math.floor(x + offset),
                math.floor(y + offset),
                math.floor(size.w),
                math.floor(size.h),
                Blitbuffer.COLOR_BLACK
            )
        end
        return orig_frame_paint(self, bb, x, y)
    end

    local TitleBar = require("ui/widget/titlebar")
    TitleBar.align = "center"
    TitleBar.button_padding = Screen:scaleBySize(8)
    TitleBar.title_h_padding = Size.padding.large
    TitleBar.left_icon_size_ratio = 0.62
    TitleBar.right_icon_size_ratio = 0.62

    local orig_titlebar_paint = TitleBar.paintTo
    TitleBar.paintTo = function(self, bb, x, y)
        if G_reader_settings:nilOrTrue("mac1984_pinstripes") and self.dimen then
            local group_size
            if self.title_group then
                local ok, result = pcall(self.title_group.getSize, self.title_group)
                if ok then group_size = result end
            end
            local band_h = group_size and math.min(self.dimen.h, group_size.h + Size.padding.small)
                or self.dimen.h
            local w = math.floor(self.dimen.w)
            local h = math.floor(band_h)
            local x0 = math.floor(x)
            local y0 = math.floor(y)
            local inset = math.max(1, Size.border.default)
            local gap = math.max(3, math.floor(Screen:scaleBySize(3)))
            local rule = math.max(1, math.floor(Screen:scaleBySize(1)))

            bb:paintRect(x0, y0, w, h, Blitbuffer.COLOR_WHITE)
            local stripe_y = math.floor(y0 + inset + gap)
            while stripe_y < y0 + h - inset do
                bb:paintRect(x0 + inset, stripe_y, w - inset * 2, rule, Blitbuffer.COLOR_BLACK)
                stripe_y = stripe_y + gap
            end
            bb:paintRect(x0, y0, w, rule, Blitbuffer.COLOR_BLACK)
            bb:paintRect(x0, y0 + h - rule, w, rule, Blitbuffer.COLOR_BLACK)

            local title_w = 0
            local title_widget = self.title_widget
            if title_widget then
                local ok, result = pcall(title_widget.getWidth, title_widget)
                if ok and result then title_w = result end
            end
            if title_w > 0 then
                local plate_w = math.min(w - inset * 4, math.floor(title_w + Size.padding.large * 2))
                local plate_x = math.floor(x0 + (w - plate_w) / 2)
                local plate_y = y0 + inset + rule
                local plate_h = math.max(rule, h - (inset + rule) * 2)
                bb:paintRect(plate_x, plate_y, plate_w, plate_h, Blitbuffer.COLOR_WHITE)
                bb:paintRect(plate_x, plate_y, plate_w, rule, Blitbuffer.COLOR_BLACK)
                bb:paintRect(plate_x, plate_y + plate_h - rule, plate_w, rule, Blitbuffer.COLOR_BLACK)
                bb:paintRect(plate_x, plate_y, rule, plate_h, Blitbuffer.COLOR_BLACK)
                bb:paintRect(plate_x + plate_w - rule, plate_y, rule, plate_h, Blitbuffer.COLOR_BLACK)
            end
        end
        return orig_titlebar_paint(self, bb, x, y)
    end

    local Button = require("ui/widget/button")
    Button.bordersize = Size.border.button
    Button.radius = Size.radius.button
    Button.padding = Size.padding.button
    Button.text_font_face = "cfont"
    Button.text_font_bold = true

    local orig_button_init = Button.init
    Button.init = function(self, ...)
        orig_button_init(self, ...)
        if self.frame and (self.bordersize or 0) == 0 then
            -- ButtonTable intentionally uses borderless buttons in dialogs.
            -- An inner rule gives them a Mac control outline without changing
            -- the geometry already negotiated by the table.
            self.frame.inner_bordersize = Size.border.default
            self.frame.color = Blitbuffer.COLOR_BLACK
        end
    end

    -- Some widgets briefly exist without a laid-out frame/image. KOReader's
    -- flash_ui path assumes a geometry and crashes while indexing dimen.
    -- Keep normal feedback, but skip only the unavailable visual highlight.
    if not Button._mac1984_flash_guard then
        Button._mac1984_flash_guard = true
        local orig_feedback_highlight = Button._doFeedbackHighlight
        local orig_feedback_unhighlight = Button._undoFeedbackHighlight
        Button._doFeedbackHighlight = function(self, ...)
            local frame = self and self[1]
            if not frame or not frame.dimen then return end
            return orig_feedback_highlight(self, ...)
        end
        Button._undoFeedbackHighlight = function(self, ...)
            local frame = self and self[1]
            if not frame or not frame.dimen then return end
            return orig_feedback_unhighlight(self, ...)
        end
    end

    local ok_icon_button, IconButton = pcall(require, "ui/widget/iconbutton")
    if ok_icon_button and type(IconButton) == "table" and not IconButton._mac1984_flash_guard then
        IconButton._mac1984_flash_guard = true
        local orig_icon_tap = IconButton.onTapIconButton
        IconButton.onTapIconButton = function(self)
            if not self.callback then return end
            local flash_enabled = not G_reader_settings:isFalse("flash_ui") and self.allow_flash
            if flash_enabled and (not self.dimen or not self.image or not self.image.dimen) then
                self.callback()
                return true
            end
            return orig_icon_tap(self)
        end
    end

    local ButtonTable = require("ui/widget/buttontable")
    ButtonTable.sep_width = math.max(2, math.floor(Screen:scaleBySize(2)))
    local orig_add_vertical_separator = ButtonTable.addVerticalSeparator
    ButtonTable.addVerticalSeparator = function(self)
        return orig_add_vertical_separator(self, true)
    end

    local TouchMenu = require("ui/widget/touchmenu")
    TouchMenu.split_color = Blitbuffer.COLOR_BLACK
    TouchMenu.split_height = Size.line.medium
    local userpatch = require("userpatch")
    local TouchMenuBar = select(1, userpatch.getUpValue(TouchMenu.init, "TouchMenuBar"))
    if TouchMenuBar then
        local orig_menubar_paint = TouchMenuBar.paintTo
        TouchMenuBar.paintTo = function(self, bb, x, y)
            local w = math.floor(self.width or (self.dimen and self.dimen.w) or Screen:getWidth())
            local h = math.floor(self.height or (self.dimen and self.dimen.h) or 0)
            local rule = math.max(2, math.floor(Screen:scaleBySize(2)))
            if h > 0 then
                bb:paintRect(math.floor(x), math.floor(y), w, h, Blitbuffer.COLOR_WHITE)
                bb:paintRect(math.floor(x), math.floor(y), w, rule, Blitbuffer.COLOR_BLACK)
            end
            return orig_menubar_paint(self, bb, x, y)
        end
    end

    local Menu = require("ui/widget/menu")
    Menu.line_color = Blitbuffer.COLOR_BLACK

    logger.info("Mac1984: theme applied", has_ui_font and "(ChicagoFLF)" or "(stock UI font)")
end

local ok, err = pcall(apply_theme)
if not ok then
    _G._mac1984_theme_status = "error"
    _G._mac1984_theme_error = tostring(err)
    logger.warn("Mac1984: theme failed:", err)
else
    _G._mac1984_theme_status = "loaded"
end

-- SimpleUI applies its saved UI font after instantiation. Reassert Chicago
-- afterwards and update the few style tokens that are read at build time.
local userpatch = require("userpatch")
if type(userpatch.registerPatchPluginFunc) == "function" then
    pcall(userpatch.registerPatchPluginFunc, "simpleui", function()
        local ok_simpleui, err_simpleui = pcall(function()
            local has_font = apply_ui_font()
            if has_font then refresh_titlebar_faces() end
            if G_reader_settings:readSetting("mac1984_safe_mode") == true then return end
            apply_simpleui_tokens()
        end)
        if not ok_simpleui then
            logger.warn("Mac1984: SimpleUI integration failed:", err_simpleui)
        end
    end)
end
