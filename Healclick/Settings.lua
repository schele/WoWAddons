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

local function pickerEntries(slot)
    -- Emptying a slot is the one thing the spellbook cannot offer, so it is
    -- offered here -- and with the text boxes gone it is the only way to
    -- clear a slot at all.
    local entries = { CLEAR_ENTRY }

    -- A spell already sitting in another slot is not offered again: two
    -- buttons casting the same thing is one button wasted, and side by side
    -- there is nothing to tell them apart. The slot being picked for is
    -- exempt, so its own spell still appears as what it currently holds.
    local taken = {}
    for index = 1, ns.Slots.MAX do
        if index ~= slot then
            local spell = ns.Slots.Spell(index)
            if spell then
                taken[spell] = true
            end
        end
    end

    for _, name in ipairs(ns.Spells.Pickable()) do
        if not taken[name] then
            entries[#entries + 1] = name
        end
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

            -- The slot's current spell, marked in the list it was picked
            -- from, so opening the list says what the slot already holds
            -- rather than making the player remember.
            button.selected:SetShown(
                button.spellName ~= nil
                and button.spellName == ns.Slots.Spell(picker.slot)
            )

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
    -- Above the rows it drops over, and above the settings frame around
    -- them, which is itself a dialog.
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
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
        -- Said out loud, because a Button made without a template does not
        -- arrive with it. Without this the row takes no mouse at all: no
        -- click, and no mouseover either -- which is why the highlight
        -- below never appeared, and the missing highlight is what gave the
        -- cause away. The Pick buttons work only because their template
        -- does this for them.
        button:EnableMouse(true)
        -- Both edges, for the reason the spell buttons ask for both: this
        -- client acts on the press where others act on the release, and a
        -- button registered for only one of them can be given a pass it
        -- will not act on. Choosing hides the list, so the second pass finds
        -- nothing to click and only one choice is ever made.
        button:RegisterForClicks("AnyUp", "AnyDown")

        -- Drawn rather than taken from Blizzard's highlight art: the client
        -- shows and hides the HIGHLIGHT layer on mouseover by itself, and a
        -- colour fill cannot silently turn out not to exist on this client.
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        local highlight = button.highlight
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.2)

        -- Below the icon and label, above the list's own backing. Gold
        -- rather than white so it reads as a selection and not as the
        -- mouseover highlight above, which the cursor may be sitting on at
        -- the same moment.
        button.selected = button:CreateTexture(nil, "BACKGROUND")
        button.selected:SetAllPoints()
        button.selected:SetColorTexture(1, 0.82, 0, 0.3)
        button.selected:Hide()

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

    -- Closing on a click elsewhere, using the panel that is already behind
    -- the list rather than a frame stretched over the screen to catch one.
    --
    -- A covering frame has to be above everything to see a click and below
    -- the list so as not to take one, and there is no arrangement of strata
    -- and level that is obviously both. Getting it wrong left the list
    -- taking no clicks at all -- no hover either, since a frame the cursor
    -- cannot reach has no mouseover. The panel cannot have that problem: it
    -- is the list's own ancestor, so the list is always above it.
    --
    -- The cost is that a click outside the settings window no longer closes
    -- the list. There is nothing outside the settings window to click while
    -- it is open.
    panel:EnableMouse(true)
    panel:SetScript("OnMouseDown", function()
        picker:Hide()
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
    picker.entries = pickerEntries(slot)
    picker.offset = 0
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -2)
    refreshPicker()
    picker:Show()
end

Panel.OpenPicker = openPicker

--- One row per slot: the spell's icon, its name, and a Pick button that
-- opens the list above.
--
-- Nothing here is typed into any more. That costs the one thing typing could
-- do that picking cannot -- setting up a spell not yet learned, the Remove
-- Curse a druid gets at 24 -- and buys a panel where a slot cannot be
-- spelled wrong.
local function addSpellTable(setting, y, x)
    local rows = setting.rows or 8
    local slotRows = {}
    local picks = {}
    local numbers = {}

    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", x, y)
    heading:SetText(setting.name)

    for index = 1, rows do
        local top = y - ROW_HEIGHT - (index - 1) * BOX_HEIGHT

        local number = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        number:SetPoint("TOPLEFT", x, top - 4)
        number:SetText(tostring(index))
        numbers[index] = number

        -- The spell's own icon and name, not an edit box. Picking is the
        -- only way into a slot now, so there is nothing left to type into --
        -- and an icon says which spell a slot holds faster than its name
        -- does, which is the same reason the buttons themselves show icons.
        local slotRow = CreateFrame("Frame", nil, panel)
        slotRow:SetPoint("TOPLEFT", x + 20, top)
        slotRow:SetSize(180, BOX_HEIGHT - 4)

        slotRow.icon = slotRow:CreateTexture(nil, "ARTWORK")
        slotRow.icon:SetSize(BOX_HEIGHT - 6, BOX_HEIGHT - 6)
        slotRow.icon:SetPoint("LEFT")
        -- The same border crop the buttons use, so the two show the same art.
        slotRow.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        slotRow.label = slotRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        slotRow.label:SetPoint("LEFT", slotRow.icon, "RIGHT", 6, 0)
        slotRow.label:SetJustifyH("LEFT")

        local pick = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        pick:SetSize(46, BOX_HEIGHT - 4)
        pick:SetPoint("LEFT", slotRow, "RIGHT", 6, 0)
        pick:SetText("Pick")
        pick:SetScript("OnClick", function()
            openPicker(index, slotRow)
        end)

        slotRows[index] = slotRow
        picks[index] = pick
    end

    return {
        setting = setting,
        widget = slotRows[1],
        slotRows = slotRows,
        picks = picks,
        height = ROW_HEIGHT + rows * BOX_HEIGHT,
        Refresh = function()
            local count = ns.Slots.Count()

            for index = 1, rows do
                local spell = ns.Slots.Spell(index)
                local slotRow = slotRows[index]

                -- A slot past the button count has nowhere to appear on the
                -- bar, so offering to fill it is offering nothing. Hidden
                -- rather than greyed: the count is right there above, and a
                -- shorter list says what it means.
                local inUse = index <= count
                slotRow:SetShown(inUse)
                picks[index]:SetShown(inUse)
                numbers[index]:SetShown(inUse)

                slotRow.label:SetText(spell or "")

                local texture = spell and ns.Spells.Texture(spell)
                if texture then
                    slotRow.icon:SetTexture(texture)
                    slotRow.icon:Show()
                else
                    slotRow.icon:Hide()
                end
            end
        end,
    }
end

-- Guards against a refresh that starts another. A slider's Refresh sets its
-- own value, the client answers that with OnValueChanged, and that runs the
-- setting's onChange -- which for the button count has to refresh the panel,
-- since changing it shows and hides whole rows. Without this the two would
-- call each other until the stack ran out.
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
