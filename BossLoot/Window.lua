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
    -- The item loading details under the window, for testing: /bl debug.
    debug = false,
})

local WIDTH = 860
local HEIGHT = 520
local PADDING = 12
local TITLE_BAR = 24 -- the game's title bar, with the name in it
local TOP = TITLE_BAR + 6
local LOGO = 16 -- the chest before the name, sized to the title bar
local LOGO_GAP = 6
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
local TURN_PER_PIXEL = 0.02 -- radians the boss's model turns per pixel dragged
local CLICK_SLOP = 4 -- pixels a press on a model may move and still be a click
-- The big model's window, beside the main one, and its zoom.
local MODEL_VIEW_WIDTH = 340
local MODEL_HINT_HEIGHT = 18
local MODEL_ZOOM_STEP = 1.15
local MODEL_NEAREST, MODEL_FARTHEST = 0.3, 3
-- The item loading bar, in the window's top row over the boss page, clear of
-- the close button: the big map, which covers the page, leaves it in sight.
local PROGRESS_WIDTH = PAGE_WIDTH - 36
local PROGRESS_HEIGHT = 14
local PROGRESS_POLL = 0.5 -- seconds between counts while items load
local DEBUG_HEIGHT = 64 -- the loading details under the window
local MORE_HEIGHT = 16
-- While the big map covers the boss page, the boss list keeps this many rows
-- and the loot moves into the space under them.
local BOSS_ROWS_WITH_MAP = 6
-- A search needs this many characters; fewer would match nearly everything.
local SEARCH_MIN = 2

local EMPTY_TEXT = "Nothing but world drops and quest items."

-- Above the vanilla list, once recordings come first.
local CLASSIC_HEADING = "Classic loot"
local CLASSIC_NOTE = "Not seen on WoW Forever yet"

-- What the boss column calls the two notable lists.
local NOTABLE_NAMES = { trash = "From trash", objects = "Chests & objects" }

local frame
-- The selection the loot column last showed: a new one scrolls it to the top,
-- a redraw of the same one keeps its place.
local lastSelection
-- The instance the boss list last showed, likewise.
local lastBossInstance
-- The item picked from a search, marked in the results and in the loot until
-- another is picked or the search is cleared.
local highlightItem

--------------------------------------------------------------------------------
-- What each column holds. Pure, so the specs read them directly.
--------------------------------------------------------------------------------

local function instanceEntry(instance, selectedKey)
    local text = instance.name
    if instance.levels then
        text = string.format("%s |cff808080%d-%d|r", instance.name, instance.levels[1], instance.levels[2])
    elseif instance.recorded then
        text = instance.name .. " |cff808080recorded|r"
    end
    return { kind = "instance", value = instance.key, selected = instance.key == selectedKey, text = text }
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

-- The recorded loot of a boss or notable list, and for a boss its kills.
local function recordedSource(instance, selection)
    if not instance then
        return nil
    end
    if type(selection) == "number" then
        local boss = instance.bosses[selection]
        return boss and boss.recorded, boss and boss.recordedKills
    end
    return instance.recordedNotable and instance.recordedNotable[selection], nil
end

-- How often a recorded item was seen: of the kills for a boss, a count for
-- a notable list.
local function seenText(entry, kills)
    if kills then
        return entry[2] .. "/" .. kills
    end
    return "×" .. entry[2]
end

