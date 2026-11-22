local addonName, ns = ...

-- BiteTime's page in the game's options window: what it does, a box for the
-- buttons' glow and one for the icon, the share of a Bite's tooltip damage
-- it counts, a button to try the glow, and where the Bite sits on the bars.
-- Laid out as RareMob's: the rows hang under the description.

local PADDING = 16
local LOGO_SIZE = 24
local ROW_HEIGHT = 30
local PANEL_WIDTH = 560
local COLUMN = 30 -- a checkbox and the gap before its label
-- The description paragraph: where its top sits on the page, the clear space
-- under it before the first row.
local HINT_TOP = PADDING + 30
local HINT_GAP = 16

local SWITCHES = {
    { key = "buttons", label = "Glow on your Ferocious Bite buttons" },
    { key = "center", label = "Show the Bite icon above the middle of the screen" },
}

-- The share slider's reach, in percent.
local SHARE_MIN, SHARE_MAX, SHARE_STEP = 50, 100, 5

local Panel = {}
ns.SettingsPanel = Panel
Panel.checks, Panel.labels = {}, {}

local panel, category, built, hint
local rows = {} -- in page order: { height, frames }

--- Stack the rows top to bottom, hanging off the bottom of the hint rather
-- than a fixed height on the page: the hint wraps to however many lines the
-- font needs. Frames keep their x from the page's left edge (btX); the hint
-- sits at PADDING, so that is taken off.
local function layout()
    local y = -HINT_GAP
    for _, row in ipairs(rows) do
        for _, frame in ipairs(row.frames) do
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", frame.btX - PADDING, y + frame.btY)
        end
        y = y - row.height
    end
end

local function place(frame, x, y)
    frame.btX, frame.btY = x, y or 0
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

local DESCRIPTION = "Lights up your Ferocious Bite when a Bite with the combo points and energy you have would "
    .. "kill your target: a pulsing border on every button that holds it, and its icon above the middle of the "
    .. "screen. Mobs only, in Cat Form. WoW Forever hides a mob's health from addons, so the game itself makes "
    .. "the comparison and the glow follows it; that is also why there is no sound. A Bite's damage is the "
    .. "lowest its tooltip gives, and armor takes some of that, so it is counted at the share below."

local function shareText(share)
    return string.format("Count a Bite at %d%% of its tooltip damage", share)
end

local function bitesLine()
    ns.Glow.Scan()
    local count = ns.Glow.Count()
    local name = ns.Bite.Name()
    if count > 0 then
        return string.format("%s is on %d of your action buttons.", name, count), 0.6, 0.9, 0.6
    end
    if ns.Bite.TopRank() then
        return string.format("%s is on none of your action buttons, so only the icon in the middle can light.",
            name), 1, 0.82, 0.3
    end
    return string.format("You have not learned %s yet.", name), 1, 0.35, 0.3
end

--- Show what is saved, and where the Bite sits. Safe to call before the
-- page is built.
function Panel.Refresh()
    if not built then
        return
    end
    for key, check in pairs(Panel.checks) do
        check:SetChecked(ns.settings[key])
    end
    local share = tonumber(ns.settings.share) or SHARE_MAX
    if Panel.share:GetValue() ~= share then
        Panel.share:SetValue(share)
    end
    Panel.shareLabel:SetText(shareText(share))

    local line, r, g, b = bitesLine()
    Panel.status:SetText(line)
    Panel.status:SetTextColor(r, g, b)
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
    title:SetText("BiteTime")

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
    hint:SetText(DESCRIPTION)
    Panel.hint = hint

    for _, switch in ipairs(SWITCHES) do
        local key = switch.key
        Panel.checks[key], Panel.labels[key] = checkbox(switch.label, function(value)
            ns.settings[key] = value
            ns.Refresh()
        end)
    end

    Panel.shareLabel = text(shareText(ns.settings.share), PADDING + 4, -4)
    table.insert(rows, { height = ROW_HEIGHT - 6, frames = { Panel.shareLabel } })

    local slider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    slider:SetMinMaxValues(SHARE_MIN, SHARE_MAX)
    slider:SetValueStep(SHARE_STEP)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(240)
    place(slider, PADDING + 8, -6)
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / SHARE_STEP + 0.5) * SHARE_STEP
        if ns.settings.share ~= value then
            ns.settings.share = value
            ns.Refresh()
        end
    end)
    Panel.share = slider
    table.insert(rows, { height = ROW_HEIGHT + 10, frames = { slider } })

    local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    test:SetSize(100, 22)
    test:SetText("Test")
    test:SetScript("OnClick", function()
        ns.Glow.Test()
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
    panel.name = "BiteTime"
    Panel.panel = panel

    panel:SetScript("OnShow", function()
        ensureBuilt()
        Panel.Refresh()
    end)

    category = Settings.RegisterCanvasLayoutCategory(panel, "BiteTime")
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
        ns.Print("This client has no settings panel. Use /bt help for commands.")
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
