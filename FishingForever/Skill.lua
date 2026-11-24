local addonName, ns = ...

-- How near the Fishing skill is to its next point.
--
-- The game keeps no progress toward a point. Each catch has a chance to raise
-- the skill, and the chance shrinks as the skill grows. So what FishingForever can
-- tell is how many catches since the last point, against how many a point
-- takes at this skill: the old game's rule until FishingForever has measured
-- enough points itself.
--
-- The count is this character's (FishingForeverCharDB). What each point took is
-- the game's rule, the same for every character, so it is kept for the
-- account (FishingForeverDB.skillUps).

local Skill = {}
ns.Skill = Skill

ns.AddDefaults({
    -- The skill a point was earned from -> { points, catches }: how many
    -- points FishingForever watched from start to end there, and the catches they
    -- took between them.
    skillUps = {},
})

-- Fishing's skill line, in every client language.
local FISHING_SKILL_ID = 356
-- Measured points within one band of skill (225 to 249, say) before what was
-- measured replaces the old game's rule.
local BAND = 25
local MEASURED_POINTS = 5

-- Points players have measured and sent in, baked into a release: the same
-- shape as FishingForeverDB.skillUps, and counted with the player's own.
Skill.BAKED = {}

-- { rank, maxRank, bonus } as last read, or nil without Fishing. `bonus` is
-- what a lure or gear adds: the old game counted it for landing a fish and
-- for a zone's minimum, but not for the chance of a point.
local current
-- This cast: whether its catch has been counted or its fish got away,
-- whether a point came before its loot did (finished once the catch is
-- counted), where and at what skill it was cast (`context`, for the stats),
-- and the stats' entry for its catch (`entry`, to mark a point on).
local cast = { open = false, caught = false, escaped = false, pointFrom = nil }
local ready = false

local function charDB()
    if type(FishingForeverCharDB) ~= "table" then
        FishingForeverCharDB = {}
    end
    local db = FishingForeverCharDB
    if type(db.catches) ~= "number" then
        db.catches = 0
    end
    return db
end

--- The skill as kept: rank, cap, and what is added to it.
local function skill(rank, maxRank, temp, modifier)
    return { rank = rank, maxRank = maxRank, bonus = (tonumber(temp) or 0) + (tonumber(modifier) or 0) }
end

--- Fishing in the skill list, by the spell's own name, which is the skill's
-- in every client language. `count` and `line` are the client's calls; a
-- line is { name, isHeader, isExpanded, rank, maxRank, temp, modifier }.
local function fromSkillList(count, line)
    local name = ns.Fishing and ns.Fishing.SpellName() or "Fishing"
    local collapsed = false
    for index = 1, count() do
        local lineName, isHeader, isExpanded, rank, maxRank, temp, modifier = line(index)
        if isHeader then
            if not isExpanded then
                collapsed = true
            end
        elseif lineName == name then
            return skill(rank, maxRank, temp, modifier), true
        end
    end
    -- Under a collapsed header Fishing is not listed: that says nothing.
    return nil, not collapsed
end

-- Classic's list hands each line over as values.
local function classicLine(index)
    local name, isHeader, isExpanded, rank, temp, modifier, maxRank = GetSkillLineInfo(index)
    return name, isHeader, isExpanded, rank, maxRank, temp, modifier
end

-- C_SkillInfo's hands it over as a table.
local function tableLine(index)
    local info = C_SkillInfo.GetSkillLineInfo(index)
    if not info then
        return nil
    end
    return info.name, info.isHeader, not info.isCollapsed, info.rank, info.maxRank,
        info.tempPoints, info.modifier
end

--- Read the skill again. Returns false when the client could not say, and
-- the last reading stands.
local function read()
    local ok, skill, known = pcall(function()
        local skills = C_SkillInfo
        if skills and skills.GetSkillLineInfoByID then
            local info = skills.GetSkillLineInfoByID(FISHING_SKILL_ID)
            if info and type(info.rank) == "number" and type(info.maxRank) == "number" then
                return skill(info.rank, info.maxRank, info.tempPoints, info.modifier), true
            end
            if skills.GetNumSkillLines and skills.GetSkillLineInfo then
                return fromSkillList(skills.GetNumSkillLines, tableLine)
            end
            return nil, true
        end
        if GetNumSkillLines and GetSkillLineInfo then
            return fromSkillList(GetNumSkillLines, classicLine)
        end
        return nil, false
    end)
    if not (ok and known) then
        return false
    end
    current = skill
    return true
end

--- The Fishing skill and its cap, or nil for a character without it.
function Skill.Rank()
    if current then
        return current.rank, current.maxRank
    end
    return nil
end

--- The skill with what a lure or gear adds: what landing a fish and a zone's
-- minimum go by. Nil without Fishing.
function Skill.Effective()
    if current then
        return current.rank + (current.bonus or 0)
    end
    return nil
end

--- What a lure or gear adds to the skill now.
function Skill.Bonus()
    return current and current.bonus or 0
end

