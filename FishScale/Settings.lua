local addonName, ns = ...

-- The settings panel. Everything on it comes from ns.RegisterSetting, so this
-- file never needs editing when a setting is added: it renders whatever has
-- been declared, in declaration order.

local PADDING = 16

-- The height of the heading, so the paragraph clears the logo and title.
-- Controls no longer measure anything from the top -- they hang off each
-- other -- so this is the only fixed vertical offset left.
local TITLE_ROW = 30

-- Headroom above a slider for the label that sits on top of it. A slider is
-- the one control whose text is above rather than beside it, so it needs
-- clearing from whatever is above it as well as from its own row.
local SLIDER_EXTRA = 26

-- Between one control and the next, and between the intro paragraph and the
-- first control. Generous on purpose: the paragraph wraps to however many
-- lines the text needs, and a fixed offset that fits today is one sentence
-- away from the first checkbox sitting on top of it.
local ROW_GAP = 14
local HINT_GAP = 18

-- Between a control and the words naming it. At 4 the label touched the box.
local LABEL_GAP = 8

-- Wide enough for a 200px slider with room to spare, and comfortably inside
-- the canvas the game gives us.
local COLUMN_WIDTH = 280

-- Big enough to read as a logo beside a GameFontNormalLarge title without
-- crowding the line the hint sits on just below it.
local LOGO_SIZE = 24

local Panel = {}
ns.SettingsPanel = Panel
Panel.controls = {}

local panel, category, built

local function addCheckbox(setting, anchorTo, gap)
    local button = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -gap)

    -- The label belongs to the template on some clients and not others, so
    -- write our own rather than reaching for button.Text and finding nil.
    local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", button, "RIGHT", LABEL_GAP, 0)
    label:SetText(setting.name)

    button:SetScript("OnClick", function(self)
        ns.SetSettingValue(setting, self:GetChecked() and true or false)
    end)

    return {
        setting = setting,
        widget = button,
        Refresh = function()
            button:SetChecked(ns.SettingValue(setting) and true or false)
        end,
    }
end

local function addSlider(setting, anchorTo, gap)
    local slider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    -- SLIDER_EXTRA on top of the usual gap: a slider wears its label above
    -- itself rather than beside it, so it needs room the other controls do
    -- not.
    slider:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -(gap + SLIDER_EXTRA))
    slider:SetMinMaxValues(setting.min, setting.max)
    slider:SetValueStep(setting.step or 1)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(200)

    -- The template labels its ends "Low" and "High", which says nothing about
    -- the range. Show the actual numbers where the template exposes them.
    if slider.Low and slider.Low.SetText then
        slider.Low:SetText(tostring(setting.min))
    end
    if slider.High and slider.High.SetText then
        slider.High:SetText(tostring(setting.max))
    end

    local label = slider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 4)

    -- A setting may describe its own value where the number alone does not
    -- tell the whole story -- the reach is asked for but only sometimes
    -- granted, and a slider reading 45 beside a client that allowed 20 is a
    -- lie the player has no way to catch.
    local function relabel(value)
        local shown = setting.describe and setting.describe(value)
            or string.format("%d", value or 0)
        label:SetText(string.format("%s: %s", setting.name, shown))
    end

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        ns.SetSettingValue(setting, value)
        -- Relabelled after the write, not before: describe() asks the client
        -- what it granted, and before the write it would still be answering
        -- about the old value.
        relabel(value)
    end)

    return {
        setting = setting,
        widget = slider,
        Refresh = function()
            local value = ns.SettingValue(setting)
            slider:SetValue(value)
            relabel(value)
        end,
    }
end

-- Pressed on their own these set no binding; they are what a binding is built
-- *with*. Without this the capture ends the instant a player reaches for
-- Shift, and the key they wanted is never seen.
local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true,
    LCTRL = true, RCTRL = true,
    LALT = true, RALT = true,
    UNKNOWN = true,
}

