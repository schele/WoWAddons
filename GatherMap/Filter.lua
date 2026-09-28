local addonName, ns = ...

-- Whether a spawn is shown on the world map or the minimap. The one place
-- every filter is applied, so the two maps can never disagree about what a
-- setting means.

local Filter = {}
ns.Filter = Filter

local function filters(pinSize)
    return {
        kinds = { herb = true, ore = true, pool = true, chest = true },
        hidden = {},
        hideUngatherable = true,
        hideGrey = false,
        onlyConfirmed = false,
        showMissing = false,
        pinSize = pinSize,
    }
end

ns.AddDefaults({
    worldmap = filters(12),
    minimap = filters(10),
})

--- Whether the game has shown this spawn is real: the player gathered it,
-- or a recording baked into the release did. vMaNGOS alone is a guess.
function Filter.Confirmed(spawn)
    return ns.db.gathered[spawn.key] ~= nil or ns.confirmed[spawn.key] == true
end

--- Whether `spawn` is shown on `where`: "worldmap" or "minimap".
function Filter.Shows(where, spawn)
    local settings = ns.settings
    if not settings.enabled then
        return false
    end

    local node = ns.Nodes[spawn.entry]
    if not node then
        return false
    end

    local chosen = settings[where]
    if not chosen.kinds[node.kind] or chosen.hidden[node.name] then
        return false
    end
    if chosen.onlyConfirmed and not Filter.Confirmed(spawn) then
        return false
    end
    if ns.db.missing[spawn.key] and not chosen.showMissing then
        return false
    end

    if node.skill then
        local color = ns.Skills.Color(node.skill, ns.Skills.Get(node.kind))
        if chosen.hideUngatherable and color == "red" then
            return false
        end
        if chosen.hideGrey and color == "grey" then
            return false
        end
    end

    return true
end
