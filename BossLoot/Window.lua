local addonName, ns = ...

-- The loot window: an instance rail on the left, the boss list with portraits
-- in the middle, and the boss page on the right -- the boss's model, a map of
-- the instance, and the loot in two columns.

local Window = {}
ns.Window = Window

ns.AddDefaults({
    -- What the window last showed, so it reopens there.
    view = { kind = "dungeon", instance = "", boss = 1 },
    window = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
})

local WIDTH = 860
local HEIGHT = 520
local PADDING = 12
local TITLE_HEIGHT = 28
local TOP = PADDING + TITLE_HEIGHT
local GAP = 8
local RAIL_WIDTH = 170
local BOSS_WIDTH = 230
local PAGE_LEFT = PADDING + RAIL_WIDTH + GAP + BOSS_WIDTH + GAP
local PAGE_WIDTH = WIDTH - PAGE_LEFT - PADDING
local HEADER_HEIGHT = 96
local SEARCH_HEIGHT = 20
local TAB_HEIGHT = 22
local RAIL_ROW = 18
local BOSS_ROW = 34
local LOOT_ROW = ns.LootRow.HEIGHT + 2
local INSET_WIDTH, INSET_HEIGHT = 150, 84
local MORE_HEIGHT = 16
-- A search needs this many characters; fewer would match nearly everything.
local SEARCH_MIN = 2

local EMPTY_TEXT = "Nothing but world drops and quest items."

-- What the boss column calls the two notable lists.
local NOTABLE_NAMES = { trash = "From trash", objects = "Chests & objects" }

local frame
-- The selection the loot column last showed: a new one scrolls it to the top,
-- a redraw of the same one keeps its place.
local lastSelection
-- The instance the boss list last showed, likewise.
local lastBossInstance

--------------------------------------------------------------------------------
-- What each column holds. Pure, so the specs read them directly.
--------------------------------------------------------------------------------

local function instanceEntry(instance, selectedKey)
    return {
        kind = "instance",
        value = instance.key,
        selected = instance.key == selectedKey,
        text = string.format("%s |cff808080%d-%d|r", instance.name, instance.levels[1], instance.levels[2]),
    }
end

-- One place an item drops, as a search result under the item: where, and how
-- likely. Choosing it jumps there.
local function placeEntry(itemID, source)
    local instance = ns.instanceByKey[source.instance]
    local label, list
    if type(source.boss) == "number" then
        local boss = instance.bosses[source.boss]
        label, list = boss.name, boss.loot
    else
        label, list = NOTABLE_NAMES[source.boss], instance.notable[source.boss]
    end

    local chance = 0
    for _, entry in ipairs(list) do
        if entry[1] == itemID then
            chance = entry[2]
            break
        end
    end

    return {
        kind = "place",
        value = source,
        text = string.format("    %s: %s |cff808080%s|r", instance.name, label, ns.Format.Chance(chance)),
    }
end

local function itemName(itemID)
    local info = ns.LootRow.ItemInfo(itemID)
    return info and info.name
end

function Window.InstanceEntries(view, searchText)
    local entries = {}
    local text = searchText and searchText:match("^%s*(.-)%s*$") or ""

    if #text >= SEARCH_MIN then
        local result = ns.Index.Search(text, itemName)

        for _, instance in ipairs(result.instances) do
            table.insert(entries, instanceEntry(instance, view.instance))
        end

        if #result.items > 0 then
            table.insert(entries, { kind = "heading", text = "Items" })
            for _, item in ipairs(result.items) do
                local info = ns.LootRow.ItemInfo(item.id)
                table.insert(entries, {
                    kind = "item",
                    value = item.id,
                    text = ns.Format.Colored(item.name, info and info.quality),
                })
                for _, source in ipairs(item.sources) do
                    table.insert(entries, placeEntry(item.id, source))
                end
            end
        end

        if #entries == 0 then
            table.insert(entries, { kind = "heading", text = "No matches" })
        end
        return entries
    end

    for _, instance in ipairs(ns.Index.Instances(view.kind)) do
        table.insert(entries, instanceEntry(instance, view.instance))
    end
    return entries
end

