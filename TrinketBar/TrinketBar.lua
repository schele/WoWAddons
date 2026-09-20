local addonName, ns = ...

ns.PREFIX = "|cffcc88ffTrinketBar|r"

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

ns.applyDefaults = applyDefaults

--- Register additional defaults. Called at file load, before ADDON_LOADED.
function ns.AddDefaults(extra)
    applyDefaults(defaults, extra)
end

function ns.Print(message)
    print(string.format("%s %s", ns.PREFIX, message))
end

--- Call `fn` and return what it returns, or `whenUnknown` if it raises.
--
-- Some clients hand tainted code (ours) a "secret" value: the API call that
-- produced it succeeds, but the client refuses to let addon code inspect the
-- result afterwards -- comparing it, or testing its truthiness, raises
-- "attempt to perform boolean test on ... a secret ... value". Which
-- particular return is secret varies by client build and by how the call was
-- reached, so every branch on one of these values in this addon is routed
-- through here, in one place, rather than guarded ad hoc.
--
-- `fn` must both make the call and perform the branch that can raise, not
-- just fetch a value for the caller to test afterwards -- in the game it is
-- the branch that raises, the call having already succeeded. Routing both
-- through the same pcall is also what makes this testable at all: Lua has no
-- way to construct a value that raises when its truthiness is checked, so a
-- test instead makes the stubbed API call itself raise. Both failure shapes
-- land in this same pcall, so the fallback path is exercised even though the
-- exact in-game trigger (a secret value, not a raising call) cannot be
-- reproduced.
function ns.Guarded(fn, whenUnknown)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return whenUnknown
end

-- Settings registry. A file declares the config it owns, and Settings.lua
-- renders what it finds.
local settings = {}
ns.settings = settings

-- checkbox and slider are the shapes UrlCopy's panel already knows. spelltable
-- is this addon's own: one row per slot, holding a spell name.
local SETTING_TYPES = { checkbox = true, slider = true, spelltable = true }

function ns.RegisterSetting(definition)
    assert(type(definition) == "table", "RegisterSetting expects a table")

    local store, key = definition.store, definition.key
    assert(type(store) == "string" and store ~= "", "setting requires a store")
    assert(type(key) == "string" and key ~= "", "setting requires a key")
    assert(type(definition.name) == "string", "setting requires a name")
    assert(
        SETTING_TYPES[definition.type],
        "unknown setting type: " .. tostring(definition.type)
    )

    -- A setting with no default reads nil and writes somewhere nothing else
    -- looks, which shows up as a control that silently does nothing.
    assert(
        type(defaults[store]) == "table" and defaults[store][key] ~= nil,
        string.format("no default registered for %s.%s", store, key)
    )

    table.insert(settings, definition)
    return definition
end

function ns.SettingValue(setting)
    local store = ns.db and ns.db[setting.store]
    return store and store[setting.key]
end

function ns.SetSettingValue(setting, value)
    local store = ns.db and ns.db[setting.store]
    if not store or store[setting.key] == value then
        return
    end

    store[setting.key] = value
    if setting.onChange then
        setting.onChange(value)
    end
end

local function ensureDatabase()
    if type(TrinketBarDB) ~= "table" then
        TrinketBarDB = {}
    end

    applyDefaults(TrinketBarDB, defaults)
    ns.db = TrinketBarDB
end

ns.ensureDatabase = ensureDatabase

-- Slash commands. Each file registers its own, so a feature owns its commands
-- and its help text.
local commands = {}
ns.commands = commands

local helpLines = {}
ns.helpLines = helpLines

function ns.RegisterCommand(name, help, handler)
    commands[name] = { help = help, handler = handler }
end

-- Headings for the settings panel's columns, by the key a setting names in
-- its `column` field. A column nobody titles simply has no heading, and a
-- setting that names no column goes in the left one.
local columns = {}
ns.columns = columns

function ns.RegisterColumn(key, title)
    columns[key] = title
end

function ns.RegisterHelpLine(line)
    table.insert(helpLines, line)
end

local function showHelp()
    ns.Print("Commands:")

    for _, line in ipairs(helpLines) do
        ns.Print(line)
    end

    local names = {}
    for name in pairs(commands) do
        table.insert(names, name)
    end
    table.sort(names)

    for _, name in ipairs(names) do
        ns.Print(string.format("/tb %s - %s", name, commands[name].help))
    end
end

ns.ShowHelp = showHelp

local function runCommand(msg)
    local input = msg and msg:match("^%s*(.-)%s*$") or ""

    -- A bare "/tb" lists the commands, the same as "/fp", "/url" and "/ch" do.
    -- Four addons whose login lines sit together must not disagree about this.
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

SLASH_TRINKETBAR1 = "/trinketbar"
SLASH_TRINKETBAR2 = "/tb"
SlashCmdList.TRINKETBAR = runCommand

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

        ns.Print("Loaded. Type /tb for commands.")
    end
end)
