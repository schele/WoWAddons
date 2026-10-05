local addonName, ns = ...

-- The zone's rares: a window in BossLoot's frame listing every rare of the
-- zone the player is in, from the database and from sightings, by level,
-- with when each was last seen and whether WoW Forever has it. Clicking one
-- opens the world map on the zone with its pins glowing.

local List = {}
ns.List = List

ns.AddDefaults({
    window = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
})

local WIDTH, HEIGHT = 540, 420
local ROW_HEIGHT = 20
local LOGO = 16 -- the skull before the name, sized to the title bar
local LOGO_GAP = 6
local TOP = 58  -- where the column heads sit, under the zone's name
-- Where the columns start, from a row's left edge, and how wide each is.
local NAME_X, LEVEL_X, LAST_X, SEEN_X = 6, 230, 290, 410
local COLUMNS = {
    { x = NAME_X, label = "Name" },
    { x = LEVEL_X, label = "Level" },
    { x = LAST_X, label = "Last seen" },
    { x = SEEN_X, label = "On WoW Forever" },
}

local frame
local mapID -- the zone listed

--- The list's rows for zone `uiMapID`: { id, name, level, last, seen, elite }.
function List.Entries(uiMapID)
    local now = time()
    local entries = {}
    for _, info in ipairs(ns.Rares.InZone(uiMapID)) do
        entries[#entries + 1] = {
            id = info.id,
            name = info.name,
            level = ns.Rares.LevelText(info),
            last = info.last and ns.Rares.Ago(now - info.last) or "never",
            seen = info.seen,
            elite = info.elite,
        }
    end
    return entries
end