--- The binding string for a key pressed right now, or nil if that key cannot
-- be one on its own. Modifiers in the order the client writes them, so what
-- is stored is what SetOverrideBinding would have produced.
local function bindingFor(key)
    if not key or MODIFIER_KEYS[key] then
        return nil
    end

    local prefix = ""
    if IsAltKeyDown and IsAltKeyDown() then
        prefix = prefix .. "ALT-"
    end
    if IsControlKeyDown and IsControlKeyDown() then
        prefix = prefix .. "CTRL-"
    end
    if IsShiftKeyDown and IsShiftKeyDown() then
        prefix = prefix .. "SHIFT-"
    end

    return prefix .. key
end

--- A button that takes a key by having it pressed at it.
--
-- Not a text box. A key is not a value to be typed -- "SHIFT-BUTTON4" is
-- exactly the sort of string that is easy to get subtly wrong and impossible
-- to tell is wrong, because a binding that does not parse simply never fires.
-- Pressing the key cannot be misspelled.
local function addKeybind(setting, anchorTo, gap)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -gap)
    button:SetSize(150, 24)
    -- The template carries this, but a button that takes no mouse looks
    -- entirely correct and does nothing, and this repo has lost rounds to
    -- exactly that. Cheaper to say it than to diagnose it.
    button:EnableMouse(true)

    local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", button, "RIGHT", LABEL_GAP, 0)
    label:SetText(setting.name)

    local capturing = false

    local function show()
        if capturing then
            button:SetText("Press a key...")
        else
            button:SetText(ns.SettingValue(setting) or "not set")
        end
    end

    local function stopCapture()
        capturing = false
        button:EnableKeyboard(false)
        -- Let key presses reach the game again. Left set, the player's
        -- movement keys stop working the moment they close the panel.
        if button.SetPropagateKeyboardInput then
            button:SetPropagateKeyboardInput(true)
        end
        show()
    end

    local function startCapture()
        capturing = true
        button:EnableKeyboard(true)
        -- Swallow what is pressed while the panel is listening, so binding
        -- the key does not also fire whatever it currently does.
        if button.SetPropagateKeyboardInput then
            button:SetPropagateKeyboardInput(false)
        end
        show()
    end

    local function take(key)
        if not capturing then
            return
        end

        if key == "ESCAPE" then
            stopCapture()
            return
        end

        local binding = bindingFor(key)
        if not binding then
            -- A modifier on its own: keep listening for the key it modifies.
            return
        end

        stopCapture()
        ns.SetSettingValue(setting, binding)
        show()
    end

    button:SetScript("OnClick", startCapture)
    button:SetScript("OnKeyDown", function(_, key) take(key) end)

    -- Mouse buttons past the first two can be bindings too, and a player who
    -- fishes with a thumb button should not have to type its name. Left and
    -- right are what opened the capture, so they are not on offer.
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" or mouseButton == "RightButton" then
            return
        end
        take(mouseButton)
    end)

    return {
        setting = setting,
        widget = button,
        -- Exposed so a panel closing mid-capture can put the keyboard back.
        StopCapture = stopCapture,
        Refresh = show,
    }
end

-- Guards against a refresh that starts another. A slider's Refresh sets its
-- own value, which the client answers with OnValueChanged, which runs the
-- setting's onChange. It still cannot recurse from inside a Refresh already
-- running: ns.SetSettingValue returns early when the value has not changed,
-- and Refresh always sets a control to exactly the value already stored.
local refreshing = false

function Panel.Refresh()
    if refreshing then
        return
    end

    refreshing = true
    for _, control in ipairs(Panel.controls) do
        control.Refresh()
    end
    refreshing = false
end

