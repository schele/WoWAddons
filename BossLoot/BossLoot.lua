local addonName, ns = ...

ns.PREFIX = "|cff66ccffBossLoot|r"

-- Defaults are contributed by each file at load time, so every piece of config
-- lives next to the code that reads it and this file never learns the others.
local defaults = {
    version = 1,
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

function ns.AddDefaults(extra)
    applyDefaults(defaults, extra)
end

function ns.Print(message)
    print(string.format("%s %s", ns.PREFIX, message))
end

--- Call `fn` and return what it returns, or `whenUnknown` if it raises. This
-- client hands addon code some values as secrets that raise when compared;
-- the comparison has to happen inside `fn`.
function ns.Guarded(fn, whenUnknown)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return whenUnknown
end

-- The generated data files each hand their instance here, in .toc order.
ns.instances = {}
ns.instanceByKey = {}

function ns.AddInstance(instance)
    table.insert(ns.instances, instance)
    ns.instanceByKey[instance.key] = instance
end

local function ensureDatabase()
    if type(BossLootDB) ~= "table" then
        BossLootDB = {}
    end
    applyDefaults(BossLootDB, defaults)
    ns.db = BossLootDB
end

-- Slash commands. Each file registers its own.
local commands = {}
ns.commands = commands

function ns.RegisterCommand(name, help, handler)
    commands[name] = { help = help, handler = handler }
end

local function showHelp()
    ns.Print("Commands:")
    ns.Print("/bl - Open or close the loot window")

    local names = {}
    for name in pairs(commands) do
        table.insert(names, name)
    end
    table.sort(names)

    for _, name in ipairs(names) do
        ns.Print(string.format("/bl %s - %s", name, commands[name].help))
    end
end

-- What a bare /bl does. Window.lua points it at the window; until then, and
-- if that file ever fails to load, it falls back to the command list.
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

SLASH_BOSSLOOT1 = "/bossloot"
SLASH_BOSSLOOT2 = "/bl"
SlashCmdList.BOSSLOOT = runCommand

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

        ns.Print("Loaded. Type /bl to browse loot, /bl help for commands.")
    end
end)
