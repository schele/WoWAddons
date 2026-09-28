local addonName, ns = ...

-- GatherMap's page in the game's options window. Every filter has two
-- checkboxes, one for the world map and one for the minimap; each kind folds
-- open into a checklist of its nodes.

local PADDING = 16
local LOGO_SIZE = 24
local ROW_HEIGHT = 26
local PANEL_WIDTH = 560
local COLUMN = 30 -- one checkbox column
local LABEL_X = PADDING + COLUMN * 2 + 6
local WHERES = { "worldmap", "minimap" }
local KINDS = { "herb", "ore" }
local KIND_LABEL = { herb = "Herbs", ore = "Ore" }

local Panel = {}
ns.SettingsPanel = Panel
Panel.kinds, Panel.nodes, Panel.filters, Panel.sizes = {}, {}, {}, {}

local panel, category, built, content
local rows = {}   -- in page order: { height, frames, visible }
local pairs_ = {} -- every checkbox pair, for Refresh
local expanded = {}
local startY

--- Every node name of `kind` once, by required skill, then name.
function Panel.NodeNames(kind)
    local seen, names = {}, {}
    local function take(node)
        if node.kind == kind and node.name and not seen[node.name] then
            seen[node.name] = true
            table.insert(names, { name = node.name, skill = node.skill })
        end
    end
    for _, node in pairs(ns.Nodes) do
        take(node)
    end
    for _, continent in ipairs({ 0, 1 }) do
        for _, spawn in ipairs(ns.Spawns.All(continent)) do
            take(ns.Spawns.Node(spawn))
        end
    end
    table.sort(names, function(a, b)
        if (a.skill or 0) ~= (b.skill or 0) then
            return (a.skill or 0) < (b.skill or 0)
        end
        return a.name < b.name
    end)
    return names
end

--- Stack the rows that are showing, top to bottom.
local function layout()
    local y = startY
    for _, row in ipairs(rows) do
        local show = not row.visible or row.visible()
        for _, frame in ipairs(row.frames) do
            frame:SetShown(show)
            if show then
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", content, "TOPLEFT", frame.gmX, y + frame.gmY)
            end
        end
        if show then
            y = y - row.height
        end
    end
    content:SetHeight(-y + PADDING)
end

local function place(frame, x, y)
    frame.gmX, frame.gmY = x, y or 0
    return frame
end

local function text(label, x, y, font)
    local fontString = content:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    fontString:SetText(label)
    return place(fontString, x, y)
end

local function button(label, width, x)
    local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetText(label)
    return place(b, x, -2)
end

--- A row with a checkbox per map. `get(where)` reads, `set(where, value)`
-- writes; `visible` folds the row away when it returns false.
local function checkPair(label, get, set, indent, visible)
    local pair = { get = get, buttons = {} }
    local frames = {}
    for index, where in ipairs(WHERES) do
        local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        place(check, PADDING + COLUMN * (index - 1))
        check:SetScript("OnClick", function(self)
            set(where, self:GetChecked() and true or false)
            ns.Refresh()
            Panel.Refresh()
        end)
        pair.buttons[where] = check
        table.insert(frames, check)
    end
    pair.label = text(label, LABEL_X + (indent or 0), -5)
    table.insert(frames, pair.label)
    pair.frames = frames
    table.insert(pairs_, pair)
    table.insert(rows, { height = ROW_HEIGHT, frames = frames, visible = visible })
    return pair
end