function Window.BossEntries(instance, selection)
    local entries = {}
    if not instance then
        return entries
    end

    local wing
    for index, boss in ipairs(instance.bosses) do
        if boss.wing and boss.wing ~= wing then
            table.insert(entries, { kind = "heading", text = boss.wing })
        end
        wing = boss.wing
        table.insert(entries, {
            kind = "boss", value = index, text = boss.name, selected = selection == index,
            number = index, display = boss.display,
        })
    end

    local notable = instance.notable or {}
    local trash, objects = notable.trash or {}, notable.objects or {}
    if #trash > 0 or #objects > 0 then
        table.insert(entries, { kind = "heading", text = "Notable drops" })
        if #trash > 0 then
            table.insert(entries, {
                kind = "boss", value = "trash", text = NOTABLE_NAMES.trash, selected = selection == "trash",
                icon = ns.Portrait.ICONS.trash,
            })
        end
        if #objects > 0 then
            table.insert(entries, {
                kind = "boss", value = "objects", text = NOTABLE_NAMES.objects, selected = selection == "objects",
                icon = ns.Portrait.ICONS.objects,
            })
        end
    end

    return entries
end

local function lootSource(instance, selection)
    if not instance then
        return nil
    end
    if type(selection) == "number" then
        local boss = instance.bosses[selection]
        return boss and boss.loot
    end
    return instance.notable and instance.notable[selection]
end

function Window.LootEntries(instance, selection)
    local entries = {}
    for _, entry in ipairs(lootSource(instance, selection) or {}) do
        table.insert(entries, { id = entry[1], chance = entry[2], sources = entry[3] })
    end
    return entries
end

--------------------------------------------------------------------------------
-- The selection
--------------------------------------------------------------------------------

-- A boss is a valid selection even with nothing to drop (the Stockade has
-- several); a notable list only when it has something in it, since the
-- boss column leaves an empty one out.
local function validSelection(instance, selection)
    if type(selection) == "number" then
        return instance.bosses[selection] ~= nil
    end
    local list = lootSource(instance, selection)
    return list ~= nil and #list > 0
end

--- The instance and boss the window shows, repaired when what was saved has
-- gone: hidden, dropped from the data by a rebuild, or a boss index past the
-- end. The repair is saved, so it happens once.
function Window.Current()
    local view = ns.db.view
    local instance = ns.instanceByKey[view.instance]

    if not instance or instance.kind ~= view.kind or ns.Index.IsHidden(instance.key) then
        instance = ns.Index.Instances(view.kind)[1]
        view.instance = instance and instance.key or ""
        view.boss = 1
    end

    if instance and not validSelection(instance, view.boss) then
        view.boss = 1
    end

    return instance, view.boss
end

local function preload(instance)
    for _, itemID in ipairs(ns.Index.ItemIDs(instance.key)) do
        if not ns.LootRow.ItemInfo(itemID) then
            ns.LootRow.RequestLoad(itemID)
        end
    end
end

function Window.CloseMap()
    if frame then
        frame.fullMap:Hide()
    end
end

function Window.OpenMap()
    if not frame then
        return
    end
    frame.fullMap:Show()
    Window.Refresh()
end

function Window.SelectKind(kind)
    ns.db.view.kind = kind
    Window.CloseMap()
    local instance = Window.Current()
    if instance then
        preload(instance)
    end
    Window.Refresh()
end

function Window.SelectInstance(key)
    local instance = ns.instanceByKey[key]
    if not instance then
        return
    end

    local view = ns.db.view
    view.kind = instance.kind
    view.instance = key
    view.boss = 1
    Window.CloseMap()
    preload(instance)
    Window.Refresh()
end

function Window.SelectBoss(selection)
    ns.db.view.boss = selection
    Window.Refresh()
end

--- Go to the first visible place an item drops.
function Window.SelectItem(itemID)
    for _, source in ipairs(ns.Index.Sources(itemID)) do
        if not ns.Index.IsHidden(source.instance) then
            Window.SelectInstance(source.instance)
            Window.SelectBoss(source.boss)
            return
        end
    end
end

function Window.HideInstance(key)
    local instance = ns.instanceByKey[key]
    if not instance then
        return
    end
    ns.db.hidden[key] = true
    ns.Print(string.format("Hid %s. Type /bl unhide to bring hidden instances back.", instance.name))
    Window.Refresh()
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

-- The portrait for a row or header: the boss's face, or -- for a row with no
-- model at all, a chest-only boss -- the chest. Drawn only when it changes:
-- the window redraws on every keystroke and every item that arrives.
local function setPortrait(texture, display, icon)
    local key = icon or display or "none"
    if texture.portraitKey == key then
        return
    end
    texture.portraitKey = key
    if icon then
        texture:SetTexture(icon)
    else
        ns.Portrait.Set(texture, display, not display and ns.Portrait.ICONS.objects or nil)
    end
