local addonName, ns = ...

-- RareMob's page in the game's options window: a box per switch, the pin
-- size, and the minimap button. Laid out as GatherMap's: the rows hang under
-- the description, and the page scrolls only when it has to.

local PADDING = 16
local LOGO_SIZE = 24
local ROW_HEIGHT = 30
local PANEL_WIDTH = 560
local COLUMN = 30 -- a checkbox and the gap before its label
-- The description paragraph: where its top sits on the page, the clear space
-- under it before the first row, and a generous guess at its height for a
-- client that will not measure it (three lines of GameFontHighlightSmall).
local HINT_TOP = PADDING + 30
local HINT_GAP = 16
local HINT_FALLBACK_HEIGHT = 42

local SWITCHES = {
    { key = "worldPins", label = "Show pins on the world map" },
    { key = "minimapPins", label = "Show pins on the minimap" },
    { key = "showUnseen", label = "Show rares only in the database" },
    { key = "alert", label = "Alert sound" },
}

local Panel = {}
ns.SettingsPanel = Panel
Panel.checks, Panel.labels = {}, {}

local panel, category, built, content, hint
local rows = {} -- in page order: { height, frames }

--- Stack the rows top to bottom, hanging off the bottom of the hint rather
-- than a fixed height on the page: the hint wraps to however many lines the
-- font needs. Frames keep their x from the page's left edge (rmX); the hint
-- sits at PADDING, so that is taken off.
local function layout()
    local y = -HINT_GAP
    for _, row in ipairs(rows) do
        for _, frame in ipairs(row.frames) do
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", frame.rmX - PADDING, y + frame.rmY)
        end
        y = y - row.height
    end
    -- The scroll child's height, measured rather than assumed, so a hint
    -- that wraps further cannot push the last row out of reach.
    local hintHeight = hint.GetStringHeight and hint:GetStringHeight() or 0
    if not hintHeight or hintHeight < 1 then
        hintHeight = HINT_FALLBACK_HEIGHT
    end
    content:SetHeight(HINT_TOP + hintHeight - y + PADDING)
    if Panel.fitScrollBar then
        Panel.fitScrollBar()
    end
end

local function place(frame, x, y)
    frame.rmX, frame.rmY = x, y or 0
    return frame
end

local function text(label, x, y)
    local fontString = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fontString:SetText(label)
    return place(fontString, x, y)
end

local function checkbox(label, onClick)
    local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    place(check, PADDING)
    check:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    local caption = text(label, PADDING + COLUMN, -6)
    table.insert(rows, { height = ROW_HEIGHT, frames = { check, caption } })
    return check, caption
end

--- Show what is saved. Safe to call before the page is built.
function Panel.Refresh()
    if not built then
        return
    end
    for key, check in pairs(Panel.checks) do
        check:SetChecked(ns.settings[key])
    end
    Panel.size:SetValue(ns.settings.pinSize)
    Panel.minimap:SetChecked(not ns.settings.button.hide)
end

local function ensureBuilt()
    if built or not panel then
        return
    end
    built = true

    local scroll = ns.Guarded(function()
        return CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    end)
    if scroll then
        -- Room on the right for the template's scroll bar.
        scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 4)
        -- The bar only while there is something to scroll. The template's own
        -- scrollBarHideable is not honoured on every client, so this runs
        -- after its handler, which shows the bar greyed out.
        local function fitScrollBar()
            local bar = scroll.ScrollBar
            if bar and scroll.GetVerticalScrollRange then
                local needed = (scroll:GetVerticalScrollRange() or 0) > 0
                bar:SetShown(needed)
                if not needed and scroll.SetVerticalScroll then
                    scroll:SetVerticalScroll(0)
                end
            end
        end
        scroll:HookScript("OnScrollRangeChanged", fitScrollBar)
        scroll:HookScript("OnShow", fitScrollBar)
        Panel.fitScrollBar = fitScrollBar
        Panel.scroll = scroll
        content = CreateFrame("Frame", nil, scroll)
        content:SetSize(PANEL_WIDTH, 1)
        scroll:SetScrollChild(content)
    else
        content = panel
    end

    -- The minimap icon, not the AddOns list one: that carries a square tile.
    local logo = content:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("TOPLEFT", PADDING, -PADDING)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\minimap")
    Panel.logo = logo

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("RareMob")

    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))

    hint = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -HINT_TOP)
    hint:SetWidth(PANEL_WIDTH - PADDING * 2)
    hint:SetJustifyH("LEFT")
    hint:SetText("Skull pins mark where rares and rare elites spawn. Bright: seen on WoW Forever. "
        .. "Dimmed: only in the classic database. A gold edge: you saw it yourself. "
        .. "A rare near you makes its pins pulse and, unless you are resting, sounds the raid warning.")
    Panel.hint = hint

    for _, switch in ipairs(SWITCHES) do
        local key = switch.key
        Panel.checks[key], Panel.labels[key] = checkbox(switch.label, function(value)
            ns.settings[key] = value
            ns.Refresh()
        end)
    end

    local caption = text("Pin size", PADDING + 4, -4)
    local slider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    slider:SetMinMaxValues(8, 24)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(200)
    place(slider, PADDING + 110, -6)
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if ns.settings.pinSize ~= value then
            ns.settings.pinSize = value
            ns.Refresh()
        end
    end)
    Panel.size = slider
    table.insert(rows, { height = ROW_HEIGHT + 10, frames = { slider, caption } })

    -- Stored as "hide", shown as "Show": the box is ticked while it shows.
    Panel.minimap, Panel.minimapLabel = checkbox("Show the minimap button", function(value)
        ns.MinimapButton.SetHidden(not value)
    end)

    Panel.Refresh()
    layout()
end

--- Claim a place in the game's options, without building anything yet.
local function register()
    -- Parented and hidden: the Settings system shows it when the category is
    -- opened, and that is when it gets filled.
    panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel.name = "RareMob"
    Panel.panel = panel

    panel:SetScript("OnShow", function()
        ensureBuilt()
        Panel.Refresh()
    end)

    category = Settings.RegisterCanvasLayoutCategory(panel, "RareMob")
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
        ns.Print("This client has no settings panel. Use /rm help for commands.")
        return
    end
    watchForClose()
    openedByUs = true
    ensureBuilt()
    Settings.OpenToCategory(category:GetID())
    Panel.Refresh()
end

--- Close the options window if it is showing this page; otherwise open it here.
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

-- Whatever else changes a setting (a command, the minimap button) is shown
-- on the page too.
ns.OnRefresh(Panel.Refresh)

ns.OnLogin(function()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        register()
    end
end)
