local addonName, ns = ...

-- The settings panel. Everything on it comes from ns.RegisterSetting, so this
-- file never needs editing when a setting is added: it renders whatever has
-- been declared, in declaration order.

local PADDING = 16
local ROW_HEIGHT = 30
local SLIDER_EXTRA = 24
local BOX_HEIGHT = 24
local PANEL_WIDTH = 400

local Panel = {}
ns.SettingsPanel = Panel
Panel.controls = {}

local panel, category, built

local function addCheckbox(setting, y)
    local button = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", PADDING, y)

    -- The label belongs to the template on some clients and not others, so
    -- write our own rather than reaching for button.Text and finding nil.
    local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", button, "RIGHT", 4, 0)
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

local function addSlider(setting, y)
    local slider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", PADDING, y - SLIDER_EXTRA)
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

    local function relabel(value)
        label:SetText(string.format("%s: %d", setting.name, value or 0))
    end

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        relabel(value)
        ns.SetSettingValue(setting, value)
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

--- One edit box per slot. Typing a name and pressing Enter stores it.
-- The store is Slots.Set rather than SetSettingValue, because a slot is one
-- entry inside a table rather than a value of its own, and because Set is
-- where the "you have not learned that yet" warning comes from.
local function addSpellTable(setting, y)
    local rows = setting.rows or 8
    local boxes = {}

    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", PADDING, y)
    heading:SetText(setting.name)

    for index = 1, rows do
        local top = y - ROW_HEIGHT - (index - 1) * BOX_HEIGHT

        local number = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        number:SetPoint("TOPLEFT", PADDING, top - 4)
        number:SetText(tostring(index))

        local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        box:SetPoint("TOPLEFT", PADDING + 20, top)
        box:SetSize(180, BOX_HEIGHT - 4)
        -- Both, and in this order. An EditBox grabs focus as it comes into
        -- existence, so SetAutoFocus(false) is a line too late to prevent it
        -- and the box has to be told to let go of what it already took --
        -- otherwise the last row built stays focused, and the player's next
        -- click anywhere silently re-stores its text and re-applies.
        box:SetAutoFocus(false)
        box:ClearFocus()

        -- Set while Escape reverts the text and lets go of focus, so the
        -- OnEditFocusLost that ClearFocus() triggers as a side effect does
        -- not re-store the value Escape just discarded.
        local reverting = false

        local function store()
            if reverting then
                return
            end

            local ok, message = ns.Slots.Set(index, box:GetText())
            if not ok then
                ns.Print(message or "That slot does not exist.")
            elseif message then
                ns.Print(message)
            end

            if setting.onChange then
                setting.onChange()
            end
        end

        -- ClearFocus() itself fires OnEditFocusLost, which is where storing
        -- happens. Binding store to OnEnterPressed too would run it twice for
        -- one Enter press; ForeverPanel's key table splits the two for the
        -- same reason.
        box:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        box:SetScript("OnEditFocusLost", store)
        box:SetScript("OnEscapePressed", function(self)
            reverting = true
            self:SetText(ns.Slots.Spell(index) or "")
            self:ClearFocus()
            reverting = false
        end)

        boxes[index] = box
    end

    return {
        setting = setting,
        widget = boxes[1],
        boxes = boxes,
        height = ROW_HEIGHT + rows * BOX_HEIGHT,
        Refresh = function()
            for index = 1, rows do
                boxes[index]:SetText(ns.Slots.Spell(index) or "")
            end
        end,
    }
end

function Panel.Refresh()
    for _, control in ipairs(Panel.controls) do
        control.Refresh()
    end
end

local function ensureBuilt()
    if built or not panel then
        return
    end
    built = true

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PADDING, -PADDING)
    title:SetText("Healclick")

    -- From the addon's own metadata, not a constant here, which would drift
    -- from the .toc the first time either is bumped without the other.
    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -PADDING - ROW_HEIGHT)
    hint:SetWidth(PANEL_WIDTH - PADDING * 2)
    hint:SetJustifyH("LEFT")
    hint:SetText(
        "Changes take effect out of combat. Anything you change mid-fight is "
        .. "held until it ends, because the game will not let an addon "
        .. "re-point a spell button while you are fighting."
    )

    local y = -PADDING - ROW_HEIGHT * 2

    for _, setting in ipairs(ns.settings) do
        local control
        if setting.type == "slider" then
            control = addSlider(setting, y)
            y = y - ROW_HEIGHT - SLIDER_EXTRA
        elseif setting.type == "spelltable" then
            control = addSpellTable(setting, y)
            y = y - control.height
        else
            control = addCheckbox(setting, y)
            y = y - ROW_HEIGHT
        end

        table.insert(Panel.controls, control)
    end

    Panel.Refresh()
end

Panel.EnsureBuilt = ensureBuilt

--- Claim a place in the game's options, without building anything yet.
local function register()
    panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel.name = "Healclick"
    Panel.panel = panel

    panel:SetScript("OnShow", function()
        ensureBuilt()
        Panel.Refresh()
    end)

    -- A canvas category holds widgets we own, which avoids
    -- Settings.RegisterAddOnSetting: its argument list changed in 11.0 and a
    -- wrong guess there registers nothing and fails silently.
    category = Settings.RegisterCanvasLayoutCategory(panel, "Healclick")
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
        ns.Print("This client has no settings panel. Use /hc for commands.")
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
        ns.Print("This client has no settings panel API. Use /hc instead.")
    end
end)
