local addonName, ns = ...

-- The settings panel. Everything on it comes from ns.RegisterSetting, so this
-- file never needs editing when a setting is added: it renders whatever has
-- been declared, in declaration order.

local PADDING = 16
local ROW_HEIGHT = 30
local SLIDER_EXTRA = 24
local BOX_HEIGHT = 24
-- Wide enough for a 200px slider or the spell table's boxes (which reach
-- x=216 from the column's left edge) with room to spare. Two of these is the
-- whole panel, and comfortably inside the canvas the game gives us.
-- Big enough to read as a logo beside a GameFontNormalLarge title without
-- crowding the line the hint sits on just below it.
local LOGO_SIZE = 24

local COLUMN_WIDTH = 280
local PANEL_WIDTH = COLUMN_WIDTH * 2

local Panel = {}
ns.SettingsPanel = Panel
Panel.controls = {}
Panel.headings = {}

local panel, category, built

local function addCheckbox(setting, y, x)
    local button = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)

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

local function addSlider(setting, y, x)
    local slider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x, y - SLIDER_EXTRA)
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

-- The spell picker: one shared list, opened against whichever row asked for
-- it.
--
-- A list rather than a drop target on these rows, because the spellbook is a
-- full-screen panel on this client. It covers the bar and the settings panel
-- alike, so nothing needing both open at once can work -- which is what put
-- the player back to typing names in the first place. Dragging a spell onto
-- a bar button still works for anyone whose spellbook does not cover it.
local PICKER_ROWS = 10
local PICKER_WIDTH = 210
local CLEAR_ENTRY = "(empty this slot)"

local picker

local function pickerEntries()
    -- Emptying a slot is the one thing the spellbook cannot offer, so it is
    -- offered here rather than sending the player back to the text box to
    -- delete what they typed.
    local entries = { CLEAR_ENTRY }

    for _, name in ipairs(ns.Spells.Known()) do
        entries[#entries + 1] = name
    end

    return entries
end

local function refreshPicker()
    for index, button in ipairs(picker.buttons) do
        local entry = picker.entries[index + picker.offset]

        if entry then
            button.spellName = entry ~= CLEAR_ENTRY and entry or nil
            button.label:SetText(entry)

            local texture = button.spellName and ns.Spells.Texture(button.spellName)
            if texture then
                button.icon:SetTexture(texture)
                button.icon:Show()
            else
                button.icon:Hide()
            end

            button:Show()
        else
            button:Hide()
        end
    end
end

--- Put `name` in `slot` and close the list. nil empties the slot.
function Panel.Choose(slot, name)
    local ok, message = ns.Slots.Set(slot, name or "")
    if not ok then
        ns.Print(message or "That slot does not exist.")
    elseif message then
        ns.Print(message)
    end

    -- The same two steps the text box's own store does, by way of the
    -- setting's onChange: write the slot, then put it on the rows.
    if ns.Group then
        ns.Group.ApplyAll()
    end

    if picker then
        picker:Hide()
    end

    Panel.Refresh()
end

local function ensurePicker()
    if picker then
        return
    end

    picker = CreateFrame("Frame", nil, panel)
    -- Above the rows it drops over, which are ordinary canvas widgets.
    picker:SetFrameStrata("DIALOG")
    picker:SetSize(PICKER_WIDTH, PICKER_ROWS * BOX_HEIGHT + 8)
    -- So a click on the list is not also a click on whatever is under it.
    picker:EnableMouse(true)
    picker:EnableMouseWheel(true)
    picker.buttons = {}
    picker.entries = {}
    picker.offset = 0

    local background = picker:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.9)

    for index = 1, PICKER_ROWS do
        local button = CreateFrame("Button", nil, picker)
        button:SetSize(PICKER_WIDTH - 8, BOX_HEIGHT - 4)
        button:SetPoint("TOPLEFT", 4, -4 - (index - 1) * BOX_HEIGHT)

        -- Drawn rather than taken from Blizzard's highlight art: the client
        -- shows and hides the HIGHLIGHT layer on mouseover by itself, and a
        -- colour fill cannot silently turn out not to exist on this client.
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.2)

        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(BOX_HEIGHT - 8, BOX_HEIGHT - 8)
        button.icon:SetPoint("LEFT", 2, 0)
        button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        button.label = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        button.label:SetPoint("LEFT", button.icon, "RIGHT", 4, 0)
        button.label:SetJustifyH("LEFT")

        button:SetScript("OnClick", function(self)
            Panel.Choose(picker.slot, self.spellName)
        end)

        picker.buttons[index] = button
    end

    picker:SetScript("OnMouseWheel", function(self, delta)
        local last = math.max(#self.entries - PICKER_ROWS, 0)
        self.offset = math.min(math.max(self.offset - delta, 0), last)
        refreshPicker()
    end)

    picker:Hide()
    Panel.picker = picker
end

local function openPicker(slot, anchorTo)
    ensurePicker()

    -- A second click on the row that is already open closes it, which is
    -- what clicking an open dropdown means everywhere else.
    if picker:IsShown() and picker.slot == slot then
        picker:Hide()
        return
    end

    picker.slot = slot
    picker.entries = pickerEntries()
    picker.offset = 0
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -2)
    refreshPicker()
    picker:Show()