end

local function showPortrait(header, display, icon)
    header.model:Hide()
    setPortrait(header.portrait, display, icon)
    header.portrait:Show()
end

local function drawHeader(instance, selection)
    local header = frame.header

    if not instance then
        header.model:Hide()
        header.portrait:Hide()
        header.title:SetText("")
        header.subtitle:SetText("")
        return
    end

    if type(selection) ~= "number" then
        header.title:SetText(NOTABLE_NAMES[selection])
        header.subtitle:SetText(instance.name)
        showPortrait(header, nil, ns.Portrait.ICONS[selection])
        return
    end

    local boss = instance.bosses[selection]
    header.title:SetText(boss.name)
    header.subtitle:SetText(boss.wing and (instance.name .. ", " .. boss.wing) or instance.name)

    -- The model is set while shown, and only when the boss changes: setting
    -- it again restarts its animation, and one set while hidden can come up
    -- blank.
    if boss.display then
        header.model:Show()
        if header.model.shownDisplay == boss.display then
            header.portrait:Hide()
            return
        end
        if ns.Portrait.SetModel(header.model, boss.display) then
            header.model.shownDisplay = boss.display
            header.portrait:Hide()
            return
        end
        header.model.shownDisplay = nil
    end
    showPortrait(header, boss.display)
end

function Window.Refresh()
    if not frame then
        return
    end

    local view = ns.db.view
    local instance, selection = Window.Current()

    ns.List.SetEntries(frame.instances, Window.InstanceEntries(view, frame.search:GetText()), true)

    -- The boss list keeps its place within an instance, starts at the top in
    -- a new one, and always shows the selected boss (picked on the map, it
    -- may be further down than the list shows).
    local bossEntries = Window.BossEntries(instance, selection)
    ns.List.SetEntries(frame.bosses, bossEntries, view.instance == lastBossInstance)
    lastBossInstance = view.instance
    for position, entry in ipairs(bossEntries) do
        if entry.selected then
            ns.List.Reveal(frame.bosses, position)
            break
        end
    end

    local loot = Window.LootEntries(instance, selection)
    local key = tostring(view.instance) .. ":" .. tostring(selection)
    ns.List.SetEntries(frame.loot, loot, key == lastSelection)
    lastSelection = key
    frame.empty:SetShown(instance ~= nil and #loot == 0)

    drawHeader(instance, selection)
    local pinned = type(selection) == "number" and selection or nil
    ns.MapView.Show(frame.inset, instance, pinned)
    if frame.fullMap:IsShown() then
        ns.MapView.Show(frame.fullMap.view, instance, pinned)
    end

    for kind, tab in pairs(frame.tabs) do
        if kind == view.kind then
            tab:LockHighlight()
        else
            tab:UnlockHighlight()
        end
    end
end

local function onInstanceClick(entry, mouseButton)
    if entry.kind == "item" then
        Window.SelectItem(entry.value)
    elseif entry.kind == "place" then
        Window.SelectInstance(entry.value.instance)
        Window.SelectBoss(entry.value.boss)
    elseif mouseButton == "RightButton" then
        Window.HideInstance(entry.value)
    else
        Window.SelectInstance(entry.value)
    end
end

local function onBossClick(entry)
    Window.SelectBoss(entry.value)
end

-- A template this client lacks raises rather than returning nil, so every
-- templated frame is asked for through here. The plain fallback gets a font,
-- or its label would be blank and an edit box would refuse text.
local function createFrame(kind, name, parent, template)
    local ok, created = pcall(CreateFrame, kind, name, parent, template)
    if ok and created then
        return created
    end
    created = CreateFrame(kind, name, parent)
    if kind == "Button" and created.SetNormalFontObject then
        created:SetNormalFontObject("GameFontNormal")
    elseif kind == "EditBox" and created.SetFontObject then
        created:SetFontObject("ChatFontNormal")
    end
    return created
end

local function savePosition(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    local saved = ns.db.window
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

-- A darker or lighter band behind one region of the window.
local function panel(parent, left, top, width, height, shade)
    local texture = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    texture:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -top)
    texture:SetSize(width, height)
    texture:SetColorTexture(shade, shade * 0.8, shade * 0.6, 1)
    return texture
end

local function createTab(parent, kind, label, x)
    local tab = createFrame("Button", nil, parent, "UIPanelButtonTemplate")
    tab:SetSize(80, TAB_HEIGHT)
    tab:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(TOP + SEARCH_HEIGHT + 6))
    tab:SetText(label)
    tab:SetScript("OnClick", function()
        Window.SelectKind(kind)
    end)
    return tab
