local addonName, ns = ...

-- The water here: the zone the player is in, and whether the game will let
-- them fish it.
--
-- Every zone has a Fishing minimum. Far under it WoW Forever refuses the
-- cast ("Skill not high enough", with no number): a level 55 zone did at
-- 106. Nearer, it lets the cast go but every fish gets away ("Your fish got
-- away!"): Stranglethorn Vale did at 155. Over it, some fish still get away.
-- The old game's rule had a hundredth more fish land for each point of skill
-- until every fish did, 95 points over the minimum. Whether Forever does is
-- not known: Hillsbrad Foothills landed 92% at 126-129, 94% at 130-139 and
-- all from 140, too few casts to tell. So FishingForever predicts nothing
-- about fish getting away; the stats (Stats.lua) count them. This file hears
-- the refusals, keeps the highest skill refused in each zone, and says when
-- the water is too low for a skill.

local Water = {}
ns.Water = Water

ns.AddDefaults({
    -- A zone's map ID -> { name, refused }: the highest skill the game
    -- refused a cast at there. (Saves from before kept casts here too; the
    -- stats' log has them now.)
    waters = {},
})

-- Refusals players have noted and sent in, baked into a release: the same
-- shape as FishingForeverDB.waters, and counted with the player's own.
Water.BAKED = {}

--- The zone the player is in: its map ID and name, or nil.
function Water.Here()
    return ns.Guarded(function()
        local id = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if type(id) ~= "number" then
            return nil
        end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(id)
        local name = info and info.name or (GetZoneText and GetZoneText()) or nil
        return { id = id, name = name }
    end, nil)
end

--- Note that the game refused a fishing cast in `zone` at `skill`: the
-- zone's minimum is above it.
function Water.RecordRefused(zone, skill)
    if not (zone and zone.id and type(skill) == "number") then
        return
    end
    local water = ns.db.waters[zone.id] or {}
    water.name = water.name or zone.name
    water.refused = math.max(tonumber(water.refused) or 0, skill)
    ns.db.waters[zone.id] = water
end

--- What FishingForever knows of a zone's water: { refused, name }, `refused`
-- the highest skill the game refused a cast at there (baked or the
-- player's own), or nil.
function Water.Read(id)
    local highest
    for _, source in ipairs({ Water.BAKED, ns.db.waters }) do
        local refused = type(source[id]) == "table" and tonumber(source[id].refused)
        if refused and refused > (highest or -math.huge) then
            highest = refused
        end
    end
    local notes = ns.db.waters[id] or Water.BAKED[id]
    return { refused = highest, name = notes and notes.name }
end

--- Whether the game has refused a cast here at `skill` or more.
function Water.TooLow(water, skill)
    return water.refused ~= nil and type(skill) == "number" and skill <= water.refused
end

-- Casts in a row whose fish all got away before the water counts as too low
-- to land one: Stranglethorn Vale let a cast go at 155 and four of four got
-- away, where Hillsbrad lost one in sixteen.
local ALL_AWAY = 5

--- Whether the water in zone `id` is too low for `skill` (with the lure's
-- bonus). "refused" and the skill refused, where the game refused a cast at
-- `skill` or more; "away" and the casts, where every fish of five casts or
-- more at `skill` or more got away; nil otherwise.
function Water.TooLowFor(id, skill)
    if type(skill) ~= "number" then
        return nil
    end
    local water = Water.Read(id)
    if Water.TooLow(water, skill) then
        return "refused", water.refused
    end
    if ns.Stats then
        local casts, caught = ns.Stats.LandedFrom(id, skill)
        if casts >= ALL_AWAY and caught == 0 then
            return "away", casts
        end
    end
    return nil
end

-- A refusal is two things from the game, in either order: a fishing cast
-- that failed, and "Skill not high enough". The words alone are said of
-- other skills too, so only the pair, close together, counts.
local ANSWER_WITHIN = 1 -- seconds

local fishingAt, refusalAt

local function now()
    return GetTime and GetTime() or 0
end

local function recent(at)
    return at ~= nil and now() - at <= ANSWER_WITHIN
end

local function refused()
    fishingAt, refusalAt = nil, nil
    -- A zone's minimum goes by the skill with a lure's bonus.
    Water.RecordRefused(Water.Here(), ns.Skill.Effective())
    if ns.Stats then
        ns.Stats.Note(ns.Stats.Context(ns.Skill.Info()), "refused")
    end
    if ns.SkillBar and ns.SkillBar.Refresh then
        ns.SkillBar.Refresh()
    end
end

local function isFishing(spellID)
    return ns.Fishing and ns.Fishing.IsFishingSpell(spellID)
end

local events = CreateFrame("Frame")
events:RegisterEvent("UNIT_SPELLCAST_SENT")
events:RegisterEvent("UNIT_SPELLCAST_FAILED")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:SetScript("OnEvent", function(_, event, ...)
    if not ns.db then
        return
    end
    if event == "UNIT_SPELLCAST_SENT" then
        local unit, _, _, spellID = ...
        if unit == "player" and isFishing(spellID) then
            -- A new cast: any earlier words were not its answer.
            fishingAt, refusalAt = now(), nil
        end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        local unit, _, spellID = ...
        if unit == "player" and isFishing(spellID) then
            fishingAt = now()
            if recent(refusalAt) then
                refused()
            end
        end
    elseif event == "UI_ERROR_MESSAGE" then
        local _, message = ...
        if ns.Guarded(function() return message == SPELL_FAILED_LOW_CASTLEVEL end, false) then
            refusalAt = now()
            if recent(fishingAt) then
                refused()
            end
        end
    end
end)
