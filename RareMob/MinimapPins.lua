local addonName, ns = ...

-- Pins on the minimap for the rares in its range, placed as GatherMap places
-- its own: chosen five times a second and moved every frame, from the
-- player's position in world yards, on whole screen pixels.

local MinimapPins = {}
ns.MinimapPins = MinimapPins

ns.AddDefaults({ minimapPins = true })

MinimapPins.INTERVAL = 0.2

local pool

--- Where the player is, in world yards, as smoothly as the game says it.
-- UnitPosition steps; the map position moves every frame (GatherMap probed
-- this 2026-09-29). So the map position, put back into yards with the map's
-- corners, and UnitPosition only where the game gives no map position.
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
    return ns.Guarded(function()
        local x, y, _, continent = UnitPosition("player")
        if type(x) ~= "number" then
            return nil
        end
        return x, y, continent
    end)
end

--- Where the minimap is looking from: the player's place and the map's
-- scale. Nil when the client will not say where the player is.
local function view()
    local x, y, continent = playerPosition()
    if type(x) ~= "number" then
        return nil
    end
    local size = ns.settings.pinSize
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

--- `value`, in `frame`'s UI units, moved to the nearest whole screen pixel,
-- so a pin's edges move together rather than flicker. Unchanged where the
-- client will not give its screen size.
local function onPixel(frame, value)
    local perUnit = ns.Guarded(function()
        local _, height = GetPhysicalScreenSize()
        return frame:GetEffectiveScale() * height / 768
    end)
    if type(perUnit) ~= "number" or perUnit <= 0 then
        return value
    end
    return math.floor(value * perUnit + 0.5) / perUnit
end

--- Put the pins chosen last where their places are now. Every frame: the
-- minimap scrolls smoothly as the player moves. A pin that has slipped
-- past the rim since is hidden until the next choice.
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
            local place = pin.place
            if place then
                local dx, dy = place.x - at.x, place.y - at.y
                if dx * dx + dy * dy <= limit then
                    local right, up = ns.Geometry.MinimapOffset(at.x, at.y, place.x, place.y, at.facing, at.rotate)
                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", Minimap, "CENTER", onPixel(pin, right * at.scale), onPixel(pin, up * at.scale))
                    pin:Show()
                else
                    pin:Hide()
                end
            end
        end
    end)
end

--- Choose the pins: the places in the minimap's range the settings show.
function MinimapPins.Refresh()
    if not pool then
        return
    end
    pool:Begin()

    ns.Guarded(function()
        if not ns.settings.minimapPins then
            return
        end
        local at = view()
        if not at then
            return
        end
        local limit = at.radius * at.radius
        for _, place in ipairs(ns.Rares.Places(at.continent)) do
            local dx, dy = place.x - at.x, place.y - at.y
            if dx * dx + dy * dy <= limit and ns.Rares.Shown(ns.Rares.Info(place.id)) then
                ns.Pins.Set(pool:Acquire(), place, at.size)
            end
        end
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
