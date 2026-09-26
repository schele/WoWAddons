local addonName, ns = ...

-- One row of the loot column: an item's icon, its name in its quality colour,
-- a grey line under it, and the drop chance on the right. It behaves like an
-- item anywhere else in the game: hover for the tooltip, shift-click to link,
-- ctrl-click to preview.

local LootRow = {}
ns.LootRow = LootRow

LootRow.HEIGHT = 30

local ICON_SIZE = 26
local CHANCE_WIDTH = 48
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- What the client itself knows about an item, or nil if it has not loaded it.
local function clientInfo(itemID)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get then
        return nil
    end

    local name, link, quality, _, _, itemType, itemSubType, _, equipLoc, icon = get(itemID)
    if not name then
        return nil
    end

    return {
        name = name, link = link, quality = quality, itemType = itemType,
        itemSubType = itemSubType, equipLoc = equipLoc, icon = icon,
    }
end

--- What is known about an item: the client's copy when it has one (saved for
-- next time), else the copy saved in an earlier session, else the one built
-- into the addon, else nil. A copy saved before the last patch comes back
-- with `stale` set, a built-in one with `builtIn`.
function LootRow.ItemInfo(itemID)
    local info = clientInfo(itemID)
    if info then
        ns.ItemCache.Put(itemID, info)
        return info
    end
    return ns.ItemCache.Get(itemID) or ns.ItemData.Get(itemID)
end

-- Whether the server has ever said what the item is: the client has it, or
-- a copy was saved. Cheap: no copy is made.
local function fromServer(itemID)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    return (get ~= nil and get(itemID) ~= nil) or ns.ItemCache.Has(itemID)
end

-- Asking the server for items. The server has no patience: asked eight at
-- once, thirty-two a second, it refused or dropped most of them -- over half
-- of every item, all real ones. So requests go out one at a time, a moment
-- apart, with no more than a few unanswered at once: the next goes when an
-- answer frees a place, so the server sets the pace. What is on screen goes
-- first. An item with no answer, or an empty one, is asked for again, after
-- a longer wait each time, and given up on only after several tries.
local TICK = 0.1         -- seconds between requests, at the most
local MAX_IN_FLIGHT = 4  -- requests out, unanswered, at once
local TIMEOUT = 10       -- seconds to wait for an answer before asking again
local RETRY_DELAYS = { 5, 15, 45, 90, 180 } -- seconds before each try after an empty answer
local MAX_TRIES = 6
LootRow.MAX_IN_FLIGHT, LootRow.MAX_TRIES = MAX_IN_FLIGHT, MAX_TRIES

local queue = {}         -- item ids waiting to be asked for, in order
local waiting = {}       -- id -> true while in the queue
local inFlight = {}      -- id -> when it was asked for
local later = {}         -- id -> when it goes back in the queue, after an empty answer
local tries = {}         -- id -> times asked for
local failed = {}        -- id -> true once an answer came back empty
local sentThisTick = false
local ticking = false
-- What the queue has done this session, for the loading details.
local counts = { asked = 0, answered = 0, empty = 0, noAnswer = 0 }

local function now()
    return GetTime and GetTime() or 0
end

local function count(set)
    local n = 0
    for _ in pairs(set) do
        n = n + 1
    end
    return n
end

-- Nothing to ask for: the client has the item, or it was saved under this
-- build of the game. A built-in copy is still asked about: the server's is
-- in the client's language, and has what the tooltip needs.
local function loaded(itemID)
    local info = LootRow.ItemInfo(itemID)
    return info ~= nil and not info.stale and not info.builtIn
end

-- Room to ask now: nothing asked yet this moment, and a place free.
local function canSend()
    return not sentThisTick and count(inFlight) < MAX_IN_FLIGHT
end

local function send(itemID)
    sentThisTick = true
    tries[itemID] = (tries[itemID] or 0) + 1
    inFlight[itemID] = now()
    counts.asked = counts.asked + 1
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    elseif GetItemInfo then
        -- Older clients start loading on any lookup.
        GetItemInfo(itemID)
    end
end

local tick

local function schedule()
    if ticking or not (C_Timer and C_Timer.After) then
        return
    end
    ticking = true
    C_Timer.After(TICK, tick)
