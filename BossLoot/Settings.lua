local addonName, ns = ...

-- BossLoot's page in the game's options window, so it is listed with every
-- other addon there: a way into the loot window, and the few switches the
-- slash commands have.

local PADDING = 16
local LOGO_SIZE = 24
local ROW_HEIGHT = 30
local PANEL_WIDTH = 400

local Panel = {}
ns.SettingsPanel = Panel

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

local function closeOptions()
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

local function addCheckbox(text, y, onClick)
    local button = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", PADDING, y)

    -- The label belongs to the template on some clients and not others, so
    -- write our own rather than reaching for button.Text and finding nil.
    local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", button, "RIGHT", 4, 0)
    label:SetText(text)

    button:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    return button
end

local function addButton(text, width, y, onClick)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", PADDING + 4, y)
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function hiddenLabel()
    local count = ns.Window.HiddenCount()
    if count == 0 then
        return "No hidden instances"
    end
    return string.format("Bring back %d hidden instance%s", count, count == 1 and "" or "s")
end

--- Show what is saved. Safe before the page is built.
function Panel.Refresh()
    if not built then
        return
    end
    Panel.minimap:SetChecked(not ns.db.minimap.hide)
    Panel.debug:SetChecked(ns.db.debug)
    Panel.unhide:SetText(hiddenLabel())
end

local function ensureBuilt()
    if built or not panel then
        return
    end
    built = true

    -- The chest alone, as the minimap button shows it: the AddOns list icon
    -- carries a square tile that reads as a sticker on a dark panel.
    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("TOPLEFT", PADDING, -PADDING)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\minimap")
    Panel.logo = logo

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("BossLoot")

    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -PADDING - ROW_HEIGHT)
    hint:SetWidth(PANEL_WIDTH - PADDING * 2)
    hint:SetJustifyH("LEFT")
    hint:SetText(
        "What every boss drops, in every dungeon and raid, from anywhere. Open it "
        .. "from the minimap button or with /bl."
    )

    local y = -PADDING - ROW_HEIGHT * 2 - 8

    Panel.open = addButton("Open BossLoot", 160, y, function()
        closeOptions()
        ns.Window.Open()
    end)
    y = y - ROW_HEIGHT - 6

    Panel.minimap = addCheckbox("Show the minimap button", y, function(value)
        ns.MinimapButton.SetHidden(not value)
    end)
    y = y - ROW_HEIGHT

    Panel.debug = addCheckbox("Show item loading details, for testing", y, function(value)
        ns.Window.SetDebug(value)
    end)
    y = y - ROW_HEIGHT - 6

    -- Hiding is a right-click on the list, easily done and easily forgotten.
    Panel.unhide = addButton(hiddenLabel(), 240, y, function()
        ns.Window.UnhideAll()
        Panel.Refresh()
    end)

    Panel.Refresh()
end

--- Claim a place in the game's options, without building anything yet.
local function register()
    -- Parented and hidden. Left parentless and shown, as the canvas examples
    -- suggest, the frame is live on screen from login. The Settings system
    -- shows it when the category is opened, and that is when it gets filled.
    panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel.name = "BossLoot"
    Panel.panel = panel

    panel:SetScript("OnShow", function()
        ensureBuilt()
        Panel.Refresh()
    end)

    category = Settings.RegisterCanvasLayoutCategory(panel, "BossLoot")
    Settings.RegisterAddOnCategory(category)
end

--- Open the page in the game's options window.
function ns.OpenSettings()
    if not category then
        ns.Print("This client has no settings panel. Use /bl for commands.")
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