local function addKind(kind)
    local pair = checkPair(KIND_LABEL[kind],
        function(where) return ns.settings[where].kinds[kind] end,
        function(where, value) ns.settings[where].kinds[kind] = value end)
    Panel.kinds[kind] = pair

    local names = Panel.NodeNames(kind)
    local function setAll(hidden)
        for _, where in ipairs(WHERES) do
            for _, node in ipairs(names) do
                ns.settings[where].hidden[node.name] = hidden or nil
            end
        end
        ns.Refresh()
        Panel.Refresh()
    end

    pair.toggle = button("+", 24, LABEL_X + 110)
    pair.toggle:SetScript("OnClick", function()
        expanded[kind] = not expanded[kind]
        Panel.Refresh()
        layout()
    end)
    pair.all = button("All", 44, LABEL_X + 140)
    pair.all:SetScript("OnClick", function() setAll(false) end)
    pair.none = button("None", 50, LABEL_X + 188)
    pair.none:SetScript("OnClick", function() setAll(true) end)
    table.insert(pair.frames, pair.toggle)
    table.insert(pair.frames, pair.all)
    table.insert(pair.frames, pair.none)

    for _, node in ipairs(names) do
        local label = node.skill and string.format("%s (%d)", node.name, node.skill) or node.name
        Panel.nodes[node.name] = checkPair(label,
            function(where) return not ns.settings[where].hidden[node.name] end,
            function(where, value) ns.settings[where].hidden[node.name] = (not value) or nil end,
            20, function() return expanded[kind] end)
    end
end

local function addFilter(key, label)
    Panel.filters[key] = checkPair(label,
        function(where) return ns.settings[where][key] end,
        function(where, value) ns.settings[where][key] = value end)
end

local function addSize(where, label, low, high)
    local caption = text(label, PADDING, -4)
    local slider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(200)
    place(slider, PADDING + 170, -4)
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if ns.settings[where].pinSize ~= value then
            ns.settings[where].pinSize = value
            ns.Refresh()
        end
    end)
    Panel.sizes[where] = slider
    table.insert(rows, { height = ROW_HEIGHT + 10, frames = { caption, slider } })
end

--- Show what is saved. Safe to call before the page is built.
function Panel.Refresh()
    if not built then
        return
    end
    Panel.enabled:SetChecked(ns.settings.enabled)
    for _, pair in ipairs(pairs_) do
        for where, check in pairs(pair.buttons) do
            check:SetChecked(pair.get(where))
        end
    end
    for kind, pair in pairs(Panel.kinds) do
        pair.toggle:SetText(expanded[kind] and "-" or "+")
    end
    for where, slider in pairs(Panel.sizes) do
        slider:SetValue(ns.settings[where].pinSize)
    end
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
    title:SetText("GatherMap")

    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))

    local hint = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -PADDING - 30)
    hint:SetWidth(PANEL_WIDTH - PADDING * 2)
    hint:SetJustifyH("LEFT")
    hint:SetText("Each row has two boxes: the world map, then the minimap. "
        .. "Open a kind with + to pick its nodes one by one. Pins are the places you "
        .. "have mined or herbed; Shift-right-click a pin to forget it.")

    startY = -PADDING - 84 -- below the title and the three-line hint

    local enabled = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    place(enabled, PADDING)
    enabled:SetScript("OnClick", function(self)
        ns.SetEnabled(self:GetChecked() and true or false)
    end)
    Panel.enabled = enabled
    table.insert(rows, { height = ROW_HEIGHT + 6, frames = { enabled, text("Show pins", PADDING + COLUMN, -5) } })

    table.insert(rows, { height = 18, frames = {
        text("Map", PADDING, 0, "GameFontNormalSmall"),
        text("Mini", PADDING + COLUMN, 0, "GameFontNormalSmall"),
    } })

    for _, kind in ipairs(KINDS) do
        addKind(kind)
    end
    addFilter("hideUngatherable", "Hide nodes my skill cannot gather yet")
    addFilter("hideGrey", "Hide grey nodes (no skill-ups left)")
    addSize("worldmap", "World map pin size", 8, 24)
    addSize("minimap", "Minimap pin size", 6, 20)

    Panel.Refresh()
    layout()
end

--- Claim a place in the game's options, without building anything yet.
local function register()
    -- Parented and hidden: the Settings system shows it when the category is
    -- opened, and that is when it gets filled.
    panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel.name = "GatherMap"
    Panel.panel = panel

    panel:SetScript("OnShow", function()
        ensureBuilt()
        Panel.Refresh()
    end)

    category = Settings.RegisterCanvasLayoutCategory(panel, "GatherMap")
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
        ns.Print("This client has no settings panel. Use /gmap help for commands.")
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
