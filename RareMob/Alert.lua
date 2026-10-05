local addonName, ns = ...

-- A sound when a living rare comes near: the raid warning, once per rare in
-- five minutes, and never in a city or an inn, where the rares are the
-- town's own and the player is not hunting.

local Alert = {}
ns.Alert = Alert

ns.AddDefaults({ alert = true })

Alert.QUIET = 300  -- seconds before the same rare sounds again
Alert.FALLBACK = 8959 -- the raid warning's sound id, for a client without SOUNDKIT

local lastPlayed = {} -- id -> GetTime() it last sounded

function Alert.Play()
    ns.Guarded(function()
        local kit = SOUNDKIT and SOUNDKIT.RAID_WARNING or Alert.FALLBACK
        PlaySound(kit, "Master")
    end)
end

local function resting()
    return ns.Guarded(function() return IsResting() and true or false end, false)
end

ns.OnSpotted(function(id)
    if not ns.settings.alert or resting() then
        return
    end
    local now = GetTime()
    if lastPlayed[id] and now - lastPlayed[id] < Alert.QUIET then
        return
    end
    lastPlayed[id] = now
    Alert.Play()
end)
