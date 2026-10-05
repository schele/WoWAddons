local addonName, ns = ...

ns.PREFIX = "|cffd8c8a8RareMob|r"

-- Settings defaults are contributed by each file at load time, so every
-- piece of config lives next to the code that reads it.
local defaults = {}

--- Merge a defaults table into a saved table without clobbering stored values.
local function applyDefaults(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            applyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

--- Register additional settings defaults. Called at file load, before ADDON_LOADED.
function ns.AddDefaults(extra)
    applyDefaults(defaults, extra)
end

function ns.Print(message)
    print(string.format("%s %s", ns.PREFIX, message))
end

--- Call `fn` and return what it returns, or `whenUnknown` if it raises.
-- This client hands addon code some values as secrets: the call succeeds,
-- but comparing or testing the result raises. The branch has to happen
-- inside `fn`, not on a value fetched through here and tested outside.
function ns.Guarded(fn, whenUnknown)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return whenUnknown
end

-- The rares, from the generated Data\Rares.lua: id -> { name, minLevel,
-- maxLevel, elite }.
ns.rares = {}

function ns.AddRares(rares)
    for id, rare in pairs(rares) do
        ns.rares[id] = { name = rare[1], minLevel = rare[2], maxLevel = rare[3], elite = rare[4] and true or false }
    end
end

-- Where they spawn, from Data\Spawns*.lua: continent -> { { id, x, y } },
-- in world yards.
ns.spawns = {}

function ns.AddSpawns(continent, flat)
    local list = ns.spawns[continent] or {}
    ns.spawns[continent] = list
    for index = 1, #flat, 3 do
        list[#list + 1] = { id = flat[index], x = flat[index + 1], y = flat[index + 2] }
    end
end

-- Sightings baked into a release, from Data\Recorded.lua: recorder id ->
-- its sightings. See Rares.lua.
ns.baked = {}

function ns.AddRecordings(recorder, sightings)
    ns.baked[recorder] = sightings
end

--- Eight hex digits, to tell this player's sightings from others' once
-- baked into a release.
local function newRecorderId()
    local digits = {}
    for index = 1, 8 do
        digits[index] = string.format("%x", math.random(0, 15))
    end
    return table.concat(digits)
end

local function ensureDatabase()
    if type(RareMobDB) ~= "table" then
        RareMobDB = {}
    end
    if type(RareMobDB.sightings) ~= "table" then
        RareMobDB.sightings = {}
    end
    if type(RareMobDB.recorder) ~= "string" then
        RareMobDB.recorder = newRecorderId()
    end
    if type(RareMobDB.settings) ~= "table" then
        RareMobDB.settings = {}
    end
    applyDefaults(RareMobDB.settings, defaults)
    ns.db = RareMobDB
    ns.settings = RareMobDB.settings
end

-- Whatever draws registers here, and redraws when anything it depends on
-- changes: a setting, a sighting, a rare spotted or gone.
local refreshers = {}

function ns.OnRefresh(fn)
    table.insert(refreshers, fn)
end

function ns.Refresh()
    -- One refresher that raises must not stop the rest.
    for _, fn in ipairs(refreshers) do
        ns.Guarded(fn)
    end
end

-- Slash commands. Each file registers its own.
local commands = {}
ns.commands = commands

function ns.RegisterCommand(name, help, handler)
    commands[name] = { help = help, handler = handler }
end

local function showHelp()
    ns.Print("Commands:")
    ns.Print("/rm - Open or close the list of this zone's rares")
    local names = {}
    for name in pairs(commands) do
        table.insert(names, name)
    end
    table.sort(names)
    for _, name in ipairs(names) do
        ns.Print(string.format("/rm %s - %s", name, commands[name].help))
    end
end

-- What a bare /rm does. List.lua points it at the list; until then, the help.
ns.DefaultCommand = nil

local function runCommand(msg)
    local input = msg and msg:match("^%s*(.-)%s*$") or ""

    if input == "" then
        if ns.DefaultCommand then
            ns.DefaultCommand()
        else
            showHelp()
        end
        return
    end
    if input == "help" then
        showHelp()
        return
    end

    local name, rest = input:match("^(%S+)%s*(.-)$")
    name = name and name:lower() or ""

    local command = commands[name]
    if command then
        command.handler(rest)
        return
    end

    ns.Print(string.format("Unknown command: %s", name))
    showHelp()
end

SLASH_RAREMOB1 = "/rm"
SLASH_RAREMOB2 = "/raremob"
SlashCmdList.RAREMOB = runCommand

-- Every call RareMob makes that this client might lack, for /rm probe.
local PROBES = {
    { "UnitClassification", function() return UnitClassification end },
    { "UnitGUID", function() return UnitGUID end },
    { "UnitIsDead", function() return UnitIsDead end },
    { "C_NamePlate.GetNamePlateForUnit", function() return C_NamePlate.GetNamePlateForUnit end },
    { "C_Map.GetBestMapForUnit", function() return C_Map.GetBestMapForUnit end },
    { "C_Map.GetPlayerMapPosition", function() return C_Map.GetPlayerMapPosition end },
    { "C_Map.GetWorldPosFromMapPos", function() return C_Map.GetWorldPosFromMapPos end },
    { "WorldMapFrame.AddDataProvider", function() return WorldMapFrame.AddDataProvider end },
    { "PlaySound", function() return PlaySound end },
}

ns.RegisterCommand("probe", "Say which of the calls RareMob uses this client has", function()
    for _, probe in ipairs(PROBES) do
        local present = ns.Guarded(function() return type(probe[2]()) == "function" end, false)
        ns.Print(string.format("%s: %s", probe[1], present and "yes" or "missing"))
    end

    local where = ns.Guarded(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        local at = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if not at then
            return nil
        end
        local rect = ns.Geometry and ns.Geometry.MapRect(mapID)
        return string.format("You are on map %d at %.3f, %.3f; its corners %s.", mapID, at.x, at.y,
            rect and "are known" or "are not")
    end)
    ns.Print(where or "The client gives no map position here.")

    local target = ns.Guarded(function()
        if not UnitExists("target") then
            return nil
        end
        local id = ns.Spotter and ns.Spotter.ParseGUID(UnitGUID("target"))
        return string.format("Target: %s, creature id %s, %s.", tostring(UnitClassification("target")),
            tostring(id), UnitIsDead("target") and "dead" or "alive")
    end)
    if target then
        ns.Print(target)
    end
end)

-- Work to do once the player is in the world and the database exists.
local loginHandlers = {}

function ns.OnLogin(handler)
    table.insert(loginHandlers, handler)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ensureDatabase()
    elseif event == "PLAYER_LOGIN" then
        ensureDatabase()
        -- One handler that raises must not stop the rest.
        for _, handler in ipairs(loginHandlers) do
            ns.Guarded(handler)
        end
        ns.Print("Loaded. Type /rm for this zone's rares, /rm help for commands.")
    end
end)