end

local function enqueue(itemID, urgent)
    if waiting[itemID] then
        if urgent then
            for index, queued in ipairs(queue) do
                if queued == itemID then
                    table.remove(queue, index)
                    break
                end
            end
            table.insert(queue, 1, itemID)
        end
        return
    end
    waiting[itemID] = true
    if urgent then
        table.insert(queue, 1, itemID)
    else
        table.insert(queue, itemID)
    end
    schedule()
end

function tick()
    ticking = false
    sentThisTick = false
    local time = now()

    -- No answer for too long: the request was dropped. Ask again, in turn.
    for itemID, asked in pairs(inFlight) do
        if time - asked >= TIMEOUT then
            inFlight[itemID] = nil
            counts.noAnswer = counts.noAnswer + 1
            if (tries[itemID] or 0) < MAX_TRIES then
                enqueue(itemID)
            else
                failed[itemID] = true
            end
        end
    end

    -- Waited long enough after an empty answer: back in the queue.
    for itemID, due in pairs(later) do
        if due <= time then
            later[itemID] = nil
            enqueue(itemID)
        end
    end

    -- The next one, if there is room. Only the front of the queue is looked
    -- at: with every item in the game waiting, looking them all over each
    -- moment would stall the game. Items loaded meanwhile drop out here.
    while #queue > 0 and canSend() do
        local itemID = table.remove(queue, 1)
        waiting[itemID] = nil
        if not loaded(itemID) then
            send(itemID)
        end
    end

    if #queue > 0 or next(inFlight) or next(later) then
        schedule()
    end
end

--- Ask the server for an item: now if there is room, otherwise in turn.
-- `urgent` (a row on screen) goes ahead of the rest.
function LootRow.RequestLoad(itemID, urgent)
    if loaded(itemID) or inFlight[itemID] or later[itemID] then
        return
    end
    if failed[itemID] and (tries[itemID] or 0) >= MAX_TRIES then
        return
    end
    if canSend() and not waiting[itemID] then
        send(itemID)
        schedule()
        return
    end
    enqueue(itemID, urgent)
end

