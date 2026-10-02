local addonName, ns = ...

ns.PREFIX = "|cff66ccffLFG Board|r"

-- Defaults are contributed by each file at load time, so every piece of
-- saved state lives next to the code that reads it.
local defaults = {
    version = 1,
    roles = {},
}

--- Merge a defaults table into a saved one without clobbering stored values.
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
    if type(LFGBoardDB) ~= "table" then
        LFGBoardDB = {}
    end
    applyDefaults(LFGBoardDB, defaults)
    ns.db = LFGBoardDB
end

--- This character as chat names it: "Name-Realm", the realm without its
-- spaces ("Living Flame" is "LivingFlame"). Its roles are saved under it.
function ns.Me()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if type(realm) ~= "string" or realm == "" then
        realm = (GetRealmName and GetRealmName() or "?"):gsub("%s", "")
    end
    return string.format("%s-%s", UnitName("player") or "?", realm)
end

--- Whether a chat sender is the player. Chat gives a name with or without
-- the realm; the same name on another realm is somebody else.
function ns.IsMe(sender)
    if type(sender) ~= "string" then
        return false
    end
    return sender == UnitName("player") or sender == ns.Me()
end

-- What each class can play, for a character's first role switches. A class
-- not listed plays damage only.
local CLASS_ROLES = {
    WARRIOR = { tank = true, dps = true },
    PALADIN = { tank = true, healer = true, dps = true },
    DRUID = { tank = true, healer = true, dps = true },
    PRIEST = { healer = true, dps = true },
    SHAMAN = { healer = true, dps = true },
}

--- This character's role switches, { tank, healer, dps }, made from its
-- class the first time and saved from then on.
function ns.Roles()
    local key = ns.Me()
    local roles = ns.db.roles[key]
    if not roles then
        local _, class = UnitClass("player")
        local can = CLASS_ROLES[class] or { dps = true }
        roles = { tank = can.tank == true, healer = can.healer == true, dps = can.dps == true }
        ns.db.roles[key] = roles
    end
    return roles
end

--- Switch one of this character's roles ("tank", "healer", "dps") on or off.
-- The board and the settings page both write through here.
function ns.SetRole(role, on)
    ns.Roles()[role] = on and true or false
    ns.Changed()
end

--- Something on the board changed: redraw it, and the settings page, so
-- each shows a switch flipped on the other.
function ns.Changed()
    if ns.Window and ns.Window.Refresh then
        ns.Window.Refresh()
    end
    if ns.SettingsPanel then
        ns.SettingsPanel.Refresh()
    end
end

-- Slash commands. Each file registers its own.
local commands = {}

function ns.RegisterCommand(name, help, handler)
    commands[name] = { help = help, handler = handler }
end

function ns.ShowHelp()
    ns.Print("Commands:")
    ns.Print("/lfgb - open or close the board")

    local names = {}
    for name in pairs(commands) do
        table.insert(names, name)
    end
    table.sort(names)

    for _, name in ipairs(names) do
        ns.Print(string.format("/lfgb %s - %s", name, commands[name].help))
    end
end

local function runCommand(msg)
    local input = msg and msg:match("^%s*(.-)%s*$") or ""

    if input == "" then
        if ns.Window then
            ns.Window.Toggle()
        else
            ns.ShowHelp()
        end
        return
    end
    if input == "help" then
        ns.ShowHelp()
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
    ns.ShowHelp()
end

SLASH_LFGBOARD1 = "/lfgb"
SLASH_LFGBOARD2 = "/lfgboard"
SlashCmdList.LFGBOARD = runCommand

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
    end
end)
