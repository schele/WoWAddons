local addonName, ns = ...

-- /gmap debug: what each step between the data and the pins on screen has,
-- so a player can say where the chain breaks. Every read is guarded: this is
-- the command used when something is already wrong.

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do
        n = n + 1
    end
    return n
end

local function say(format, ...)
    ns.Print(string.format(format, ...))
end

local function describePin(label, pin)
    if not pin then
        say("%s: none", label)
        return
    end
    ns.Guarded(function()
        local point, relativeTo, relativePoint, x, y = pin:GetPoint(1)
        say("%s: %s shown=%s visible=%s size=%.0f scale=%.2f alpha=%.2f level=%s strata=%s at %s %.0f,%.0f texture=%s",
            label, pin.spawn and ns.Spawns.Node(pin.spawn).name or "?",
            tostring(pin:IsShown()), tostring(pin.IsVisible and pin:IsVisible()), pin:GetWidth() or 0,
            pin:GetScale() or 0, pin:GetAlpha() or 0, tostring(pin:GetFrameLevel()),
            tostring(pin.GetFrameStrata and pin:GetFrameStrata()), tostring(relativePoint), x or 0, y or 0,
            tostring(pin.icon and pin.icon:GetTexture()))
    end)
end

function ns.Debug()
    say("Data: %d node types listed; %d places gathered: %d Eastern Kingdoms, %d Kalimdor.",
        count(ns.Nodes), count(ns.db.gathered), #ns.Spawns.All(0), #ns.Spawns.All(1))
    say("Pins %s. Skills: Herbalism %d, Mining %d.", ns.settings.enabled and "shown" or "HIDDEN",
        ns.Skills.Get("herb"), ns.Skills.Get("ore"))

    ns.Guarded(function()
        local x, y, _, continent = UnitPosition("player")
        say("Position: %s, %s on continent %s.", tostring(x), tostring(y), tostring(continent))
        local near = 0
        if type(x) == "number" then
            ns.Spawns.Near(continent, x, y, 250, function() near = near + 1 end)
        end
        say("Spawns within 250 yards: %d. Minimap pins: %d, zoom %s, indoors %s, %s wide.", near,
            #ns.MinimapPins.Shown(), tostring(Minimap:GetZoom()), tostring(IsIndoors and IsIndoors()),
            tostring(Minimap:GetWidth()))
    end)
    describePin("First minimap pin", ns.MinimapPins.Shown()[1])

    ns.Guarded(function()
        if not WorldMapFrame then
            say("World map: no WorldMapFrame.")
            return
        end
        local mapID = WorldMapFrame:GetMapID()
        local rect = ns.Geometry.MapRect(mapID)
        local canvas = WorldMapFrame:GetCanvas()
        say("World map: open=%s map=%s rect=%s canvas %.0fx%.0f level=%s scale=%s; spawns on it %d; pins %d.",
            tostring(WorldMapFrame:IsShown()), tostring(mapID),
            rect and string.format("continent %d (%.0f,%.0f)-(%.0f,%.0f)", rect.continent, rect.x0, rect.y0, rect.x1, rect.y1) or "none",
            canvas:GetWidth() or 0, canvas:GetHeight() or 0, tostring(canvas:GetFrameLevel()),
            tostring(WorldMapFrame:GetCanvasScale()), #ns.WorldMap.SpawnsOn(mapID), #ns.WorldMap.Shown())
    end)
    describePin("First world map pin", ns.WorldMap.Shown()[1])
end

ns.RegisterCommand("debug", "Show what GatherMap has, step by step, to find why pins do not show", function()
    local ok, err = pcall(ns.Debug)
    if not ok then
        ns.Print("Debug stopped: " .. tostring(err))
    end
end)