-- One place an item drops, as a search result under the item: where, and how
-- likely. Choosing it jumps there.
local function placeEntry(itemID, source, view)
    local instance = ns.instanceByKey[source.instance]
    local label, list
    if type(source.boss) == "number" then
        local boss = instance.bosses[source.boss]
        label, list = boss.name, boss.loot
    else
        label, list = NOTABLE_NAMES[source.boss], instance.notable[source.boss]
    end

    local right
    for _, entry in ipairs(list or {}) do
        if entry[1] == itemID then
            right = ns.Format.Chance(entry[2])
            break
        end
    end
    if not right then
        local recorded, kills = recordedSource(instance, source.boss)
        for _, entry in ipairs(recorded or {}) do
            if entry[1] == itemID then
                right = seenText(entry, kills)
                break
            end
        end
    end

    return {
        kind = "place",
        value = { instance = source.instance, boss = source.boss, item = itemID },
        text = string.format("    %s: %s", instance.name, label),
        right = right or "",
        selected = itemID == highlightItem and source.instance == view.instance and source.boss == view.boss,
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
                    selected = item.id == highlightItem,
                })
                for _, source in ipairs(item.sources) do
                    table.insert(entries, placeEntry(item.id, source, view))
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
    local recordedNotable = instance.recordedNotable or {}
    local function has(which)
        return #(notable[which] or {}) > 0 or #(recordedNotable[which] or {}) > 0
    end
    if has("trash") or has("objects") then
        table.insert(entries, { kind = "heading", text = "Notable drops" })
        if has("trash") then
            table.insert(entries, {
                kind = "boss", value = "trash", text = NOTABLE_NAMES.trash, selected = selection == "trash",
                icon = ns.Portrait.ICONS.trash,
            })
        end
        if has("objects") then
            table.insert(entries, {
                kind = "boss", value = "objects", text = NOTABLE_NAMES.objects, selected = selection == "objects",
                icon = ns.Portrait.ICONS.objects,
            })
        end
    end
    return entries
end

