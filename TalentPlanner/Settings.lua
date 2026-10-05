local addonName, ns = ...

-- TalentPlanner's page in the game's options window: its four switches, as
-- checkboxes.

local PADDING = 16
-- Big enough to read as a logo beside a GameFontNormalLarge title without
-- crowding the line below it.
local LOGO_SIZE = 24
local ROW_HEIGHT = 30
local PANEL_WIDTH = 400
-- Clear space between the description paragraph and the first row under it.
local HINT_GAP = 16

local Panel = {}
ns.SettingsPanel = Panel

local panel, category, built

local function addCheckbox(text, y, onClick)
    local button = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", Panel.hint, "BOTTOMLEFT", 0, y)

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

--- Show what is saved. Safe to call before the page is built: every setter
-- calls it, from a command as much as from here.
function Panel.Refresh()
    if not built then
        return
    end
    Panel.remind:SetChecked(ns.db.remind)
    Panel.overlay:SetChecked(ns.db.overlay)
    Panel.learn:SetChecked(ns.db.learn)
    Panel.minimap:SetChecked(not ns.db.minimap.hide)
end

local function ensureBuilt()
    if built or not panel then
        return
    end
    built = true

    -- The minimap icon, not the AddOns list one: that carries a square tile,
    -- which on a dark panel reads as a sticker pasted on.
    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("TOPLEFT", PADDING, -PADDING)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\minimap")
    Panel.logo = logo

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("TalentPlanner")

    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -PADDING - ROW_HEIGHT)
    hint:SetWidth(PANEL_WIDTH - PADDING * 2)
    hint:SetJustifyH("LEFT")
    hint:SetText(
        "Plan the order your talent points go in with /tp or the minimap button. "
        .. "TalentPlanner shows the plan in the game's talent window and names the "
        .. "next talent when a point is free. Learn next spends the point for you, "
        .. "never in combat."
    )

    -- Rows hang off the bottom of the hint rather than a fixed height on the
    -- panel, so a hint that wraps to another line never crowds the first.
    Panel.hint = hint
    local y = -HINT_GAP

    Panel.remind = addCheckbox("Remind me when a point is free", y, function(value)
        ns.SetSetting("remind", value)
    end)
    y = y - ROW_HEIGHT

    Panel.overlay = addCheckbox("Show the plan in the talent window", y, function(value)
        ns.SetSetting("overlay", value)
    end)
    y = y - ROW_HEIGHT

    Panel.learn = addCheckbox("Show the Learn next button", y, function(value)
        ns.SetSetting("learn", value)
    end)
    y = y - ROW_HEIGHT

    -- Stored as "hide", shown as "Show": the box is ticked while it shows.
    Panel.minimap = addCheckbox("Show the minimap button", y, function(value)
        ns.MinimapButton.SetHidden(not value)
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
    panel.name = "TalentPlanner"
    Panel.panel = panel

    panel:SetScript("OnShow", function()
        ensureBuilt()
        Panel.Refresh()
    end)

    category = Settings.RegisterCanvasLayoutCategory(panel, "TalentPlanner")
    Settings.RegisterAddOnCategory(category)
end

-- Whether the page on screen was opened from here rather than through the
-- game menu. Decides where closing it should leave the player.
local openedByUs = false

-- Armed while the client is closing a page we opened, so the game menu it
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
        -- Opening the page from a command leaves the client queued to fall
        -- back to the game menu, which is not where the player came from.
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

--- Open the page in the game's options window.
function ns.OpenSettings()
    if not category then
        ns.Print("This client has no settings panel. Use /tp for commands.")
        return
    end

    watchForClose()
    openedByUs = true

    -- Build before showing, in case the client opens the category without
    -- firing OnShow on our canvas.
    ensureBuilt()

    Settings.OpenToCategory(category:GetID())
    Panel.Refresh()
end

--- Close the options window if it is showing this page; otherwise open it
-- here, which also turns it over from another addon's page. Both shown is the
-- test: the window keeps this frame hidden while any other page is up.
function ns.ToggleSettings()
    if panel and panel:IsShown() and SettingsPanel and SettingsPanel:IsShown() then
        if HideUIPanel then
            HideUIPanel(SettingsPanel)
        else
            SettingsPanel:Hide()
        end
        return
    end
    ns.OpenSettings()
end

ns.RegisterCommand("settings", "Open the settings page", function()
    ns.OpenSettings()
end)

ns.OnLogin(function()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        register()
    end
end)