local function savePosition(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    local saved = ns.settings.window
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

--- CreateFrame with a template, or without it on a client that lacks it.
local function createFrame(kind, name, parent, template)
    local ok, created = pcall(CreateFrame, kind, name, parent, template)
    if ok and created then
        return created
    end
    return CreateFrame(kind, name, parent)
end

-- The window's frame, as BossLoot's, BankBags' and LFGBoard's: the options
-- window's own, the name in its title bar and its red X, so this reads as one
-- of the game's windows. On a client without it, the dialog border, a name
-- and a close button of our own. Solid either way: the options window and
-- the dialog background let the world show through.
local function createWindowFrame()
    local ok, made = pcall(CreateFrame, "Frame", "RareMobListFrame", UIParent, "SettingsFrameTemplate")
    if not (ok and made) then
        made = createFrame("Frame", "RareMobListFrame", UIParent, "BackdropTemplate")
    end
    local native = made.NineSlice and made.NineSlice.Text and made.ClosePanelButton and made.Bg

    if native then
        -- On the game's background, so under its border and title bar too.
        made.background = made.Bg:CreateTexture(nil, "BACKGROUND", nil, 7)
        made.background:SetAllPoints(made.Bg)
        made.title = made.NineSlice.Text
        made.title:ClearAllPoints()
        made.title:SetPoint("TOP", made, "TOP", (LOGO + LOGO_GAP) / 2, -5)
        made.close = made.ClosePanelButton
    else
        made.background = made:CreateTexture(nil, "BACKGROUND", nil, -8)
        made.background:SetPoint("TOPLEFT", made, "TOPLEFT", 4, -4)
        made.background:SetPoint("BOTTOMRIGHT", made, "BOTTOMRIGHT", -4, 4)
        if made.SetBackdrop then
            made:SetBackdrop({
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
        end
        made.title = made:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        made.title:SetPoint("TOP", made, "TOP", (LOGO + LOGO_GAP) / 2, -14)
        made.close = createFrame("Button", nil, made, "UIPanelCloseButton")
        made.close:SetPoint("TOPRIGHT", made, "TOPRIGHT", -4, -4)
        if not (made.close.GetNormalTexture and made.close:GetNormalTexture()) then
            made.close:SetText("X")
        end
    end
    made.background:SetColorTexture(0.06, 0.045, 0.03, 1)
    made.title:SetText("RareMob")

    -- The glyph alone, as the minimap button shows it, before the name.
    made.logo = (native and made.NineSlice or made):CreateTexture(nil, "OVERLAY")
    made.logo:SetSize(LOGO, LOGO)
    made.logo:SetPoint("RIGHT", made.title, "LEFT", -LOGO_GAP, 0)
    made.logo:SetTexture("Interface\\AddOns\\RareMob\\minimap")

    -- Our own, not the game's: that asks the window manager, which an addon
    -- may not do in combat.
    made.close:SetScript("OnClick", function()
        made:Hide()
    end)
    return made
end

local function cell(row, x, width, font)
    local text = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    text:SetPoint("LEFT", row, "LEFT", x, 0)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local function makeRow(index)
    local row = CreateFrame("Button", nil, frame.content)
    row:SetSize(WIDTH - 60, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.name = cell(row, NAME_X, LEVEL_X - NAME_X - 6, "GameFontNormalSmall")
    row.level = cell(row, LEVEL_X, LAST_X - LEVEL_X - 6)
    row.last = cell(row, LAST_X, SEEN_X - LAST_X - 6)
    row.seen = cell(row, SEEN_X, WIDTH - 60 - SEEN_X)
    row:SetScript("OnClick", function(self)
        if self.id then
            frame:Hide()
            ns.WorldMap.ShowRare(self.id, mapID)
        end
    end)
    row:SetScript("OnEnter", function(self)
        if self.id then
            ns.Pins.ShowTooltip(self, self.id)
        end
    end)
    row:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    frame.rows[index] = row
    return row
end

local function fill(row, entry)
    row.id = entry.id
    row.name:SetText(entry.elite and (entry.name .. " (elite)") or entry.name)
    row.level:SetText(entry.level)
    row.last:SetText(entry.last)
    if entry.seen then
        row.seen:SetText("|cff40ff40Yes|r")
    else
        row.seen:SetText("|cff9d9d9dNo, classic database|r")
    end
    row:Show()
end

local function create()
    frame = createWindowFrame()
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", savePosition)
    local saved = ns.settings.window
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)

    frame.zone = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.zone:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -32)

    for _, column in ipairs(COLUMNS) do
        local head = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        head:SetPoint("TOPLEFT", frame, "TOPLEFT", 18 + column.x, -TOP)
        head:SetText(column.label)
    end

    -- The rows scroll: Stranglethorn has more rares than fit.
    local scroll = createFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -TOP - 16)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 16)
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
    frame.scroll = scroll
    frame.content = CreateFrame("Frame", nil, scroll)
    frame.content:SetSize(WIDTH - 60, ROW_HEIGHT)
    if scroll.SetScrollChild then
        scroll:SetScrollChild(frame.content)
    end
    frame.rows = {}

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.empty:SetPoint("TOP", frame, "TOP", 0, -TOP - 40)
    frame.empty:SetText("No rares known in this zone.")

    frame:SetScript("OnShow", function()
        List.Refresh()
    end)
    table.insert(UISpecialFrames, "RareMobListFrame")
    frame:Hide()
end

local function zoneName(uiMapID)
    return ns.Guarded(function()
        local info = C_Map.GetMapInfo(uiMapID)
        return info and info.name
    end)
end

function List.Refresh()
    if not (frame and frame:IsShown()) then
        return
    end
    mapID = ns.Guarded(function() return C_Map.GetBestMapForUnit("player") end)
    frame.zone:SetText(zoneName(mapID) or "Unknown zone")

    local entries = List.Entries(mapID)
    for index, entry in ipairs(entries) do
        fill(frame.rows[index] or makeRow(index), entry)
    end
    for index = #entries + 1, #frame.rows do
        frame.rows[index].id = nil
        frame.rows[index]:Hide()
    end
    frame.content:SetHeight(math.max(1, #entries) * ROW_HEIGHT)
    frame.empty:SetShown(#entries == 0)
end

function List.Toggle()
    if not frame then
        create()
    end
    frame:SetShown(not frame:IsShown())
end

--- Show the list; left open if it is open already.
function List.Open()
    if not frame then
        create()
    end
    frame:Show()
end

function List.Frame()
    return frame
end

ns.DefaultCommand = List.Toggle

local events = CreateFrame("Frame")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function()
    ns.Guarded(List.Refresh)
end)

ns.OnRefresh(List.Refresh)