end

Panel.OpenPicker = openPicker

--- One edit box per slot, and a Pick button beside each. Typing a name and
-- pressing Enter stores it; Pick opens the list above instead.
-- The store is Slots.Set rather than SetSettingValue, because a slot is one
-- entry inside a table rather than a value of its own, and because Set is
-- where the "you have not learned that yet" warning comes from.
local function addSpellTable(setting, y, x)
    local rows = setting.rows or 8
    local boxes = {}
    local picks = {}

    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", x, y)
    heading:SetText(setting.name)

    for index = 1, rows do
        local top = y - ROW_HEIGHT - (index - 1) * BOX_HEIGHT

        local number = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        number:SetPoint("TOPLEFT", x, top - 4)
        number:SetText(tostring(index))

        local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        box:SetPoint("TOPLEFT", x + 20, top)
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

        -- Typing stays, because it is the only way to set up a spell you
        -- have not learned yet -- the Remove Curse a druid gets at 24 is not
        -- in the spellbook to be picked. This is for the other case, which
        -- is every other case.
        local pick = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        pick:SetSize(46, BOX_HEIGHT - 4)
        pick:SetPoint("LEFT", box, "RIGHT", 6, 0)
        pick:SetText("Pick")
        pick:SetScript("OnClick", function()
            openPicker(index, box)
        end)

        boxes[index] = box
        picks[index] = pick
    end

    return {
        setting = setting,
        widget = boxes[1],
        boxes = boxes,
        picks = picks,
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

    -- The addon's own icon, the one the AddOns list shows, built from
    -- addonName rather than spelled out: the .toc already points at this
    -- file, and a second copy of the path here would be the thing that goes
    -- stale when the folder is renamed.
    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("TOPLEFT", PADDING, -PADDING)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\icon")
    Panel.logo = logo

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    -- Centred against the icon rather than pinned to the panel, so the two
    -- read as one heading whatever size the icon is given.
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
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

    -- Two columns, each falling down its own side independently. A setting
    -- names the column it belongs to; anything that names none goes left,
    -- which is every setting declared before columns existed.
    local top = -PADDING - ROW_HEIGHT * 2
    local columnX = { left = PADDING, right = PADDING + COLUMN_WIDTH }
    local y = { left = top, right = top }

    for _, setting in ipairs(ns.settings) do
        local column = columnX[setting.column] and setting.column or "left"
        local x = columnX[column]

        -- The heading goes in above the first control that claims the
        -- column, so an untitled column costs nothing and a column nobody
        -- puts a setting in never appears at all.
        if ns.columns[column] and not Panel.headings[column] then
            local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            heading:SetPoint("TOPLEFT", x, y[column])
            heading:SetText(ns.columns[column])
            Panel.headings[column] = heading
            y[column] = y[column] - ROW_HEIGHT
        end

        local control
        if setting.type == "slider" then
            control = addSlider(setting, y[column], x)
            y[column] = y[column] - ROW_HEIGHT - SLIDER_EXTRA
        elseif setting.type == "spelltable" then
            control = addSpellTable(setting, y[column], x)
            y[column] = y[column] - control.height
        else
            control = addCheckbox(setting, y[column], x)
            y[column] = y[column] - ROW_HEIGHT
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
