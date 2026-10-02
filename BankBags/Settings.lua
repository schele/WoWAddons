local addonName, ns = ...

-- BankBags' page in the game's options window, so it is listed with every
-- other addon there: a way into the bank window, the minimap switch, and the
-- saved banks, each with a way to forget it.

local PADDING = 16
local LOGO_SIZE = 24
local ROW_HEIGHT = 30
local PANEL_WIDTH = 400
local MAX_ROWS = 10 -- saved banks listed; the rest are counted

local Panel = {}
ns.SettingsPanel = Panel
Panel.rows = {}

local panel, category, built

-- Whether the options on screen were opened from here rather than through the
-- game menu, or are being closed from here for the window. Either way,
-- closing them should not bring the game menu back.
local openedByUs = false

-- Armed while the client is closing options we opened, so the game menu it
-- puts up on the way out can be turned away at the door.
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
        if not openedByUs then
            return
        end
        openedByUs = false
        suppressGameMenu = true

        -- Backstop, in case the menu is already up or has no OnShow to catch.
        C_Timer.After(0, function()
            if suppressGameMenu then
                if GameMenuFrame and GameMenuFrame:IsShown() then
                    dismissGameMenu(GameMenuFrame)
                end
                suppressGameMenu = false
            end
        end)
    end)

    -- Caught as it shows, so it never reaches the screen.
    if GameMenuFrame and GameMenuFrame.HookScript then
        GameMenuFrame:HookScript("OnShow", function(self)
            if suppressGameMenu then
                dismissGameMenu(self)
            end
        end)
    end
end

--- Close the options window, and the game menu it may have come from. The
-- bank window calls this as it opens: one window at a time.
function ns.CloseOptions()
    if not (SettingsPanel and SettingsPanel:IsShown()) then
        return
    end
    watchForClose()
    openedByUs = true
    if HideUIPanel then
        HideUIPanel(SettingsPanel)
    else
        SettingsPanel:Hide()
    end
end

-- Clear space under the description paragraph, and under the "Saved banks"
-- heading. Everything below hangs off those two rather than a fixed height on
-- the panel, so a paragraph that wraps to another line pushes the rows down
-- instead of crowding them.
local HINT_GAP = 16
local HEADING_GAP = 10

local function row(index)
    local made = Panel.rows[index]
    if made then
        return made
    end
    made = CreateFrame("Frame", nil, panel)
    made:SetSize(PANEL_WIDTH - PADDING * 2, ROW_HEIGHT - 4)
    made:SetPoint("TOPLEFT", Panel.heading, "BOTTOMLEFT", 4,
        -HEADING_GAP - (index - 1) * (ROW_HEIGHT - 4))

    made.forget = CreateFrame("Button", nil, made, "UIPanelButtonTemplate")
    made.forget:SetSize(70, 20)
    made.forget:SetPoint("LEFT", made, "LEFT", 0, 0)
    made.forget:SetText("Forget")
    made.forget:SetScript("OnClick", function()
        if made.key then
            ns.Bank.ForgetKey(made.key)
        end
    end)

    made.label = made:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    made.label:SetPoint("LEFT", made.forget, "RIGHT", 10, 0)

    Panel.rows[index] = made
    return made
end

local function refreshBanks()
    local keys = ns.Bank.Characters()
    local now = time and time() or 0
    for index, key in ipairs(keys) do
        if index > MAX_ROWS then
            break
        end
        local character = ns.Bank.Get(key)
        local made = row(index)
        made.key = key
        made.label:SetText(ns.Window.CharacterLabel(key, character)
            .. "  |cff808080" .. ns.Window.SavedText(now - (character.saved or now)) .. "|r")
        made:Show()
    end
    for index = #keys + 1, #Panel.rows do
        Panel.rows[index].key = nil
        Panel.rows[index]:Hide()
    end

    Panel.none:SetShown(#keys == 0)
    local more = #keys - MAX_ROWS
    Panel.more:SetShown(more > 0)
    if more > 0 then
        Panel.more:SetText(string.format("And %d more: /bb forget <name>", more))
    end
end

--- Show what is saved. Safe before the page is built.
function Panel.Refresh()
    if not built then
        return
    end
    Panel.minimap:SetChecked(not ns.db.minimap.hide)
    refreshBanks()
end

local function ensureBuilt()
    if built or not panel then
        return
    end
    built = true

    -- The sack alone, as the minimap button shows it: the AddOns list icon
    -- carries a square tile that reads as a sticker on a dark panel.
    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("TOPLEFT", PADDING, -PADDING)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\minimap")
    Panel.logo = logo

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("BankBags")

    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -PADDING - ROW_HEIGHT)
    hint:SetWidth(PANEL_WIDTH - PADDING * 2)
    hint:SetJustifyH("LEFT")
    hint:SetText(
        "Your bank, from anywhere. A character's bank is saved each time they "
        .. "visit a banker. Open it from the minimap button or with /bb."
    )

    Panel.hint = hint

    -- Measured down from the hint's bottom edge.
    local y = -HINT_GAP

    Panel.open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    Panel.open:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 4, y)
    Panel.open:SetSize(160, 22)
    Panel.open:SetText("Open BankBags")
    -- Opening closes the options over it.
    Panel.open:SetScript("OnClick", function()
        ns.Window.Open()
    end)
    y = y - ROW_HEIGHT - 6

    Panel.minimap = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    Panel.minimap:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, y)
    -- The label belongs to the template on some clients and not others, so
    -- write our own rather than reaching for button.Text and finding nil.
    local minimapLabel = Panel.minimap:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    minimapLabel:SetPoint("LEFT", Panel.minimap, "RIGHT", 4, 0)
    minimapLabel:SetText("Show the minimap button")
    Panel.minimap:SetScript("OnClick", function(self)
        ns.MinimapButton.SetHidden(not self:GetChecked())
    end)
    y = y - ROW_HEIGHT - 6

    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, y)
    heading:SetText("Saved banks")
    Panel.heading = heading

    Panel.none = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    Panel.none:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 4, -HEADING_GAP - 4)
    Panel.none:SetText("None yet. Visit a banker on each character to save their bank.")

    Panel.more = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    Panel.more:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 4,
        -HEADING_GAP - MAX_ROWS * (ROW_HEIGHT - 4) - 4)

    Panel.Refresh()
end

--- Claim a place in the game's options, without building anything yet.
local function register()
    -- Parented and hidden. Left parentless and shown, as the canvas examples
    -- suggest, the frame is live on screen from login. The Settings system
    -- shows it when the category is opened, and that is when it gets filled.
    panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel.name = "BankBags"
    Panel.panel = panel

    panel:SetScript("OnShow", function()
        ensureBuilt()
        Panel.Refresh()
    end)

    category = Settings.RegisterCanvasLayoutCategory(panel, "BankBags")
    Settings.RegisterAddOnCategory(category)
end

--- Open the page in the game's options window.
function ns.OpenSettings()
    if not category then
        ns.Print("This client has no settings panel. Use /bb for commands.")
        return
    end
    watchForClose()
    openedByUs = true
    ensureBuilt()
    Settings.OpenToCategory(category:GetID())
    Panel.Refresh()
end

ns.RegisterCommand("settings", "Open the settings page", function()
    ns.OpenSettings()
end)

ns.OnLogin(function()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        register()
    end
end)
