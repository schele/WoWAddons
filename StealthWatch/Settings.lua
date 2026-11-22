local addonName, ns = ...

-- StealthWatch's page in the game's options window: what it does, a box per
-- alert, a button to try the alert, and whether enemy nameplates are on.
-- Laid out as RareMob's: the rows hang under the description.

local PADDING = 16
local LOGO_SIZE = 24
local ROW_HEIGHT = 30
local PANEL_WIDTH = 560
local COLUMN = 30 -- a checkbox and the gap before its label
-- The description paragraph: where its top sits on the page, the clear space
-- under it before the first row, and a generous guess at its height for a
-- client that will not measure it (five lines of GameFontHighlightSmall).
local HINT_TOP = PADDING + 30
local HINT_GAP = 16
local HINT_FALLBACK_HEIGHT = 70

local SWITCHES = {
    { key = "sound", label = "Play a warning sound" },
    { key = "screen", label = "Show a warning in the middle of the screen" },
    { key = "chat", label = "Print a line in chat" },
}

local Panel = {}
ns.SettingsPanel = Panel
Panel.checks, Panel.labels = {}, {}

local panel, category, built, hint
local rows = {} -- in page order: { height, frames }

--- Stack the rows top to bottom, hanging off the bottom of the hint rather
-- than a fixed height on the page: the hint wraps to however many lines the
-- font needs. Frames keep their x from the page's left edge (swX); the hint
-- sits at PADDING, so that is taken off.
local function layout()
    local y = -HINT_GAP
    for _, row in ipairs(rows) do
        for _, frame in ipairs(row.frames) do
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", frame.swX - PADDING, y + frame.swY)
        end
        y = y - row.height
    end
end

local function place(frame, x, y)
    frame.swX, frame.swY = x, y or 0
    return frame
end

local function text(label, x, y, font)
    local fontString = panel:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    fontString:SetText(label)
    return place(fontString, x, y)
end

local function checkbox(label, onClick)
    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    place(check, PADDING)
    check:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    local caption = text(label, PADDING + COLUMN, -6)
    table.insert(rows, { height = ROW_HEIGHT, frames = { check, caption } })
    return check, caption
end

local DESCRIPTION = "Warns you when an enemy player near you goes into stealth. It watches every enemy "
    .. "player with a nameplate, and your target. A stealth spell the game names sets it off, and so does "
    .. "someone who casts something instant and is gone a moment later: that is how stealth looks when the "
    .. "game hides which spell it was, as WoW Forever does for other players' casts. It sees only as far "
    .. "as enemy nameplates reach, so keep them on (V)."

--- Show what is saved, and whether enemy nameplates are on. Safe to call
-- before the page is built.
function Panel.Refresh()
    if not built then
        return
    end
    for key, check in pairs(Panel.checks) do
        check:SetChecked(ns.settings[key])
    end
    if ns.Watcher.EnemyPlatesShown() then
        Panel.status:SetText("Enemy nameplates are on.")
        Panel.status:SetTextColor(0.6, 0.9, 0.6)
    else
        Panel.status:SetText("Enemy nameplates are off, so StealthWatch only sees your target. Press V to show them.")
        Panel.status:SetTextColor(1, 0.35, 0.3)
    end
end

local function ensureBuilt()
    if built or not panel then
        return
    end
    built = true

    -- logo, not icon: icon.tga carries the square tile the AddOns list needs.
    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("TOPLEFT", PADDING, -PADDING)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\logo")
    Panel.logo = logo

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("StealthWatch")

    -- From the .toc, so the two cannot drift apart.
    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))
    Panel.version = version

    hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -HINT_TOP)
    hint:SetWidth(PANEL_WIDTH - PADDING * 2)
    hint:SetJustifyH("LEFT")
    -- Only the names the client gave: a spell it does not know is not shown.
    local known = ns.Watcher.KnownNames()
    local watching = #known > 0 and string.format(" Watching for: %s.", table.concat(known, ", ")) or ""
    hint:SetText(DESCRIPTION .. watching)
    Panel.hint = hint

    for _, switch in ipairs(SWITCHES) do
        local key = switch.key
        Panel.checks[key], Panel.labels[key] = checkbox(switch.label, function(value)
            ns.settings[key] = value
            ns.Refresh()
        end)
    end

    local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    test:SetSize(100, 22)
    test:SetText("Test")
    test:SetScript("OnClick", function()
        ns.Alert.Test()
    end)
    place(test, PADDING + 4, -6)
    Panel.test = test
    table.insert(rows, { height = ROW_HEIGHT + 10, frames = { test } })

    Panel.status = text("", PADDING + 4, -4, "GameFontHighlightSmall")
    table.insert(rows, { height = ROW_HEIGHT, frames = { Panel.status } })

    Panel.Refresh()
    layout()
end

--- Claim a place in the game's options, without building anything yet.
local function register()
    -- Parented and hidden: the Settings system shows it when the category is
    -- opened, and that is when it gets filled.
    panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel.name = "StealthWatch"
    Panel.panel = panel

    panel:SetScript("OnShow", function()
        ensureBuilt()
        Panel.Refresh()
    end)

    category = Settings.RegisterCanvasLayoutCategory(panel, "StealthWatch")
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
        ns.Print("This client has no settings panel. Use /sw help for commands.")
        return
    end
    watchForClose()
    openedByUs = true
    ensureBuilt()
    Settings.OpenToCategory(category:GetID())
    Panel.Refresh()
end

ns.DefaultCommand = ns.OpenSettings

ns.RegisterCommand("settings", "Open the settings page", function()
    ns.OpenSettings()
end)

ns.OnRefresh(Panel.Refresh)

ns.OnLogin(function()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        register()
    end
end)