end

-- A boss row: portrait, number, name. Headings keep just their text.
local function bossRow(list)
    local row = ns.List.TextRow(onBossClick)(list)
    row.portrait = row:CreateTexture(nil, "ARTWORK")
    row.portrait:SetSize(BOSS_ROW - 4, BOSS_ROW - 4)
    row.portrait:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.number = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.number:SetPoint("LEFT", row.portrait, "RIGHT", 4, 0)
    row.number:SetWidth(18)
    row.number:SetJustifyH("RIGHT")
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.number, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    return row
end

local function renderBoss(row, entry)
    ns.List.RenderText(row, entry)
    if entry.kind == "heading" then
        row.portrait:Hide()
        row.number:SetText("")
        return
    end
    setPortrait(row.portrait, entry.display, entry.icon)
    row.portrait:Show()
    row.number:SetText(entry.number and tostring(entry.number) or "")
end

local function createHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", PAGE_LEFT, -TOP)
    header:SetSize(PAGE_WIDTH, HEADER_HEIGHT)

    -- The boss, turning slowly.
    header.model = CreateFrame("PlayerModel", nil, header)
    header.model:SetSize(84, 84)
    header.model:SetPoint("LEFT", header, "LEFT", 4, 0)
    header.model.facing = 0
    header.model:SetScript("OnUpdate", function(self, elapsed)
        self.facing = (self.facing + (elapsed or 0) * 0.4) % (math.pi * 2)
        if self.SetFacing then
            self:SetFacing(self.facing)
        end
    end)

    header.portrait = header:CreateTexture(nil, "ARTWORK")
    header.portrait:SetSize(64, 64)
    header.portrait:SetPoint("LEFT", header, "LEFT", 14, 0)

    header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header.title:SetPoint("TOPLEFT", header, "TOPLEFT", 100, -22)
    header.title:SetPoint("RIGHT", header, "RIGHT", -(INSET_WIDTH + 12), 0)
    header.title:SetJustifyH("LEFT")

    header.subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.subtitle:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -4)
    header.subtitle:SetJustifyH("LEFT")

    return header
end

