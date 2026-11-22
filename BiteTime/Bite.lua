local addonName, ns = ...

-- What a Ferocious Bite does, read from the game's own tooltip: the damage
-- for each number of combo points, and what each point of energy over its
-- cost adds. Reading only, so it can be tested without a client. Every
-- lookup tries C_Spell first and the old global second: this client moved
-- spell lookups into C_Spell.

local Bite = {}
ns.Bite = Bite

-- Rank 1, how the client's own name for the spell is found; and the
-- English name, should the client not know that id.
Bite.SPELL = 22568
Bite.ENGLISH = "Ferocious Bite"
-- Its energy cost, when the client will not say.
Bite.COST = 35
-- How many combo points a tooltip lists damage for.
Bite.MAX_POINTS = 5

local ENERGY = 3 -- Enum.PowerType.Energy

local function nameOf(id)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(id)
    end
    if GetSpellInfo then
        return (GetSpellInfo(id))
    end
    return nil
end

--- The client's name for Ferocious Bite.
function Bite.Name()
    local name = ns.Guarded(function() return nameOf(Bite.SPELL) end)
    return type(name) == "string" and name ~= "" and name or Bite.ENGLISH
end

--- Whether spell `id` is a rank of Ferocious Bite.
function Bite.Is(id)
    if ns.IsSecret(id) or type(id) ~= "number" then
        return false
    end
    return ns.Guarded(function() return nameOf(id) == Bite.Name() end, false)
end

--- The highest rank the character knows, or nil. Asked by name, the client
-- answers with the rank a /cast without one would cast.
function Bite.TopRank()
    local id = ns.Guarded(function()
        local name = Bite.Name()
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(name)
            return type(info) == "table" and info.spellID or nil
        end
        if GetSpellInfo then
            return (select(7, GetSpellInfo(name)))
        end
        return nil
    end)
    return Bite.Is(id) and id or nil
end

-- A damage figure as a tooltip writes it: "40", "1,040" or "1.040".
local RANGE = "(%d[%d,%.]*)%s*%-%s*(%d[%d,%.]*)"

local function whole(text)
    local digits = text:gsub("[,%.]", "")
    return tonumber(digits)
end

--- The numbers in a Bite's tooltip: `ranges`, the low and high damage for
-- one combo point, two and so on, and `perEnergy`, what each point of
-- energy over the cost adds (0 when the text names nothing). Nil for text
-- with no damage in it.
function Bite.Parse(text)
    if type(text) ~= "string" then
        return nil
    end
    local ranges = {}
    for low, high in text:gmatch(RANGE) do
        table.insert(ranges, { whole(low), whole(high) })
    end
    if #ranges == 0 then
        return nil
    end
    -- The list is last: anything before it ("1-5 combo points") is not it.
    while #ranges > Bite.MAX_POINTS do
        table.remove(ranges, 1)
    end

    local rest = text:gsub(RANGE, "")
    local units, fraction = rest:match("(%d+)[%.,](%d+)")
    local perEnergy = units and tonumber(units .. "." .. fraction) or 0
    return { ranges = ranges, perEnergy = perEnergy }
end

local function description(id)
    if C_Spell and C_Spell.GetSpellDescription then
        return C_Spell.GetSpellDescription(id)
    end
    if GetSpellDescription then
        return GetSpellDescription(id)
    end
    return nil
end

local function cost(id)
    local costs
    if C_Spell and C_Spell.GetSpellPowerCost then
        costs = C_Spell.GetSpellPowerCost(id)
    elseif GetSpellPowerCost then
        costs = GetSpellPowerCost(id)
    end
    for _, entry in ipairs(type(costs) == "table" and costs or {}) do
        if (entry.type == ENERGY or entry.name == "ENERGY") and type(entry.cost) == "number" then
            return entry.cost
        end
    end
    return Bite.COST
end

local function icon(id)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(id)
    end
    if GetSpellTexture then
        return GetSpellTexture(id)
    end
    return nil
end

-- Ranks read so far, by id. Forgotten when the numbers may have moved: a
-- new rank, a level, or the tooltip arriving late.
local ranks = {}

function Bite.Forget()
    ranks = {}
end

--- A rank as { id, ranges, perEnergy, cost, icon }, or nil while the client
-- has no tooltip for it (it may not have loaded yet: asked again later).
function Bite.Read(id)
    if type(id) ~= "number" then
        return nil
    end
    if ranks[id] then
        return ranks[id]
    end
    local rank = ns.Guarded(function()
        local parsed = Bite.Parse(description(id))
        if not parsed then
            return nil
        end
        parsed.id = id
        parsed.cost = cost(id)
        parsed.icon = icon(id)
        return parsed
    end)
    ranks[id] = rank
    return rank
end

--- The least a Bite of `rank` does with `points` combo points and `energy`
-- energy: the low end of its range, plus what the energy over its cost
-- adds. Nil without combo points.
function Bite.Damage(rank, points, energy)
    if not rank or type(points) ~= "number" or points < 1 then
        return nil
    end
    local range = rank.ranges[math.min(points, #rank.ranges)]
    local extra = math.max(0, (tonumber(energy) or 0) - rank.cost)
    return range[1] + extra * rank.perEnergy
end
