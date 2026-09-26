local addonName, ns = ...

-- The loot window: instances, bosses and loot in three columns.

local Window = {}
ns.Window = Window

ns.AddDefaults({
    -- What the window last showed, so it reopens there.
    view = { kind = "dungeon", instance = "", boss = 1 },
    window = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
})

local WIDTH = 780
local HEIGHT = 470
local PADDING = 12
local TITLE_HEIGHT = 28
local ROW_HEIGHT = 18
local SEARCH_HEIGHT = 20
local TAB_HEIGHT = 22
local INSTANCE_WIDTH = 210
local BOSS_WIDTH = 200
local GAP = 10
local LOOT_WIDTH = WIDTH - PADDING * 2 - INSTANCE_WIDTH - BOSS_WIDTH - GAP * 2
local LIST_TOP = PADDING + TITLE_HEIGHT
local LIST_HEIGHT = HEIGHT - LIST_TOP - PADDING

local EMPTY_TEXT = "Nothing but world drops and quest items."

local frame
-- The selection the loot column last showed: a new one scrolls it to the top,
-- a redraw of the same one keeps its place.
local lastSelection

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

-- What the boss column calls the two notable lists.
local NOTABLE_NAMES = { trash = "From trash", objects = "Chests & objects" }

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

    if searchText and searchText:match("%S") then
        local result = ns.Index.Search(searchText, itemName)

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
        table.insert(entries, { kind = "boss", value = index, text = boss.name, selected = selection == index })
    end

    local notable = instance.notable or {}
    local trash, objects = notable.trash or {}, notable.objects or {}
    if #trash > 0 or #objects > 0 then
        table.insert(entries, { kind = "heading", text = "Notable drops" })
        if #trash > 0 then
            table.insert(entries, { kind = "boss", value = "trash", text = NOTABLE_NAMES.trash, selected = selection == "trash" })
        end
        if #objects > 0 then
            table.insert(entries, { kind = "boss", value = "objects", text = NOTABLE_NAMES.objects, selected = selection == "objects" })
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

function Window.SelectKind(kind)
    ns.db.view.kind = kind
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

function Window.Refresh()
    if not frame then
        return
    end

    local view = ns.db.view
    local instance, selection = Window.Current()

    ns.List.SetEntries(frame.instances, Window.InstanceEntries(view, frame.search:GetText()), true)
    ns.List.SetEntries(frame.bosses, Window.BossEntries(instance, selection), true)

    local loot = Window.LootEntries(instance, selection)
    local key = tostring(view.instance) .. ":" .. tostring(selection)
    ns.List.SetEntries(frame.loot, loot, key == lastSelection)
    lastSelection = key

    frame.empty:SetShown(instance ~= nil and #loot == 0)

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
-- templated frame is asked for through here, with a plain fallback.
local function createFrame(kind, name, parent, template)
    local ok, created = pcall(CreateFrame, kind, name, parent, template)
    if ok and created then
        return created
    end
    return CreateFrame(kind, name, parent)
end

local function savePosition(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    local saved = ns.db.window
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

local function createTab(parent, kind, label, x)
    local tab = createFrame("Button", nil, parent, "UIPanelButtonTemplate")
    tab:SetSize(80, TAB_HEIGHT)
    tab:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(LIST_TOP + SEARCH_HEIGHT + 4))
    tab:SetText(label)
    tab:SetScript("OnClick", function()
        Window.SelectKind(kind)
    end)
    return tab
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

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    -- Escape closes it, like every other window.
    table.insert(UISpecialFrames, "BossLootFrame")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 6, -PADDING - 4)
    title:SetText("BossLoot")

    local close = createFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    local search = createFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(INSTANCE_WIDTH - 8, SEARCH_HEIGHT)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 6, -LIST_TOP)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    search:SetScript("OnTextChanged", function()
        Window.Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    frame.search = search

    frame.tabs = {
        dungeon = createTab(frame, "dungeon", "Dungeons", PADDING),
        raid = createTab(frame, "raid", "Raids", PADDING + 84),
    }

    local instanceTop = LIST_TOP + SEARCH_HEIGHT + TAB_HEIGHT + 10
    frame.instances = ns.List.Create(frame, {
        width = INSTANCE_WIDTH, rowHeight = ROW_HEIGHT,
        rows = math.floor((HEIGHT - instanceTop - PADDING) / ROW_HEIGHT),
        createRow = ns.List.TextRow(onInstanceClick), renderRow = ns.List.RenderText,
    })
    frame.instances:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -instanceTop)

    frame.bosses = ns.List.Create(frame, {
        width = BOSS_WIDTH, rowHeight = ROW_HEIGHT,
        rows = math.floor(LIST_HEIGHT / ROW_HEIGHT),
        createRow = ns.List.TextRow(onBossClick), renderRow = ns.List.RenderText,
    })
    frame.bosses:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + INSTANCE_WIDTH + GAP, -LIST_TOP)

    local lootLeft = PADDING + INSTANCE_WIDTH + BOSS_WIDTH + GAP * 2
    frame.loot = ns.List.Create(frame, {
        width = LOOT_WIDTH, rowHeight = ns.LootRow.HEIGHT,
        rows = math.floor(LIST_HEIGHT / ns.LootRow.HEIGHT),
        createRow = ns.LootRow.Create, renderRow = ns.LootRow.Render,
    })
    frame.loot:SetPoint("TOPLEFT", frame, "TOPLEFT", lootLeft, -LIST_TOP)

    -- Some bosses drop nothing but world drops and quest items, which are
    -- left out; say so rather than show a column that looks broken.
    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", lootLeft + 4, -LIST_TOP - 6)
    frame.empty:SetText(EMPTY_TEXT)
    frame.empty:Hide()

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
