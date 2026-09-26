local addonName, ns = ...

-- Items the server has sent, kept between sessions, so the loot lists fill in
-- at once instead of asking the server for hundreds of items every time.
-- Only what a row shows is kept -- name, link, quality, type, slot, icon; the
-- tooltip, with the stats, always comes from the client.
--
-- A patch can change an item, so the cache remembers the game's build. After
-- one, every saved item moves to `previous`: still shown, but asked about
-- again when it is next on screen, and moved back once the server answers.
-- Names are in the client's language, so a new language starts afresh.

local ItemCache = {}
ns.ItemCache = ItemCache

ns.AddDefaults({
    itemCache = { items = {}, previous = {} },
})

local cache -- BossLootDB.itemCache, from login on

local function clientBuild()
    if not GetBuildInfo then
        return ""
    end
    local version, build = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build)
end

local function clientLocale()
    return GetLocale and GetLocale() or ""
end

--- Take up the saved cache, checking it against the client's language and build.
function ItemCache.Load(saved)
    local locale, build = clientLocale(), clientBuild()
    if saved.locale ~= locale then
        saved.items, saved.previous = {}, {}
    elseif saved.build ~= build then
        for itemID, entry in pairs(saved.items) do
            saved.previous[itemID] = entry
        end
        saved.items = {}
    end
    saved.locale, saved.build = locale, build
    cache = saved
end

ns.OnLogin(function()
    ItemCache.Load(ns.db.itemCache)
end)

-- Saved as a list, not a keyed table: a couple of thousand items are
-- written out on every logout.
local function pack(info)
    return { info.name, info.link, info.quality, info.itemType, info.itemSubType, info.equipLoc, info.icon }
end

local function same(entry, info)
    return entry[1] == info.name and entry[2] == info.link and entry[3] == info.quality
        and entry[4] == info.itemType and entry[5] == info.itemSubType
        and entry[6] == info.equipLoc and entry[7] == info.icon
end

--- A saved item, in the shape LootRow.ItemInfo gives, or nil. One saved
-- before the last patch has `stale` set.
function ItemCache.Get(itemID)
    if not cache then
        return nil
    end
    local entry = cache.items[itemID]
    local stale = false
    if not entry then
        entry = cache.previous[itemID]
        stale = entry ~= nil
    end
    if not entry then
        return nil
    end
    return {
        name = entry[1], link = entry[2], quality = entry[3], itemType = entry[4],
        itemSubType = entry[5], equipLoc = entry[6], icon = entry[7], stale = stale,
    }
end

--- Save what the client says about an item. Called on every lookup, so an
-- unchanged item costs a comparison, not a new table.
function ItemCache.Put(itemID, info)
    if not cache then
        return
    end
    local entry = cache.items[itemID]
    if entry and same(entry, info) then
        return
    end
    cache.items[itemID] = pack(info)
    cache.previous[itemID] = nil
end
