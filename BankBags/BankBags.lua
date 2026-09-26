local addonName, ns = ...

ns.PREFIX = "|cff4fd1c5BankBags|r"

-- Defaults are contributed by each file at load time, so every piece of config
-- lives next to the code that reads it.
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

local function ensureDatabase()
    if type(BankBagsDB) ~= "table" then
        BankBagsDB = {}
    end
    applyDefaults(BankBagsDB, defaults)
    ns.db = BankBagsDB
end

-- Slash commands. Each file registers its own.
local commands = {}

function ns.RegisterCommand(name, help, handler)
    commands[name] = { help = help, handler = handler }
end

local function showHelp()
    ns.Print("Commands:")
    ns.Print("/bb - Open or close your bank")
    local names = {}
    for name in pairs(commands) do
        table.insert(names, name)
    end
    table.sort(names)
    for _, name in ipairs(names) do
        ns.Print(string.format("/bb %s - %s", name, commands[name].help))
    end
end

-- What a bare /bb does. Window.lua points it at the window; until then, the
-- command list.
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

SLASH_BANKBAGS1 = "/bankbags"
SLASH_BANKBAGS2 = "/bb"
SlashCmdList.BANKBAGS = runCommand

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
    end
end)
