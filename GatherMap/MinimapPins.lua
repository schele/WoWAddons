local addonName, ns = ...

-- Pins on the minimap for what is in its range: chosen five times a second,
-- and moved every frame, from the player's position in world yards. The
-- position keeps coming in combat (probed 2026-09-28), so the pins keep
-- moving through a fight.

local MinimapPins = {}
ns.MinimapPins = MinimapPins

MinimapPins.INTERVAL = 0.2
MinimapPins.MAX = 100

local pool

--- Where the player is, in world yards, as smoothly as the game says it.
-- UnitPosition steps: running, it changed on only 29-44 frames in 120, while
-- the map position changed on all 120 (probed 2026-09-29). So the map
-- position, put back into yards with the map's corners, and UnitPosition
-- only where the game gives no map position.
local function playerPosition()
    local fromMap = ns.Guarded(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        local rect = ns.Geometry.MapRect(mapID)
        local at = rect and C_Map.GetPlayerMapPosition(mapID, "player")
        if not at or type(at.x) ~= "number" then
            return nil
        end
        local x, y = ns.Geometry.ToWorld(rect, at.x, at.y)
        return { x = x, y = y, continent = rect.continent }
    end)
    if fromMap then
        return fromMap.x, fromMap.y, fromMap.continent
    end
    local x, y, _, continent = UnitPosition("player")
    return x, y, continent
end

--- Where the minimap is looking from, as the pins need it: the player's
-- place and the map's scale. Nil when the client will not say where the
-- player is.
local function view()
    local x, y, continent = playerPosition()
    if type(x) ~= "number" then
        return nil
    end
    local size = ns.settings.minimap.pinSize
    local diameter = ns.Geometry.MinimapDiameter(Minimap:GetZoom(), IsIndoors and IsIndoors())
    local scale = Minimap:GetWidth() / diameter
    local rotate = GetCVar("rotateMinimap") == "1"
    return {
        x = x, y = y, continent = continent, size = size, scale = scale,
        -- Short of the edge by half a pin, so no pin hangs off the round map.
        radius = diameter / 2 - size / 2 / scale,
        rotate = rotate,
        facing = rotate and GetPlayerFacing and GetPlayerFacing(),
    }
end

--- Put the pins chosen last where their places are now. Every frame: the
-- minimap scrolls smoothly as the player moves, so pins placed only when
-- chosen would lag behind it and jump. A pin that has slipped past the rim
-- since is hidden until the next choice.
function MinimapPins.Place()
    if not pool then
        return
    end
    ns.Guarded(function()
        local at = view()
        if not at then
            return
        end
        local limit = at.radius * at.radius
        for index = 1, pool.used do
            local pin = pool.pins[index]
            local spawn = pin.spawn
            if spawn then
                local dx, dy = spawn.x - at.x, spawn.y - at.y
                if dx * dx + dy * dy <= limit then
                    local right, up = ns.Geometry.MinimapOffset(at.x, at.y, spawn.x, spawn.y, at.facing, at.rotate)
                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", Minimap, "CENTER", right * at.scale, up * at.scale)
                    pin:Show()
                else
                    pin:Hide()
                end
            end
        end
    end)
end

--- Choose the pins: the places in the minimap's range that the filters
-- show, one per spot. Five times a second, and on any change.
function MinimapPins.Refresh()
    if not pool then
        return
    end
    pool:Begin()

    ns.Guarded(function()
        if not ns.settings.enabled then
            return
        end
        local at = view()
        if not at then
            return
        end

        -- One pin per spot: its first spawn stands for it.
        ns.Spawns.Near(at.continent, at.x, at.y, at.radius, function(spawn)
            if pool.used >= MinimapPins.MAX or spawn.stack[1] ~= spawn then
                return
            end
            local shown = ns.Filter.Shown("minimap", spawn.stack)
            if #shown > 0 then
                ns.Pins.Set(pool:Acquire(), shown, at.size)
            end
        end)
    end)

    pool:Finish()
    MinimapPins.Place()
end

function MinimapPins.Shown()
    return pool and pool:Shown() or {}
end

ns.OnLogin(function()
    if not Minimap then
        return
    end
    pool = ns.Pins.Pool(Minimap)

    local elapsed = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= MinimapPins.INTERVAL - 1e-9 then
            elapsed = 0
            MinimapPins.Refresh()
        else
            MinimapPins.Place()
        end
    end)
    MinimapPins.ticker = ticker
end)

ns.OnRefresh(MinimapPins.Refresh)