--- The server's answer about an item (GET_ITEM_INFO_RECEIVED). An empty one
-- is asked about again after a wait that grows with each try, up to the
-- limit; meanwhile the row says the item is not loaded yet, or keeps showing
-- its saved copy. A full one is saved, whether or not its row is on screen.
function LootRow.Arrived(itemID, success)
    inFlight[itemID] = nil
    if success == false then
        counts.empty = counts.empty + 1
        failed[itemID] = true
        local asked = tries[itemID] or 0
        if asked < MAX_TRIES then
            later[itemID] = now() + RETRY_DELAYS[math.max(1, math.min(asked, #RETRY_DELAYS))]
            schedule()
        end
    else
        counts.answered = counts.answered + 1
        failed[itemID] = nil
        LootRow.ItemInfo(itemID)
    end
end

--- What the queue has done this session: requests `asked`, answers with the
-- item (`answered`), empty answers, requests that timed out (`noAnswer`);
-- and now, items `waiting` their turn (or a retry) and requests out (`asking`).
function LootRow.Activity()
    return {
        asked = counts.asked, answered = counts.answered, empty = counts.empty,
        noAnswer = counts.noAnswer, waiting = #queue + count(later), asking = count(inFlight),
    }
end

-- Given up on: every try came back empty or not at all.
local function givenUp(itemID)
    return failed[itemID] and (tries[itemID] or 0) >= MAX_TRIES
        and not inFlight[itemID] and not waiting[itemID] and not later[itemID]
end

-- Items seen loaded this session, and seen from the server. Items do not
-- unload, and a count of every item in the game, twice a second, should not
-- look each one up again.
local seenLoaded = {}
local seenFromServer = {}

--- How far a list of items has loaded: counts of the items that are loaded
-- (any copy: the client's, a saved one, the built-in one; or with
-- `serverOnly`, only those the server has sent), still loading, and given up on.
function LootRow.Status(itemIDs, serverOnly)
    local seen = serverOnly and seenFromServer or seenLoaded
    local status = { total = #itemIDs, loaded = 0, loading = 0, failed = 0 }
    for _, itemID in ipairs(itemIDs) do
        local known = seen[itemID]
        if not known then
            if serverOnly then
                known = fromServer(itemID)
            else
                known = LootRow.ItemInfo(itemID) ~= nil
            end
        end
        if known then
            seen[itemID] = true
            status.loaded = status.loaded + 1
        elseif givenUp(itemID) then
            status.failed = status.failed + 1
        else
            status.loading = status.loading + 1
        end
    end
    return status
end

--- Ask again, from scratch, for those of the items given up on.
function LootRow.Retry(itemIDs)
    for _, itemID in ipairs(itemIDs) do
        if givenUp(itemID) and not loaded(itemID) then
            tries[itemID], failed[itemID] = 0, nil
            LootRow.RequestLoad(itemID, true)
        end
    end
end

-- The icon lookup by ID works before the item itself has loaded, so even a
-- placeholder row shows the right picture.
local function iconFor(itemID, info)
    if info and info.icon then
        return info.icon
    end
    if C_Item and C_Item.GetItemIconByID then
        local icon = C_Item.GetItemIconByID(itemID)
        if icon then
            return icon
        end
    end
    return UNKNOWN_ICON
end

local function showTooltip(row)
    if not (row.entry and GameTooltip) then
        return
    end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(row.entry.id)
    else
        GameTooltip:SetHyperlink("item:" .. row.entry.id)
    end
    GameTooltip:Show()
end

local function hideTooltip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

-- Shift-click links in chat, ctrl-click opens the dressing room: the game's
-- own handler does both, the same as for an item in your bags.
local function click(row)
    if row.link and HandleModifiedItemClick then
        HandleModifiedItemClick(row.link)
    end
end

function LootRow.Create(list)
    local row = CreateFrame("Button", nil, list)
    row:SetSize(list.options.columnWidth or list.options.width, LootRow.HEIGHT)
    row:RegisterForClicks("LeftButtonUp")

    -- The band behind the item picked from a search.
    row.selectedTexture = row:CreateTexture(nil, "BACKGROUND")
    row.selectedTexture:SetAllPoints()
    row.selectedTexture:SetColorTexture(1, 0.82, 0, 0.18)
    row.selectedTexture:Hide()

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -CHANCE_WIDTH, 0)
    row.name:SetJustifyH("LEFT")

    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 0)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -CHANCE_WIDTH, 0)
    row.detail:SetJustifyH("LEFT")
    -- One line each: wrapped, a long type line ("Main Hand, One-Handed Swords")
    -- runs up into the name. Cut short with "..." instead.
    row.name:SetWordWrap(false)
    row.detail:SetWordWrap(false)

    row.chance = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.chance:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.chance:SetJustifyH("RIGHT")

    row:SetScript("OnEnter", showTooltip)
    row:SetScript("OnLeave", hideTooltip)
    row:SetScript("OnClick", click)

    return row
end

function LootRow.Render(row, entry)
    row.entry = entry
    local info = LootRow.ItemInfo(entry.id)

    row.icon:SetTexture(iconFor(entry.id, info))

    if info then
        row.name:SetText(ns.Format.Colored(info.name, info.quality))
        row.link = info.link
        if info.stale or info.builtIn then
            -- Saved before a patch, or built in: shown as it is, and asked
            -- about behind the rows that have nothing to show yet.
            LootRow.RequestLoad(entry.id)
        end
    elseif failed[entry.id] then
        row.name:SetText("|cff808080Item " .. entry.id .. " (not loaded yet)|r")
        row.link = nil
        LootRow.RequestLoad(entry.id, true)
    else
        row.name:SetText("|cff808080Loading item " .. entry.id .. "...|r")
        row.link = nil
        LootRow.RequestLoad(entry.id, true)
    end

    if entry.sources then
        row.detail:SetText(table.concat(entry.sources, ", "))
    elseif info then
        row.detail:SetText(ns.Format.TypeLabel(info.itemType, info.itemSubType, info.equipLoc))
    else
        row.detail:SetText("")
    end

    row.chance:SetText(ns.Format.Chance(entry.chance))
    row.selectedTexture:SetShown(entry.selected and true or false)
end
