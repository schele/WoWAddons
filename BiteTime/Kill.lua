local addonName, ns = ...

-- What a Bite now would take from the target, and the target's health to
-- weigh it against.
--
-- On WoW Forever a mob's health and its max health are secrets: addon code
-- may hold them and hand them to the screen, but not compare them. So this
-- file never compares the health. It works out the Bite's reach, a plain
-- number, and Gate has the client's status bars do the comparing. Nothing
-- here learns the answer. Classic Era hides nothing, so there it is a plain
-- comparison.

local Kill = {}
ns.Kill = Kill

-- How much of its tooltip damage a Bite is counted at, in percent: armor
-- takes some of it, and the glow should mean the Bite kills.
ns.AddDefaults({ share = 80 })

Kill.UNIT = "target"
Kill.CAT_FORM = 1 -- GetShapeshiftFormID
local ENERGY = 3 -- Enum.PowerType.Energy

local function rawPoints()
    return ns.Guarded(function()
        if GetComboPoints then
            return GetComboPoints("player", Kill.UNIT)
        end
        return nil
    end)
end

local function rawEnergy()
    return ns.Guarded(function() return UnitPower("player", ENERGY) end)
end

--- Combo points on the target, or nil when the client will not say.
function Kill.Points()
    return ns.Number(rawPoints())
end

--- Energy, or nil when the client will not say.
function Kill.Energy()
    return ns.Number(rawEnergy())
end

--- Whether the client hides the player's combo points, or energy, from
-- addons. WoW Forever may hide any power type it has not marked as never
-- secret (SecretWhenUnitPowerRestricted).
function Kill.PointsHidden()
    return ns.IsSecret(rawPoints())
end

function Kill.EnergyHidden()
    return ns.IsSecret(rawEnergy())
end

--- Whether the player is in Cat Form. A client that cannot say is let through.
function Kill.InCatForm()
    if not GetShapeshiftFormID then
        return true
    end
    return ns.Guarded(function() return GetShapeshiftFormID() == Kill.CAT_FORM end, false)
end

--- The target's max health, or nil when the client hides it, as WoW Forever
-- does for every mob. Only for telling a client that shows health as a
-- percentage, where the max is 100.
function Kill.MaxHealth()
    return ns.Guarded(function()
        local max = ns.Number(UnitHealthMax(Kill.UNIT))
        if max and max > 0 then
            return max
        end
        return nil
    end)
end

--- Why no Bite can be weighed now, or nil when one can: "notCat",
-- "noTarget", "player" (enemy players' health is not for addons to weigh),
-- "hiddenPoints" (the client hides the combo points) or "noPoints".
function Kill.Why()
    if not Kill.InCatForm() then
        return "notCat"
    end
    local usable = ns.Guarded(function()
        return UnitExists(Kill.UNIT) and UnitCanAttack("player", Kill.UNIT) and not UnitIsDeadOrGhost(Kill.UNIT)
    end, false)
    if not usable then
        return "noTarget"
    end
    if ns.Guarded(function() return UnitIsPlayer(Kill.UNIT) end, true) then
        return "player"
    end
    if Kill.PointsHidden() then
        return "hiddenPoints"
    end
    local points = Kill.Points()
    if not points or points < 1 then
        return "noPoints"
    end
    return nil
end

--- The most health a Bite of `rank` surely takes now: the least it does
-- with these combo points and this energy, counted at the share setting.
-- Nil when there is none.
function Kill.Reach(rank)
    local damage = ns.Bite.Damage(rank, Kill.Points(), Kill.Energy())
    if not damage then
        return nil
    end
    local share = tonumber(ns.settings and ns.settings.share) or 100
    local reach = math.floor(damage * share / 100)
    return reach >= 1 and reach or nil
end

-- What a client giving health only as a percentage reports as max health.
local PERCENT_ONLY = 100

--- Whether a Bite of `rank` can be weighed against the target now: if so,
-- the most health it surely takes, and the target's health. The health may
-- be a secret, which is only handed on (to Gate), never looked at here.
function Kill.Weigh(rank)
    if not rank or Kill.Why() then
        return nil
    end
    local reach = Kill.Reach(rank)
    if not reach then
        return nil
    end
    local health = ns.Guarded(function() return UnitHealth(Kill.UNIT) end)
    if ns.IsSecret(health) then
        return reach, health
    end
    if type(health) ~= "number" or Kill.MaxHealth() == PERCENT_ONLY then
        return nil
    end
    return reach, health
end
