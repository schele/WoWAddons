local addonName, ns = ...

-- Which buttons hold an older rank than the highest the character knows.
-- Reading only: no frames and no changes, so its answers can be tested
-- without a client. Every lookup tries C_Spell first and the old global
-- second: this client moved GetSpellInfo into C_Spell without warning.

local Ranks = {}
ns.Ranks = Ranks

-- Classic's bars and the druid's form pages are slots 1 to 120; the newer
-- bars 6 to 8 are 145 to 180. A slot this client does not have reads empty.
Ranks.LAST_SLOT = 180

function Ranks.Slots()
    local slots = {}
    for slot = 1, Ranks.LAST_SLOT do
        slots[slot] = slot
    end
    return slots
end

local function nameOf(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        return type(info) == "table" and info.name or nil
    end
    if GetSpellInfo then
        return (GetSpellInfo(spellID))
    end
    return nil
end

--- Asked by name, the client answers with the highest rank known: the one
-- a `/cast` macro without a rank casts.
local function topRank(name)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(name)
        return type(info) == "table" and info.spellID or nil
    end
    if GetSpellInfo then
        return (select(7, GetSpellInfo(name)))
    end
    return nil
end

--- A spell's rank as the client words it ("Rank 5"), or nil for a spell
-- with none.
function Ranks.RankText(spellID)
    return ns.Guarded(function()
        local text
        if C_Spell and C_Spell.GetSpellSubtext then
            text = C_Spell.GetSpellSubtext(spellID)
        elseif GetSpellSubtext then
            text = GetSpellSubtext(spellID)
        end
        if type(text) == "string" and text ~= "" then
            return text
        end
        return nil
    end, nil)
end

-- The number in a rank's words, to find the lowest of several. Words with
-- no number sort last, so the rank seen first stands.
local function rankNumber(text)
    local digits = type(text) == "string" and text:match("%d+")
    return digits and tonumber(digits) or math.huge
end

--- Whether `top` is a lower or the same rank as `id`, by the numbers in
-- their words. A client listing every rank might answer a name with the
-- first it finds, and putting that on the bar would be a downgrade. Words
-- without a number ("Journeyman") cannot be compared, so they never block.
local function notHigher(id, top)
    local from, to = rankNumber(Ranks.RankText(id)), rankNumber(Ranks.RankText(top))
    return from ~= math.huge and to ~= math.huge and to <= from
end

--- What an outdated slot holds, { id, name, top }, or nil. One guarded read,
-- so a client that raises on any part of it costs that slot and no other.
local function readSlot(slot)
    return ns.Guarded(function()
        local kind, id = GetActionInfo(slot)
        if kind ~= "spell" or type(id) ~= "number" then
            return nil
        end

        local name = nameOf(id)
        local top = type(name) == "string" and topRank(name) or nil
        if type(top) == "number" and top ~= id and not notHigher(id, top) then
            return { id = id, name = name, top = top }
        end
        return nil
    end, nil)
end

--- Every outdated button, grouped by spell and sorted by its name. Empty
-- when every button holds the highest rank.
function Ranks.Outdated()
    local groups, byName = {}, {}

    for _, slot in ipairs(Ranks.Slots()) do
        local found = readSlot(slot)
        if found then
            local fromRank = Ranks.RankText(found.id)
            local group = byName[found.name]
            if not group then
                group = {
                    name = found.name,
                    fromRank = fromRank,
                    toRank = Ranks.RankText(found.top),
                    toID = found.top,
                    slots = {},
                }
                byName[found.name] = group
                table.insert(groups, group)
            elseif rankNumber(fromRank) < rankNumber(group.fromRank) then
                group.fromRank = fromRank
            end
            table.insert(group.slots, slot)
        end
    end

    table.sort(groups, function(a, b)
        return a.name < b.name
    end)
    return groups
end
