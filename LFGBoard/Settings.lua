local addonName, ns = ...

-- LFGBoard's page in the game's options window: the board's switches as
-- checkboxes, and a button that opens the board. Each box writes through the
-- same setter as the board's own, so the two stay in step.

local PADDING = 16
-- Big enough to read as a logo beside a GameFontNormalLarge title without
-- crowding the line below it.
local LOGO_SIZE = 24
local ROW_HEIGHT = 30
local PANEL_WIDTH = 400
local INDENT = 30 -- under a checkbox's label, not its box
local ROLE_WIDTH = 100 -- room for a role's box and its label, side by side
-- Between the hint's last line and what follows it, so however far the hint
-- wraps it never crowds the first row.
local HINT_GAP = 16
-- The empty edge round a UICheckButtonTemplate box, so text and buttons line
-- up with the box drawn rather than its frame.
local CHECK_MARGIN = 4

-- In the board's order and with its words.
local ROLES = {
    { key = "tank", label = "Tank" },
    { key = "healer", label = "Healer" },
    { key = "dps", label = "Damage" },
}

local Panel = {}
ns.SettingsPanel = Panel

local panel, category, built

--- A checkbox hung from the hint, x and y measured from its bottom left.
local function addCheckbox(text, x, y, onClick)
    local button = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", Panel.hint, "BOTTOMLEFT", x, y)

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

--- Show what is saved. Safe to call before the page is built: ns.Changed
-- calls it after every change, from the board or a command as much as here.
function Panel.Refresh()
    if not built then
        return
    end
    Panel.nearLevel:SetChecked(ns.db.nearLevel)
    Panel.alerts:SetChecked(ns.db.alerts)
    Panel.completed:SetChecked(ns.db.hideCompleted)
    Panel.minimap:SetChecked(not ns.db.minimap.hide)
    local roles = ns.Roles()
    for _, info in ipairs(ROLES) do
        Panel.roles[info.key]:SetChecked(roles[info.key])
    end
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
    title:SetText("LFGBoard")
    Panel.title = title

    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))
    Panel.version = version

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -PADDING - ROW_HEIGHT)
    hint:SetWidth(PANEL_WIDTH - PADDING * 2)
    hint:SetJustifyH("LEFT")
    hint:SetText(
        "The groups that want you, from chat and the group finder, on one "
        .. "board, filtered to the roles you play and the dungeons near your "
        .. "level. Open it with /lfgb or the minimap button."
    )
    Panel.hint = hint

    -- Everything below hangs from the hint's bottom edge, measured down from it.
    local y = -HINT_GAP

    Panel.nearLevel = addCheckbox("Only dungeons and raids near my level", 0, y, function(value)
        ns.Window.SetNearLevel(value)
    end)
    y = y - ROW_HEIGHT

    Panel.alerts = addCheckbox("Alert me when a group in chat wants one of my roles", 0, y, function(value)
        ns.Alerts.SetEnabled(value)
    end)
    y = y - ROW_HEIGHT

    -- Only a quest linked in chat can be checked; one named in words stays.
    Panel.completed = addCheckbox("Hide quests I have completed", 0, y, function(value)
        ns.Window.SetHideCompleted(value)
    end)
    y = y - ROW_HEIGHT

    -- Saved per character, so the page says whose they are.
    local rolesLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rolesLabel:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", CHECK_MARGIN, y - 6)
    rolesLabel:SetText("Roles this character plays")
    y = y - ROW_HEIGHT + 6

    Panel.roles = {}
    for index, info in ipairs(ROLES) do
        Panel.roles[info.key] = addCheckbox(info.label, INDENT + (index - 1) * ROLE_WIDTH, y, function(value)
            ns.SetRole(info.key, value)
        end)
    end
    y = y - ROW_HEIGHT

    -- Stored as "hide", shown as "Show": the box is ticked while it shows.
    Panel.minimap = addCheckbox("Show the minimap button", 0, y, function(value)
        ns.MinimapButton.SetHidden(not value)
    end)
    y = y - ROW_HEIGHT - 8

    local openBoard = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    -- In line with the boxes drawn, not their empty edge.
    openBoard:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", CHECK_MARGIN, y)
    openBoard:SetSize(140, 22)
    openBoard:SetText("Open the board")
    openBoard:SetScript("OnClick", function()
        ns.Window.Open()
    end)
    Panel.openBoard = openBoard

    Panel.Refresh()
end

--- Claim a place in the game's options, without building anything yet.
local function register()
    -- Parented and hidden. Left parentless and shown, as the canvas examples
    -- suggest, the frame is live on screen from login. The Settings system
    -- shows it when the category is opened, and that is when it gets filled.
    panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel.name = "LFGBoard"
    Panel.panel = panel

    panel:SetScript("OnShow", function()
        ensureBuilt()
        Panel.Refresh()
    end)

    category = Settings.RegisterCanvasLayoutCategory(panel, "LFGBoard")
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
        ns.Print("This client has no settings panel. Use /lfgb for commands.")
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

ns.RegisterCommand("settings", "open the settings page", function()
    ns.OpenSettings()
end)

ns.OnLogin(function()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        register()
    end
end)