local function create()
    frame = createFrame("Frame", "BossLootFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", savePosition)

    local saved = ns.db.window
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)

    -- Opaque, whatever the backdrop does: the dialog background is
    -- translucent by design, and may not load at all.
    frame.background = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.background:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    frame.background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    frame.background:SetColorTexture(0.06, 0.045, 0.03, 1)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    local columnHeight = HEIGHT - TOP - PADDING
    panel(frame, PADDING, TOP, RAIL_WIDTH, columnHeight, 0.035)
    panel(frame, PADDING + RAIL_WIDTH + GAP, TOP, BOSS_WIDTH, columnHeight, 0.05)
    panel(frame, PAGE_LEFT, TOP, PAGE_WIDTH, HEADER_HEIGHT, 0.12)

    -- Escape closes it, like every other window.
    table.insert(UISpecialFrames, "BossLootFrame")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 6, -PADDING - 4)
    title:SetText("BossLoot")

    local close = createFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    if not (close.GetNormalTexture and close:GetNormalTexture()) then
        close:SetText("X")
    end
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- The rail: search, tabs, instances.
    local search = createFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(RAIL_WIDTH - 14, SEARCH_HEIGHT)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 8, -TOP - 2)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    -- On the box itself: a string on the window would draw under the box's art.
    frame.searchHint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.searchHint:SetPoint("LEFT", search, "LEFT", 4, 0)
    frame.searchHint:SetText("Search...")
    search:SetScript("OnTextChanged", function(self)
        frame.searchHint:SetShown(self:GetText() == "")
        Window.Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    frame.search = search

    frame.tabs = {
        dungeon = createTab(frame, "dungeon", "Dungeons", PADDING + 4),
        raid = createTab(frame, "raid", "Raids", PADDING + 86),
    }

    local railTop = TOP + SEARCH_HEIGHT + TAB_HEIGHT + 12
    frame.instances = ns.List.Create(frame, {
        width = RAIL_WIDTH, rowHeight = RAIL_ROW,
        rows = math.floor((HEIGHT - railTop - PADDING - MORE_HEIGHT) / RAIL_ROW),
        createRow = ns.List.TextRow(onInstanceClick), renderRow = ns.List.RenderText,
    })
    frame.instances:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -railTop)

    -- The boss list.
    frame.bosses = ns.List.Create(frame, {
        width = BOSS_WIDTH, rowHeight = BOSS_ROW,
        rows = math.floor((columnHeight - MORE_HEIGHT) / BOSS_ROW),
        createRow = bossRow, renderRow = renderBoss,
    })
    frame.bosses:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + RAIL_WIDTH + GAP, -TOP)

    -- The boss page: header with model and map inset, then the loot grid.
    frame.header = createHeader(frame)

    frame.inset = ns.MapView.Create(frame.header, INSET_WIDTH, INSET_HEIGHT)
    frame.inset:SetPoint("RIGHT", frame.header, "RIGHT", -6, 0)
    frame.inset:SetScript("OnClick", function()
        Window.OpenMap()
    end)

    local lootTop = TOP + HEADER_HEIGHT + 6
    frame.loot = ns.List.Create(frame, {
        width = PAGE_WIDTH, columnWidth = PAGE_WIDTH / 2, columns = 2, rowHeight = LOOT_ROW,
        rows = math.floor((HEIGHT - lootTop - PADDING - MORE_HEIGHT) / LOOT_ROW),
        createRow = ns.LootRow.Create, renderRow = ns.LootRow.Render,
    })
    frame.loot:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_LEFT, -lootTop)

    -- Some bosses drop nothing but world drops and quest items, which are
    -- left out; say so rather than show a column that looks broken.
    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_LEFT + 6, -lootTop - 6)
    frame.empty:SetText(EMPTY_TEXT)
    frame.empty:Hide()

    -- The full map, over the boss page.
    frame.fullMap = CreateFrame("Frame", nil, frame)
    frame.fullMap:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_LEFT, -TOP)
    frame.fullMap:SetSize(PAGE_WIDTH, columnHeight)
    frame.fullMap:SetFrameLevel(frame:GetFrameLevel() + 20)
    frame.fullMap.view = ns.MapView.Create(frame.fullMap, PAGE_WIDTH, columnHeight, {
        pinSize = 20,
        onPinClick = function(bossIndex)
            Window.SelectBoss(bossIndex)
            Window.CloseMap()
        end,
    })
    frame.fullMap.view:SetPoint("TOPLEFT", frame.fullMap, "TOPLEFT", 0, 0)
    frame.fullMap.close = createFrame("Button", nil, frame.fullMap, "UIPanelCloseButton")
    frame.fullMap.close:SetPoint("TOPRIGHT", frame.fullMap, "TOPRIGHT", 0, 0)
    -- Above the pins, which can sit right under it (Blackrock Depths' 25).
    frame.fullMap.close:SetFrameLevel(frame.fullMap.view:GetFrameLevel() + 10)
    frame.fullMap.close:SetScript("OnClick", function()
        Window.CloseMap()
    end)
    frame.fullMap:Hide()

    frame:SetScript("OnShow", function()
        local instance = Window.Current()
        if instance then
            preload(instance)
        end
        Window.Refresh()
    end)

    frame:Hide()
end

function Window.Frame()
    return frame
end

function Window.Open()
    if not frame then
        create()
    end
    frame:Show()
    Window.Refresh()
end

function Window.Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        Window.Open()
    end
end

ns.DefaultCommand = Window.Toggle

ns.RegisterCommand("unhide", "Bring back every instance you hid", function()
    for key in pairs(ns.db.hidden) do
        ns.db.hidden[key] = nil
    end
    ns.Print("Every instance is back on the list.")
    Window.Refresh()
end)

-- Items arrive in bursts as an instance loads; redraw once per burst.
local redrawPending = false
local events = CreateFrame("Frame")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, _, itemID, success)
    if success == false then
        ns.LootRow.MarkFailed(itemID)
    end
    if redrawPending or not (frame and frame:IsShown()) then
        return
    end
    redrawPending = true
    C_Timer.After(0.1, function()
        redrawPending = false
        Window.Refresh()
    end)
end)