--- The skill as last read: { rank, maxRank, bonus }, or nil.
function Skill.Info()
    return current
end

--- Catches since the last point.
function Skill.Catches()
    return ready and charDB().catches or 0
end

--- Whether the skill is at its cap, where no catch can raise it.
function Skill.Capped()
    return current ~= nil and current.rank >= current.maxRank
end

--- The old game's rule: every catch raises the skill below 75; from there,
-- a catch raises it 2500 / (skill - 50) times in a hundred. Returns the
-- catches a point takes on average.
function Skill.Guess(rank)
    if rank < 75 then
        return 1
    end
    return math.max(1, (rank - 50) / 25)
end

--- How many catches a point takes at `rank`, on average, where that came
-- from ("measured" or "guess"), and how many points were measured near it.
function Skill.Expected(rank)
    local low = math.floor(rank / BAND) * BAND
    local points, catches = 0, 0
    for _, source in ipairs({ Skill.BAKED, ns.db and ns.db.skillUps or {} }) do
        for from = low, low + BAND - 1 do
            local entry = source[from]
            if type(entry) == "table" then
                points = points + (tonumber(entry.points) or 0)
                catches = catches + (tonumber(entry.catches) or 0)
            end
        end
    end
    if points >= MEASURED_POINTS then
        return catches / points, "measured", points
    end
    return Skill.Guess(rank), "guess", points
end

local function changed()
    if ns.SkillBar and ns.SkillBar.Refresh then
        ns.SkillBar.Refresh()
    end
end

--- A point (or more) from `from` to `to`. The catches since the last point
-- are noted against `from`, when FishingForever watched them all: from the point
-- before, and one point at a time.
local function finishPoint(from, to)
    local db = charDB()
    local whole = db.clean and to == from + 1 and db.catches > 0
    if whole then
        local entry = ns.db.skillUps[from] or { points = 0, catches = 0 }
        entry.points = entry.points + 1
        entry.catches = entry.catches + db.catches
        ns.db.skillUps[from] = entry
    end
    db.catches = 0
    db.clean = to == from + 1
    db.rank = to
end

local function onSkillChanged()
    local before = current and current.rank
    if not read() then
        return
    end
    local after = current and current.rank
    if not (before and after) or after == before then
        changed() -- a trainer may have raised the cap
        return
    end
    if after < before then
        local db = charDB()
        db.catches, db.clean, db.rank = 0, false, after
    elseif cast.open and not cast.caught then
        -- The point came before its catch's loot: finished once it is counted.
        cast.pointFrom = cast.pointFrom or before
    else
        finishPoint(before, after)
        ns.Stats.Point(cast.entry, after)
    end
    changed()
end

local function finishPending()
    if cast.pointFrom and current then
        finishPoint(cast.pointFrom, current.rank)
        ns.Stats.Point(cast.entry, current.rank)
    end
    cast.pointFrom = nil
end

local function onCatch()
    if cast.caught or cast.escaped then
        return
    end
    cast.caught = true
    cast.entry = ns.Stats.Note(cast.context, "caught", ns.Stats.ReadLoot())
    if not Skill.Capped() or cast.pointFrom then
        local db = charDB()
        db.catches = db.catches + 1
    end
    finishPending()
    changed()
end

-- "Your fish got away!": no catch, and no point, but the stats count it.
local function onEscape()
    if not cast.open or cast.caught or cast.escaped then
        return
    end
    cast.escaped = true
    ns.Stats.Note(cast.context, "away")
    changed()
end

local function onCastStart()
    finishPending()
    cast.open, cast.caught, cast.escaped, cast.entry = true, false, false, nil
    -- Where and at what skill, as the cast goes out: the fish may bite in
    -- the next zone over, or after a point.
    cast.context = ns.Stats.Context(current)
end

local function isEscape(message)
    return ns.Guarded(function() return message == ERR_FISH_ESCAPED end, false)
end

local events = CreateFrame("Frame")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
-- The game says a fish got away in red; some clients say it in yellow.
events:RegisterEvent("UI_ERROR_MESSAGE")
events:RegisterEvent("UI_INFO_MESSAGE")
events:SetScript("OnEvent", function(_, event, ...)
    if not ready then
        return
    end
    if event == "SKILL_LINES_CHANGED" then
        onSkillChanged()
    elseif event == "LOOT_OPENED" then
        if ns.Guarded(function() return IsFishingLoot and IsFishingLoot() end, false) then
            onCatch()
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit, _, spellID = ...
        if unit == "player" and ns.Fishing.IsFishingSpell(spellID) then
            onCastStart()
        end
    elseif event == "UI_ERROR_MESSAGE" or event == "UI_INFO_MESSAGE" then
        local _, message = ...
        if isEscape(message) then
            onEscape()
        end
    end
end)

ns.OnLogin(function()
    read()
    local db = charDB()
    local rank = current and current.rank
    -- The skill moved while FishingForever was not watching: the count is not
    -- this point's.
    if db.rank ~= rank then
        db.catches, db.clean, db.rank = 0, false, rank
    end
    ready = true
end)