--- A boss's or notable list's loot: what was recorded, most seen first, with
-- how often; then, under a heading on a line of its own in a grid of
-- `perLine` columns, the vanilla list, dimmed, less what was recorded.
function Window.LootEntries(instance, selection, perLine)
    perLine = perLine or 2
    local entries = {}
    if not instance then
        return entries
    end

    local recorded, kills = recordedSource(instance, selection)
    local seen = {}
    for _, entry in ipairs(recorded or {}) do
        seen[entry[1]] = true
        table.insert(entries, {
            id = entry[1],
            seen = seenText(entry, kills),
            sources = #entry[3] > 0 and entry[3] or nil,
            selected = entry[1] == highlightItem,
        })
    end

    local classic = {}
    for _, entry in ipairs(lootSource(instance, selection) or {}) do
        if not seen[entry[1]] then
            table.insert(classic, {
                id = entry[1], chance = entry[2], sources = entry[3], classic = true,
                selected = entry[1] == highlightItem,
            })
        end
    end
    if #classic > 0 then
        while #entries % perLine ~= 0 do
            table.insert(entries, { blank = true })
        end
        table.insert(entries, { heading = CLASSIC_HEADING, note = CLASSIC_NOTE })
        while #entries % perLine ~= 0 do
            table.insert(entries, { blank = true })
        end
        for _, entry in ipairs(classic) do
            table.insert(entries, entry)
        end
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
    local recorded = recordedSource(instance, selection)
    return (list ~= nil and #list > 0) or (recorded ~= nil and #recorded > 0)
end

-- The first thing to show: the first boss, or failing one (a recorded
-- instance with no named boss), a notable list.
local function firstSelection(instance)
    for _, selection in ipairs({ 1, "trash", "objects" }) do
        if validSelection(instance, selection) then
            return selection
        end
    end
    return 1
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
        view.boss = firstSelection(instance)
    end

    return instance, view.boss
end

-- Every item of the instances on the list, worked out again when one is
-- hidden or brought back.
local everyItemList
local function everyItem()
    everyItemList = everyItemList or ns.Index.AllItemIDs()
    return everyItemList
end


-- The big map covers the boss page, loot and all, so while it is open the
-- loot moves under the boss list, which gives up its lower half.
function Window.CloseMap()
    if not (frame and frame.fullMap:IsShown()) then
        return
    end
    frame.fullMap:Hide()
    frame.mapLoot:Hide()
    frame.loot:Show()
    ns.List.SetVisibleRows(frame.bosses, frame.bossRows)
    Window.Refresh()
end

function Window.OpenMap()
    if not frame then
        return
    end
    frame.fullMap:Show()
    frame.loot:Hide()
    frame.mapLoot:Show()
    ns.List.SetVisibleRows(frame.bosses, BOSS_ROWS_WITH_MAP)
    Window.Refresh()
end

function Window.SelectKind(kind)
    ns.db.view.kind = kind
    Window.CloseMap()
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
    view.boss = firstSelection(instance)
    Window.CloseMap()
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
    everyItemList = nil
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

-- The item loading bar: how many of the instance's items have loaded, in
-- green, and how many were given up on, in red. Gone once all have loaded.
local function updateProgress(bar)
    local status = ns.LootRow.Status(bar.itemIDs or {}, bar.serverOnly)
    bar.status = status
    if status.total == 0 or (status.loaded == status.total and not bar.keepWhenDone) then
        bar:Hide()
        return
    end

    local function widthFor(count)
        return math.max(0.001, bar:GetWidth() * count / status.total)
    end
    bar.fill:SetWidth(widthFor(status.loaded))
    bar.fill:SetShown(status.loaded > 0)
    bar.failedFill:SetWidth(widthFor(status.failed))
    bar.failedFill:SetShown(status.failed > 0)

    bar.text:SetText(bar.describe(status))
    bar:Show()
end

-- What the instance's bar says.
local function describeInstance(status)
    local count = status.loaded .. " / " .. status.total
    if status.loading == 0 then
        return count .. " items, " .. status.failed .. " failed: click to retry"
    end
    local text = "Loading items " .. count
    if status.failed > 0 then
        text = text .. ", " .. status.failed .. " failed"
    end
    return text
end

-- What the test panel's bar says: how many items the server has sent.
local function describeAll(status)
    local text = "Server item data " .. status.loaded .. " / " .. status.total
    if status.failed > 0 then
        text = text .. " (" .. status.failed .. " failed)"
    end
    return text
end

-- The loading details' two lines: what the queue has done, and what it is
-- doing, with how many items arrived a second since last counted.
local function updateDetails(panel, elapsed)
    panel.progress.itemIDs = everyItem()
    updateProgress(panel.progress)

    local activity = ns.LootRow.Activity()
    panel.asked:SetText(string.format("Asked %d times: %d answered, %d empty, %d no answer",
        activity.asked, activity.answered, activity.empty, activity.noAnswer))
    if elapsed > 0 then
        panel.rate = math.floor((activity.answered - panel.lastAnswered) / elapsed + 0.5)
        panel.lastAnswered = activity.answered
    end
    panel.waiting:SetText(string.format("Waiting %d, asking now %d, %d %s a second",
        activity.waiting, activity.asking, panel.rate, panel.rate == 1 and "item" or "items"))
end

local function progressTooltip(bar)
    local status = bar.status
    if not (GameTooltip and status) then
        return
    end
    GameTooltip:SetOwner(bar, "ANCHOR_BOTTOM")
    GameTooltip:SetText(bar.title)
    GameTooltip:AddLine(status.loaded .. " loaded", 0.4, 0.9, 0.4)
    GameTooltip:AddLine(status.loading .. " loading", 1, 1, 1)
    if status.failed > 0 then
        GameTooltip:AddLine(status.failed .. " could not be loaded", 1, 0.4, 0.3)
        GameTooltip:AddLine("Click to try those again.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- A loading bar in the window's top row, `left` across and `width` wide.
local function createProgress(parent, left, width, title, describe)
    local bar = CreateFrame("Button", nil, parent)
    bar:SetSize(width, PROGRESS_HEIGHT)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -(PADDING + 7))
    bar.title, bar.describe = title, describe
    bar:RegisterForClicks("LeftButtonUp")

    bar.background = bar:CreateTexture(nil, "BACKGROUND")
    bar.background:SetAllPoints()
    bar.background:SetColorTexture(0, 0, 0, 0.6)

    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.fill:SetHeight(PROGRESS_HEIGHT)
    bar.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar.fill:SetVertexColor(0.2, 0.6, 0.2)

    bar.failedFill = bar:CreateTexture(nil, "ARTWORK")
    bar.failedFill:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    bar.failedFill:SetHeight(PROGRESS_HEIGHT)
    bar.failedFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar.failedFill:SetVertexColor(0.7, 0.15, 0.1)

    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- Held at both ends and never wrapped: a long count is cut short with
    -- "...", not run out past the bar.
    bar.text:SetPoint("LEFT", bar, "LEFT", 4, 0)
    bar.text:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    bar.text:SetWordWrap(false)

    -- Items arrive, and are given up on, without a redraw: count again
    -- every so often while the bar shows.
    bar.sinceCount = 0
    bar:SetScript("OnUpdate", function(self, elapsed)
        self.sinceCount = self.sinceCount + (elapsed or 0)
        if self.sinceCount >= PROGRESS_POLL then
            self.sinceCount = 0
            updateProgress(self)
        end
    end)
    bar:SetScript("OnClick", function(self)
        if self.status and self.status.failed > 0 then
            ns.LootRow.Retry(self.itemIDs)
            updateProgress(self)
        end
    end)
    bar:SetScript("OnEnter", progressTooltip)
    bar:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    bar:Hide()
    return bar
end

-- The big model, while it is open: the picked boss, or closed for a pick
-- with no model.
local function drawModelView(instance, selection)
    local view = frame.modelView
    if not view:IsShown() then
        return
    end
    local boss = instance and type(selection) == "number" and instance.bosses[selection]
    if not (boss and boss.display) then
        view:Hide()
        return
    end
    view.title:SetText(boss.name)
    if view.model.shownDisplay == boss.display then
        return
    end
    if ns.Portrait.SetModel(view.model, boss.display) then
        view.model.shownDisplay = boss.display
        view.model.turnedByHand = false
    else
        view:Hide()
    end
end

--- Open the big model of the picked boss.
function Window.OpenModel()
    if not frame then
        return
    end
    frame.modelView:Show()
    drawModelView(Window.Current())
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
    if not boss then
        header.model:Hide()
        header.portrait:Hide()
        header.title:SetText(instance.name)
        header.subtitle:SetText("")
        return
    end
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
            header.model.turnedByHand = false
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

    -- A cleared search lets go of the item it picked.
    if frame.search:GetText() == "" then
        highlightItem = nil
    end

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

    local mapOpen = frame.fullMap:IsShown()
    local lootList = mapOpen and frame.mapLoot or frame.loot
    if mapOpen then
        -- Straight under the last boss row showing, and down to the bottom.
        local showing = math.min(#bossEntries - frame.bosses.offset, BOSS_ROWS_WITH_MAP)
        local more = #bossEntries - frame.bosses.offset > BOSS_ROWS_WITH_MAP
        local top = TOP + math.max(0, showing) * BOSS_ROW + (more and MORE_HEIGHT or 0) + 6
        frame.mapLoot:ClearAllPoints()
        frame.mapLoot:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + RAIL_WIDTH + GAP, -top)
        ns.List.SetVisibleRows(frame.mapLoot, math.floor((HEIGHT - top - PADDING - MORE_HEIGHT) / LOOT_ROW))
    end
    local loot = Window.LootEntries(instance, selection, mapOpen and 1 or 2)
    local key = tostring(view.instance) .. ":" .. tostring(selection) .. (mapOpen and ":map" or "")
    ns.List.SetEntries(lootList, loot, key == lastSelection)
    lastSelection = key
    for position, entry in ipairs(loot) do
        if entry.selected then
            ns.List.Reveal(lootList, position)
            break
        end
    end
    frame.empty:ClearAllPoints()
    frame.empty:SetPoint("TOPLEFT", lootList, "TOPLEFT", 6, -6)
    frame.empty:SetShown(instance ~= nil and #loot == 0)

    drawHeader(instance, selection)
    drawModelView(instance, selection)
    frame.progress.itemIDs = instance and ns.Index.ItemIDs(instance.key) or {}
    updateProgress(frame.progress)
    if frame.debug:IsShown() then
        updateDetails(frame.debug, 0)
    end
    local pinned = type(selection) == "number" and selection or nil
    ns.MapView.Show(frame.inset, instance, pinned)
    if frame.fullMap:IsShown() then
        ns.MapView.Show(frame.fullMap.view, instance, pinned)
        frame.fullMap.title:SetText(instance and instance.name or "")
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
        highlightItem = entry.value
        Window.SelectItem(entry.value)
    elseif entry.kind == "place" then
        highlightItem = entry.value.item
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

-- The game's own search box: a magnifying glass, the word "Search" in grey
-- while it is empty, and a clear button. SearchBoxTemplate draws all three and
-- shows and hides the word from its own OnTextChanged, so a box made from it
-- is hooked, never given a script of ours in that slot. On a client without
-- it, an input box gets the glass and the word drawn here.
local SEARCH_ICON = "Interface\\Common\\UI-Searchbox-Icon"

local function createSearchBox(parent)
    local ok, box = pcall(CreateFrame, "EditBox", nil, parent, "SearchBoxTemplate")
    if ok and box and box.Instructions then
        box.hint = box.Instructions
        return box
    end
    if ok and box then
        box:Hide() -- a template of that name, but not the box this expects
    end
    box = createFrame("EditBox", nil, parent, "InputBoxTemplate")
    box.icon = box:CreateTexture(nil, "OVERLAY")
    box.icon:SetTexture(SEARCH_ICON)
    box.icon:SetSize(14, 14)
    box.icon:SetPoint("LEFT", box, "LEFT", 0, -1)
    box:SetTextInsets(16, 4, 0, 0)
    -- On the box itself: a string on the window would draw under the box's art.
    box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    box.hint:SetPoint("LEFT", box, "LEFT", 18, 0)
    box.hint:SetText(SEARCH or "Search")
    box:HookScript("OnTextChanged", function(self)
        box.hint:SetShown(self:GetText() == "")
    end)
    return box
end

-- A close button like every other window's, at the template's own size, or
-- a plain "X" if the template has no picture.
local function createCloseButton(parent, onClick)
    local close = createFrame("Button", nil, parent, "UIPanelCloseButton")
    if not (close.GetNormalTexture and close:GetNormalTexture()) then
        close:SetText("X")
    end
    close:SetScript("OnClick", onClick)
    return close
end

-- A window's dressing: opaque, whatever the backdrop does -- the dialog
-- background is translucent by design, and may not load at all -- inside
-- the dialog border.
local function dress(target)
    target.background = target:CreateTexture(nil, "BACKGROUND", nil, -8)
    target.background:SetPoint("TOPLEFT", target, "TOPLEFT", 4, -4)
    target.background:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", -4, 4)
    target.background:SetColorTexture(0.06, 0.045, 0.03, 1)
    if target.SetBackdrop then
        target:SetBackdrop({
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
end

-- A window's frame: the options window's own, the name in its title bar and
-- its red X, so this reads as one of the game's windows. On a client without
-- it, the dialog border, a name and a close button of our own. Solid either
-- way: the options window lets the world show through, which the loot text
-- cannot bear. With a logo, it sits before the name; without, a long name
-- (a boss's) is cut short before the X.
local function createWindowFrame(name, parent, logo)
    local ok, made = pcall(CreateFrame, "Frame", name, parent, "SettingsFrameTemplate")
    if not (ok and made) then
        made = createFrame("Frame", name, parent, "BackdropTemplate")
    end
    local native = made.NineSlice and made.NineSlice.Text and made.ClosePanelButton and made.Bg

    local titleY
    if native then
        -- On the game's background, so under its border and title bar too;
        -- the same dark as dress's.
        made.background = made.Bg:CreateTexture(nil, "BACKGROUND", nil, 7)
        made.background:SetAllPoints(made.Bg)
        made.background:SetColorTexture(0.06, 0.045, 0.03, 1)
        made.title = made.NineSlice.Text
        made.close = made.ClosePanelButton
        titleY = -5
    else
        dress(made)
        made.title = made:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        made.close = createCloseButton(made)
        made.close:SetPoint("TOPRIGHT", made, "TOPRIGHT", -4, -4)
        titleY = -14
    end

    made.title:ClearAllPoints()
    made.title:SetWordWrap(false)
    if logo then
        made.title:SetPoint("TOP", made, "TOP", (LOGO + LOGO_GAP) / 2, titleY)
        -- Drawn with the name, so over the title bar.
        made.logo = made.title:GetParent():CreateTexture(nil, "OVERLAY")
        made.logo:SetSize(LOGO, LOGO)
        made.logo:SetPoint("RIGHT", made.title, "LEFT", -LOGO_GAP, 0)
        made.logo:SetTexture(logo)
    else
        made.title:SetPoint("TOP", made, "TOP", 0, titleY)
        made.title:SetPoint("LEFT", made, "LEFT", 60, 0)
        made.title:SetPoint("RIGHT", made, "RIGHT", -60, 0)
    end

    -- Our own, not the game's: that asks the window manager, which an addon
    -- may not do in combat.
    made.close:SetScript("OnClick", function()
        made:Hide()
    end)
    return made
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

-- The item loading details, for testing, under the window: a bar for every
-- item, and what the queue is doing, counted twice a second. /bl debug.
local function createDebugPanel(parent)
    local panel = createFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(WIDTH, DEBUG_HEIGHT)
    panel:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, 2)
    dress(panel)

    panel.progress = createProgress(panel, PADDING + 4, WIDTH - 2 * PADDING - 8, "Item data the server has sent", describeAll)
    panel.progress.keepWhenDone = true
    panel.progress.serverOnly = true
    panel.asked = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.asked:SetPoint("TOPLEFT", panel.progress, "BOTTOMLEFT", 0, -6)
    panel.waiting = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.waiting:SetPoint("TOPLEFT", panel.progress, "BOTTOMLEFT", WIDTH / 2, -6)

    panel.rate, panel.lastAnswered, panel.sinceCount = 0, 0, 0
    panel:SetScript("OnShow", function(self)
        self.rate, self.lastAnswered, self.sinceCount = 0, ns.LootRow.Activity().answered, 0
        updateDetails(self, 0)
    end)
    panel:SetScript("OnUpdate", function(self, elapsed)
        self.sinceCount = self.sinceCount + (elapsed or 0)
        if self.sinceCount >= PROGRESS_POLL then
            updateDetails(self, self.sinceCount)
            self.sinceCount = 0
        end
    end)
    panel:SetShown(ns.db.debug)
    return panel
end

-- A boss's model that turns slowly by itself, and with the cursor when
-- dragged; it then stays where it is left until given another boss, which
-- clears `turnedByHand`. A press and release without a drag is a click.
local function makeTurnable(model, onClick)
    model.facing = 0
    model:EnableMouse(true)

    local function cursorX(self)
        return GetCursorPosition() / self:GetEffectiveScale()
    end
    -- Turn by how far the cursor has moved since last looked at.
    local function follow(self)
        local x = cursorX(self)
        if x ~= self.dragX then
            self.dragged = self.dragged + math.abs(x - self.dragX)
            self.facing = self.facing + (x - self.dragX) * TURN_PER_PIXEL
            self.dragX = x
            self.turnedByHand = true
        end
    end

    model:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.dragX, self.dragged = cursorX(self), 0
        end
    end)
    model:SetScript("OnMouseUp", function(self)
        if not self.dragX then
            return
        end
        follow(self)
        self.dragX = nil
        if self.dragged < CLICK_SLOP and onClick then
            onClick()
        end
    end)
    model:SetScript("OnUpdate", function(self, elapsed)
        if self.dragX then
            follow(self)
        elseif not self.turnedByHand then
            self.facing = self.facing + (elapsed or 0) * 0.4
        end
        self.facing = self.facing % (math.pi * 2)
        if self.SetFacing then
            self:SetFacing(self.facing)
        end
    end)
end

-- The big model, in a window of its own beside the main one: the picked
-- boss, to turn by dragging and zoom with the mouse wheel.
local function createModelView(parent)
    local view = createWindowFrame(nil, parent)
    view:SetSize(MODEL_VIEW_WIDTH, HEIGHT)
    view:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, 0)
    view:SetClampedToScreen(true)
    view:EnableMouse(true)

    local stageHeight = HEIGHT - TOP - PADDING - MODEL_HINT_HEIGHT
    panel(view, PADDING, TOP, MODEL_VIEW_WIDTH - 2 * PADDING, stageHeight, 0.12)

    view.model = CreateFrame("PlayerModel", nil, view)
    view.model:SetPoint("TOPLEFT", view, "TOPLEFT", PADDING, -TOP)
    view.model:SetSize(MODEL_VIEW_WIDTH - 2 * PADDING, stageHeight)
    makeTurnable(view.model)
    view.model.distance = 1
    view.model:EnableMouseWheel(true)
    view.model:SetScript("OnMouseWheel", function(self, delta)
        local step = delta > 0 and 1 / MODEL_ZOOM_STEP or MODEL_ZOOM_STEP
        self.distance = math.max(MODEL_NEAREST, math.min(MODEL_FARTHEST, self.distance * step))
        if self.SetCamDistanceScale then
            self:SetCamDistanceScale(self.distance)
        end
    end)

    view.hint = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.hint:SetPoint("BOTTOM", view, "BOTTOM", 0, PADDING + 4)
    view.hint:SetText("Drag to turn, scroll to zoom")

    -- Shown again, the model is set afresh: one kept while hidden can come
    -- back blank.
    view:SetScript("OnHide", function()
        view.model.shownDisplay = nil
    end)
    view:Hide()
    return view
end

local function createHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", PAGE_LEFT, -TOP)
    header:SetSize(PAGE_WIDTH, HEADER_HEIGHT)

    -- The boss, turning slowly; a click opens the big model.
    header.model = CreateFrame("PlayerModel", nil, header)
    header.model:SetSize(84, 84)
    header.model:SetPoint("LEFT", header, "LEFT", 4, 0)
    makeTurnable(header.model, function()
        Window.OpenModel()
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
    -- The chest alone, as the minimap button shows it, before the name: the
    -- AddOns list icon carries a square tile that reads as a sticker here.
    frame = createWindowFrame("BossLootFrame", UIParent, "Interface\\AddOns\\BossLoot\\minimap")
    frame.title:SetText("BossLoot")
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

    local columnHeight = HEIGHT - TOP - PADDING
    panel(frame, PADDING, TOP, RAIL_WIDTH, columnHeight, 0.035)
    panel(frame, PADDING + RAIL_WIDTH + GAP, TOP, BOSS_WIDTH, columnHeight, 0.05)
    panel(frame, PAGE_LEFT, TOP, PAGE_WIDTH, HEADER_HEIGHT, 0.12)

    -- Escape closes it, like every other window.
    table.insert(UISpecialFrames, "BossLootFrame")

    -- One window at a time: the options window opening closes this one.
    if SettingsPanel and SettingsPanel.HookScript then
        SettingsPanel:HookScript("OnShow", function()
            frame:Hide()
        end)
    end

    frame.progress = createProgress(frame, PAGE_LEFT, PROGRESS_WIDTH, "Items in this instance", describeInstance)
    frame.debug = createDebugPanel(frame)
    frame.allProgress = frame.debug.progress

    -- The rail: search, tabs, instances.
    local search = createSearchBox(frame)
    search:SetSize(RAIL_WIDTH - 14, SEARCH_HEIGHT)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 8, -TOP - 2)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    frame.searchHint = search.hint
    search:HookScript("OnTextChanged", function()
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
    frame.bossRows = frame.bosses.options.rows

    -- Where the loot goes while the big map is open: under the boss list,
    -- one tile across. Built with rows enough to fill the column from its
    -- top; Refresh moves it under the last boss and uses as many as fit.
    frame.mapLoot = ns.List.Create(frame, {
        width = BOSS_WIDTH, rowHeight = LOOT_ROW,
        rows = math.floor((HEIGHT - TOP - 6 - PADDING - MORE_HEIGHT) / LOOT_ROW),
        createRow = ns.LootRow.Create, renderRow = ns.LootRow.Render,
    })
    frame.mapLoot:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + RAIL_WIDTH + GAP, -TOP)
    frame.mapLoot:Hide()

    -- The boss page: header with model and map inset, then the loot grid.
    frame.header = createHeader(frame)
    frame.modelView = createModelView(frame)

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
        -- A ball big enough for a two-digit number.
        pinSize = 26,
        labels = true,
        zoom = true,
        onPinClick = function(bossIndex)
            Window.SelectBoss(bossIndex)
            Window.CloseMap()
        end,
    })
    frame.fullMap.view:SetPoint("TOPLEFT", frame.fullMap, "TOPLEFT", 0, 0)
    -- The instance's name in the corner, above the map so it draws over it.
    frame.fullMap.title = frame.fullMap.view.overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.fullMap.title:SetPoint("TOPLEFT", frame.fullMap.view, "TOPLEFT", 10, -8)
    frame.fullMap.close = createCloseButton(frame.fullMap, function()
        Window.CloseMap()
    end)
    frame.fullMap.close:SetPoint("TOPRIGHT", frame.fullMap, "TOPRIGHT", 0, 0)
    -- Above the pins, which can sit right under it (Blackrock Depths' 25).
    frame.fullMap.close:SetFrameLevel(frame.fullMap.view:GetFrameLevel() + 10)
    frame.fullMap:Hide()

    -- Items are asked for only as their rows come on screen: every row
    -- shows from the built-in names meanwhile, and a server asked for every
    -- item at once answered none of them.
    frame:SetScript("OnShow", function()
        Window.Refresh()
    end)

    frame:Hide()
end

function Window.Frame()
    return frame
end

-- The click the options window makes as it opens on an addon's page, so every
-- addon's window sounds alike. Closing is silent, as it is there.
local function playOpenSound()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
    end
end

function Window.Open()
    if not frame then
        create()
    end
    -- One window at a time: the options window and BankBags' close.
    if ns.CloseOptions then
        ns.CloseOptions()
    end
    if _G.BankBagsFrame then
        _G.BankBagsFrame:Hide()
    end
    if not frame:IsShown() then
        playOpenSound()
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

--- Show or hide the item loading details under the window.
function Window.SetDebug(on)
    ns.db.debug = on and true or false
    if frame then
        frame.debug:SetShown(ns.db.debug)
    end
end

--- How many instances the player has hidden from the list.
function Window.HiddenCount()
    local count = 0
    for _ in pairs(ns.db.hidden) do
        count = count + 1
    end
    return count
end

--- Put every hidden instance back on the list.
function Window.UnhideAll()
    for key in pairs(ns.db.hidden) do
        ns.db.hidden[key] = nil
    end
    everyItemList = nil
    Window.Refresh()
end

ns.RegisterCommand("debug", "Show or hide the item loading details", function()
    Window.SetDebug(not ns.db.debug)
    ns.Print(ns.db.debug and "Item loading details on." or "Item loading details off.")
end)

ns.RegisterCommand("unhide", "Bring back every instance you hid", function()
    Window.UnhideAll()
    ns.Print("Every instance is back on the list.")
end)

-- Items arrive in bursts as an instance loads; redraw once per burst.
local redrawPending = false
local events = CreateFrame("Frame")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, _, itemID, success)
    ns.LootRow.Arrived(itemID, success)
    if redrawPending or not (frame and frame:IsShown()) then
        return
    end
    redrawPending = true
    C_Timer.After(0.1, function()
        redrawPending = false
        Window.Refresh()
    end)
end)