local function ensureBuilt()
    if built or not panel then
        return
    end
    built = true

    -- logo, not icon. They are the same fish drawn twice: icon.tga has the
    -- tile behind it that the AddOns list needs, because every entry there
    -- is a square and one that is not looks broken. Here the opposite is
    -- true -- a square tile on a dark grey panel reads as a sticker pasted
    -- on it -- so logo.tga is the fish alone, on transparency.
    --
    -- Built from addonName rather than spelled out: the .toc already names
    -- this folder, and a second copy of the path is the one that goes stale
    -- when it is renamed.
    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("TOPLEFT", PADDING, -PADDING)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\logo")
    Panel.logo = logo

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    -- Centred against the logo rather than pinned to the panel, so the two
    -- read as one heading whatever size the logo is given.
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("FishScale")

    -- From the addon's own metadata, not a constant here, which would drift
    -- from the .toc the first time either is bumped without the other.
    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -PADDING - TITLE_ROW)
    hint:SetWidth(COLUMN_WIDTH - PADDING * 2)
    hint:SetJustifyH("LEFT")
    Panel.hint = hint
    hint:SetText(
        "One key for the whole loop: press it to cast, and press it again "
        .. "to pick the bobber up. The key is yours again in combat, and "
        .. "while the loot window is open."
    )

    -- Each control hangs below the one before it, and the first below the
    -- paragraph, rather than every control sitting at a counted offset from
    -- the top. The paragraph wraps to however many lines its text needs, and
    -- only the client knows how many that is -- a count kept here was right
    -- for two lines and put the first checkbox on top of the third.
    local anchorTo = hint
    local gap = HINT_GAP

    for _, setting in ipairs(ns.settings) do
        local control
        if setting.type == "slider" then
            control = addSlider(setting, anchorTo, gap)
        elseif setting.type == "keybind" then
            control = addKeybind(setting, anchorTo, gap)
        else
            control = addCheckbox(setting, anchorTo, gap)
        end

        table.insert(Panel.controls, control)
        anchorTo = control.widget
        gap = ROW_GAP
    end

    Panel.Refresh()
end

Panel.EnsureBuilt = ensureBuilt

--- Give the keyboard back, whatever the panel was in the middle of.
--
-- A capture left running when the panel closes holds every key press away
-- from the game, which looks exactly like the client having frozen.
function Panel.StopCapturing()
    for _, control in ipairs(Panel.controls) do
        if control.StopCapture then
            control.StopCapture()
        end
    end
end

--- Claim a place in the game's options, without building anything yet.
local function register()
    panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel.name = "FishScale"
    Panel.panel = panel

    panel:SetScript("OnShow", function()
        ensureBuilt()
        Panel.Refresh()
    end)

    panel:SetScript("OnHide", Panel.StopCapturing)

    -- A canvas category holds widgets we own, which avoids
    -- Settings.RegisterAddOnSetting: its argument list changed in 11.0 and a
    -- wrong guess there registers nothing and fails silently.
    category = Settings.RegisterCanvasLayoutCategory(panel, "FishScale")
    Settings.RegisterAddOnCategory(category)
end

-- Whether the panel on screen was opened from our command rather than through
-- the game menu. Decides where closing it should leave the player.
local openedByUs = false
local suppressGameMenu = false
local closeHooked = false

local function dismissGameMenu(frame)
    suppressGameMenu = false
    if HideUIPanel then
        HideUIPanel(frame)
    else
        frame:Hide()
    end
end

local function watchForClose()
    if closeHooked or not SettingsPanel or not SettingsPanel.HookScript then
        return
    end
    closeHooked = true

    SettingsPanel:HookScript("OnHide", function()
        Panel.StopCapturing()

        -- Opening the panel from a command leaves the client queued to fall
        -- back to the game menu, which is not where the player came from.
        if not openedByUs then
            return
        end
        openedByUs = false
        suppressGameMenu = true

        C_Timer.After(0, function()
            if suppressGameMenu then
                if GameMenuFrame and GameMenuFrame:IsShown() then
                    dismissGameMenu(GameMenuFrame)
                end
                suppressGameMenu = false
            end
        end)
    end)

    if GameMenuFrame and GameMenuFrame.HookScript then
        GameMenuFrame:HookScript("OnShow", function(self)
            if suppressGameMenu then
                dismissGameMenu(self)
            end
        end)
    end
end

function ns.OpenSettings()
    if not category then
        ns.Print("This client has no settings panel. Use /fs help for commands.")
        return
    end

    watchForClose()
    openedByUs = true
    ensureBuilt()

    Settings.OpenToCategory(category:GetID())
    Panel.Refresh()
end

ns.RegisterCommand("settings", "Open the settings panel", function()
    ns.OpenSettings()
end)

ns.OnLogin(function()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        register()
    else
        ns.Print("This client has no settings panel API. Use /fs help instead.")
    end
end)
