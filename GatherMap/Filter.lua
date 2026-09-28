local addonName, ns = ...

-- Whether a place is shown on the world map or the minimap. The one place
-- every filter is applied, so the two maps can never disagree about what a
-- setting means.

local Filter = {}
ns.Filter = Filter

local function filters(pinSize)
    return {
        kinds = { herb = true, ore = true },
        hidden = {},
        hideUngatherable = true,
        hideGrey = false,
        pinSize = pinSize,
    }
end

ns.AddDefaults({
    worldmap = filters(12),
    minimap = filters(10),
})

--- Whether `spawn` is shown on `where`: "worldmap" or "minimap".
function Filter.Shows(where, spawn)
    local settings = ns.settings
    if not settings.enabled then
        return false
    end

    local node = ns.Spawns.Node(spawn)
    local chosen = settings[where]
    if not node.kind or not chosen.kinds[node.kind] or chosen.hidden[node.name] then
        return false
    end

    -- A skill the client has not shown is no reason to hide anything.
    if node.skill and ns.Skills.Known(node.kind) then
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

--- The members of `stack` (a spot's places) shown on `where`, in its order.
function Filter.Shown(where, stack)
    local shown = {}
    for _, spawn in ipairs(stack) do
        if Filter.Shows(where, spawn) then
            shown[#shown + 1] = spawn
        end
    end
    return shown
end
