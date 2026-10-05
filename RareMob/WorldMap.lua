local addonName, ns = ...

-- Pins on the world map, as GatherMap draws them. A data provider tells
-- RareMob when the map changes or zooms; the pins are RareMob's own frames
-- on the map's canvas, above the map art, so they pan and zoom with it, and
-- scaled against the zoom so they stay one size on screen.

local WorldMap = {}
ns.WorldMap = WorldMap

ns.AddDefaults({ worldPins = true })

-- The pins' frame level where the map will not give one: above Blizzard's
-- default pin level (2000) and the explored-area overlay.
WorldMap.FALLBACK_LEVEL = 2200

-- Per map: every pin place inside it, with its place on it, as of
-- Rares.version.
local cache = {}
local pool, provider

--- The pin places on map `uiMapID`: { place, x, y }, x and y 0..1 across it.
function WorldMap.PlacesOn(uiMapID)
    local cached = uiMapID and cache[uiMapID]
    if cached and cached.version == ns.Rares.version then
        return cached.places
    end

    local places = {}
    local rect = ns.Geometry.MapRect(uiMapID)
    if rect then
        for _, place in ipairs(ns.Rares.Places(rect.continent)) do
            local x, y = ns.Geometry.ToMap(rect, place.x, place.y)
            if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                places[#places + 1] = { place = place, x = x, y = y }
            end
        end
    end
    if uiMapID then
        cache[uiMapID] = { version = ns.Rares.version, places = places }
    end
    return places
end

function WorldMap.Refresh()
    if not pool then
        return
    end
    pool:Begin()

    if ns.settings.worldPins and WorldMapFrame:IsShown() then
        local canvas = WorldMapFrame:GetCanvas()
        local width, height = canvas:GetWidth(), canvas:GetHeight()
        -- Pins stay the same size on screen however far the map is zoomed.
        local scale = 1 / (ns.Guarded(function() return WorldMapFrame:GetCanvasScale() end) or 1)
        local size = ns.settings.pinSize

        for _, spot in ipairs(WorldMap.PlacesOn(WorldMapFrame:GetMapID())) do
            if ns.Rares.Shown(ns.Rares.Info(spot.place.id)) then
                local pin = pool:Acquire()
                ns.Pins.Set(pin, spot.place, size)
                pin:SetScale(scale)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", spot.x * width / scale, -spot.y * height / scale)
            end
        end
    end

    pool:Finish()
end

--- The pins on the map now.
function WorldMap.Shown()
    return pool and pool:Shown() or {}
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

    pool = ns.Pins.Pool(WorldMapFrame:GetCanvas(), level)
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    -- The map calls these from its own code: an error of ours must not land
    -- there.
    local function refresh() ns.Guarded(WorldMap.Refresh) end
    function provider:RefreshAllData() refresh() end
    function provider:RemoveAllData() pool:Begin(); pool:Finish() end
    function provider:OnMapChanged() refresh() end
    function provider:OnCanvasScaleChanged() refresh() end
    WorldMapFrame:AddDataProvider(provider)
    WorldMapFrame:HookScript("OnShow", refresh)
    -- The rare picked in the list glows until the map is closed.
    WorldMapFrame:HookScript("OnHide", function()
        ns.Pins.highlight = nil
    end)
end

--- Open the world map on zone `uiMapID`, with rare `id`'s pins glowing.
function WorldMap.ShowRare(id, uiMapID)
    ns.Guarded(attach)
    if not provider then
        return
    end
    ns.Pins.highlight = id
    ns.Guarded(function()
        if not WorldMapFrame:IsShown() then
            if ShowUIPanel then
                ShowUIPanel(WorldMapFrame)
            else
                WorldMapFrame:Show()
            end
        end
        WorldMapFrame:SetMapID(uiMapID)
    end)
    ns.Refresh()
end

ns.OnLogin(function()
    ns.Guarded(attach)
end)

-- The world map can load after RareMob, on demand.
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_WorldMap" and ns.settings then
        ns.Guarded(attach)
    end
end)

ns.OnRefresh(WorldMap.Refresh)
