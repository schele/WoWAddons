local addonName, ns = ...

-- Pins on the minimap for what is in its range, redrawn five times a second
-- from the player's position in world yards. The position keeps coming in
-- combat (probed 2026-09-28), so the pins keep moving through a fight.

local MinimapPins = {}
ns.MinimapPins = MinimapPins

MinimapPins.INTERVAL = 0.2
MinimapPins.MAX = 100

local pool

function MinimapPins.Refresh()
    if not pool then
        return
    end
    pool:Begin()

    ns.Guarded(function()
        if not ns.settings.enabled then
            return
        end
        local x, y, _, continent = UnitPosition("player")
        if type(x) ~= "number" then
            return
        end

        local size = ns.settings.minimap.pinSize
        local diameter = ns.Geometry.MinimapDiameter(Minimap:GetZoom(), IsIndoors and IsIndoors())
        local scale = Minimap:GetWidth() / diameter
        -- Short of the edge by half a pin, so no pin hangs off the round map.
        local radius = diameter / 2 - size / 2 / scale
        local rotate = GetCVar("rotateMinimap") == "1"
        local facing = rotate and GetPlayerFacing and GetPlayerFacing()

        ns.Spawns.Near(continent, x, y, radius, function(spawn)
            if pool.used < MinimapPins.MAX and ns.Filter.Shows("minimap", spawn) then
                local right, up = ns.Geometry.MinimapOffset(x, y, spawn.x, spawn.y, facing, rotate)
                local pin = pool:Acquire()
                ns.Pins.Set(pin, spawn, size)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", Minimap, "CENTER", right * scale, up * scale)
            end
        end)
    end)

    pool:Finish()
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
        end
    end)
    MinimapPins.ticker = ticker
end)

ns.OnRefresh(MinimapPins.Refresh)
