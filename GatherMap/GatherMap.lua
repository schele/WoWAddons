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

-- The catalog and the spawns, handed over by the generated Data files as
-- they load. Spawns.lua turns the flat lists into its index at login.
ns.Nodes = {}
ns.rawSpawns = {}
-- Spawns players gathered in WoW Forever, baked into the release.
ns.confirmed = {}

function ns.AddConfirmed(keys)
    for _, key in ipairs(keys) do
        ns.confirmed[key] = true
    end
end

function ns.AddNodes(nodes)
    for entry, node in pairs(nodes) do
        ns.Nodes[entry] = node
    end
end

function ns.AddSpawns(continent, flat)
    local list = ns.rawSpawns[continent]
    if not list then
        list = {}
        ns.rawSpawns[continent] = list
    end
    for index = 1, #flat do
        list[#list + 1] = flat[index]
    end
end

local function ensureDatabase()
    if type(GatherMapDB) ~= "table" then
        GatherMapDB = {}
    end
    if type(GatherMapDB.gathered) ~= "table" then
        GatherMapDB.gathered = {}
    end
    if type(GatherMapDB.missing) ~= "table" then
        GatherMapDB.missing = {}
    end
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
    for _, fn in ipairs(refreshers) do
        fn()
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

ns.RegisterCommand("toggle", "Show or hide every pin", function()
    ns.SetEnabled(not ns.settings.enabled)
    ns.Print(ns.settings.enabled and "Pins shown." or "Pins hidden.")
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
        for _, handler in ipairs(loginHandlers) do
            handler()
        end
        ns.Print("Loaded. Type /gmap for settings, or /gmap help for commands.")
    end
end)
