local addonName, ns = ...

-- Pins on the world map. A data provider tells GatherMap when the map
-- changes or zooms; the pins are GatherMap's own frames on the map's canvas,
-- so they pan and zoom with it.

local WorldMap = {}
ns.WorldMap = WorldMap

-- A continent map holds thousands of spawns; past this many pins the map
-- stops being usable, so the rest are left off.
WorldMap.MAX = 2000
-- The pins' frame level where the map will not give one: above Blizzard's
-- default pin level (2000) and the explored-area overlay, which covers the
-- whole canvas.
WorldMap.FALLBACK_LEVEL = 2200

-- Per map: every spot inside it, with its place, as of Spawns.version.
local cache = {}
local pool, provider

--- One place per spot on the map: { spawn = its first, stack, x, y }.
function WorldMap.SpawnsOn(uiMapID)
    local cached = cache[uiMapID]
    if cached and cached.version == ns.Spawns.version then
        return cached.places
    end

    local places = {}
    local rect = ns.Geometry.MapRect(uiMapID)
    if rect then
        for _, spawn in ipairs(ns.Spawns.All(rect.continent)) do
            if spawn.stack[1] == spawn then
                local x, y = ns.Geometry.ToMap(rect, spawn.x, spawn.y)
                if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    table.insert(places, { spawn = spawn, stack = spawn.stack, x = x, y = y })
                end
            end
        end
    end
    if uiMapID then
        cache[uiMapID] = { version = ns.Spawns.version, places = places }
    end
    return places
end

function WorldMap.Refresh()
    if not pool then
        return
    end
    pool:Begin()

    if WorldMapFrame:IsShown() then
        local canvas = WorldMapFrame:GetCanvas()
        local width, height = canvas:GetWidth(), canvas:GetHeight()
        -- Pins stay the same size on screen however far the map is zoomed.
        local scale = 1 / (ns.Guarded(function() return WorldMapFrame:GetCanvasScale() end) or 1)
        local size = ns.settings.worldmap.pinSize

        for _, place in ipairs(WorldMap.SpawnsOn(WorldMapFrame:GetMapID())) do
            if pool.used >= WorldMap.MAX then
                break
            end
            local shown = ns.Filter.Shown("worldmap", place.stack)
            if #shown > 0 then
                local pin = pool:Acquire()
                ns.Pins.Set(pin, shown, size)
                pin:SetScale(scale)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", place.x * width / scale, -place.y * height / scale)
            end
        end
    end

    pool:Finish()
end

--- The pins on the map now.
function WorldMap.Shown()
    return pool and pool:Shown() or {}
end

local function zoomOut()
    ns.Guarded(function()
        if WorldMapFrame.NavigateToParentMap then
            WorldMapFrame:NavigateToParentMap()
        end
    end)
end

local function attach()
    if provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider
        and CreateFromMixins and MapCanvasDataProviderMixin) then
        return
    end

    -- The map's tiles sit at the canvas's level and its own pins far above
    -- it; ours go where the map puts its points of interest.
    local level = ns.Guarded(function()
        return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_AREA_POI")
    end)
    if type(level) ~= "number" then
        level = WorldMap.FALLBACK_LEVEL
    end

    -- A plain right-click on a pin does what it would have done on the map.
    pool = ns.Pins.Pool(WorldMapFrame:GetCanvas(), zoomOut, level)
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RefreshAllData() WorldMap.Refresh() end
    function provider:RemoveAllData() pool:Begin(); pool:Finish() end
    function provider:OnMapChanged() WorldMap.Refresh() end
    function provider:OnCanvasScaleChanged() WorldMap.Refresh() end
    WorldMapFrame:AddDataProvider(provider)
    WorldMapFrame:HookScript("OnShow", WorldMap.Refresh)
end

ns.OnLogin(function()
    ns.Guarded(attach)
end)

-- The world map can load after GatherMap, on demand.
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_WorldMap" and ns.settings then
        ns.Guarded(attach)
    end
end)

ns.OnRefresh(WorldMap.Refresh)

ns.RegisterCommand("where", "Show where the game and GatherMap put you on the map", function()
    local said = ns.Guarded(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        local rect = ns.Geometry.MapRect(mapID)
        local x, y = UnitPosition("player")
        local game = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if not rect or type(x) ~= "number" or not game then
            return false
        end
        local mx, my = ns.Geometry.ToMap(rect, x, y)
        ns.Print(string.format("Map %d. Game: %.3f, %.3f. GatherMap: %.3f, %.3f.", mapID, game.x, game.y, mx, my))
        return true
    end)
    if not said then
        ns.Print("The game will not say where you are here.")
    end
end)
