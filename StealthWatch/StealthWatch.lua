local addonName, ns = ...

ns.PREFIX = "|cffb9a8f0StealthWatch|r"

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

local function ensureDatabase()
    if type(StealthWatchDB) ~= "table" then
        StealthWatchDB = {}
    end
    if type(StealthWatchDB.settings) ~= "table" then
        StealthWatchDB.settings = {}
    end
    applyDefaults(StealthWatchDB.settings, defaults)
    ns.db = StealthWatchDB
    ns.settings = StealthWatchDB.settings
end

-- Whatever shows a setting registers here, and redraws when one changes.
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

function ns.RegisterCommand(name, help, handler)
    commands[name] = { help = help, handler = handler }
end

local function showHelp()
    ns.Print("Commands:")
    ns.Print("/sw - Open the settings page")
    local names = {}
    for name in pairs(commands) do
        table.insert(names, name)
    end
    table.sort(names)
    for _, name in ipairs(names) do
        ns.Print(string.format("/sw %s - %s", name, commands[name].help))
    end
end

-- What a bare /sw does. Settings.lua points it at the page; until then, the help.
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

SLASH_STEALTHWATCH1 = "/sw"
SLASH_STEALTHWATCH2 = "/stealthwatch"
SlashCmdList.STEALTHWATCH = runCommand

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
    end
end)
