local addonName, ns = ...

ns.PREFIX = "|cff7ccc5cGatherMap|r"

-- Defaults are contributed by each file at load time, so every piece of config
-- lives next to the code that reads it and this file never learns the others.
local defaults = {
    version = 1,
    enabled = true,
}

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

--- Register additional defaults. Called at file load, before ADDON_LOADED.
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

-- The herbs and veins known by name, handed over by Data/Nodes.lua.
ns.Nodes = {}

function ns.AddNodes(nodes)
    for entry, node in pairs(nodes) do
        ns.Nodes[entry] = node
    end
end

local function ensureDatabase()
    if type(GatherMapDB) ~= "table" then
        GatherMapDB = {}
    end
    if type(GatherMapDB.gathered) ~= "table" then
        GatherMapDB.gathered = {}
    end
    -- The first GatherMap's "not here" marks: nothing uses them now.
    GatherMapDB.missing = nil
    ns.db = GatherMapDB

    if type(GatherMapSettings) ~= "table" then
        GatherMapSettings = {}
    end
    applyDefaults(GatherMapSettings, defaults)
    ns.settings = GatherMapSettings
end

-- Whatever draws pins registers here, and redraws when anything they depend
-- on changes: a filter, a skill, a new gather.
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

function ns.SetEnabled(value)
    ns.settings.enabled = value and true or false
    ns.Refresh()
end

-- Slash commands. Each file registers its own, so a feature owns its commands
-- and its help text.
local commands = {}
ns.commands = commands

function ns.RegisterCommand(name, help, handler)
    commands[name] = { help = help, handler = handler }
end

local function showHelp()
    ns.Print("Commands:")
    local names = {}
    for name in pairs(commands) do
        table.insert(names, name)
    end
    table.sort(names)
    for _, name in ipairs(names) do
        ns.Print(string.format("/gmap %s - %s", name, commands[name].help))
    end
end

local function runCommand(msg)
    local input = msg and msg:match("^%s*(.-)%s*$") or ""

    if input == "" and ns.OpenSettings then
        ns.OpenSettings()
        return
    end
    if input == "" or input == "help" then
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

-- Not /gm: that is the game's own help-ticket command.
SLASH_GATHERMAP1 = "/gathermap"
SLASH_GATHERMAP2 = "/gmap"
SlashCmdList.GATHERMAP = runCommand

-- What `/gmap toggle <word>` switches: one map's pins.
local MAPS = {
    map = { where = "worldmap", label = "World map" },
    worldmap = { where = "worldmap", label = "World map" },
    minimap = { where = "minimap", label = "Minimap" },
}

ns.RegisterCommand("toggle", "Show or hide every pin; /gmap toggle map or minimap for one map", function(rest)
    rest = (rest or ""):lower()
    if rest == "" then
        ns.SetEnabled(not ns.settings.enabled)
        ns.Print(ns.settings.enabled and "Pins shown." or "Pins hidden.")
        return
    end
    local map = MAPS[rest]
    if not map then
        ns.Print("/gmap toggle shows or hides every pin; /gmap toggle map or /gmap toggle minimap, one map's.")
        return
    end
    ns.Filter.SetShown(map.where, not ns.settings[map.where].show)
    ns.Print(string.format("%s pins %s.", map.label, ns.settings[map.where].show and "shown" or "hidden"))
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
        ns.Print("Loaded. Type /gmap for settings, or /gmap help for commands.")
    end
end)
