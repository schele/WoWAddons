local addonName, ns = ...

ns.PREFIX = "|cff66ccffFishScale|r"

-- Defaults are contributed by each file at load time, so every piece of config
-- lives next to the code that reads it and this file never learns the others.
local defaults = {
    version = 1,
}

-- Bumped whenever a stored value has to change for an existing player.
--
-- Changing a default cannot do that: applyDefaults fills in what is absent
-- and leaves what is stored, which is right for a value the player chose and
-- wrong for one this addon chose badly and retracted. A shipped default
-- change is invisible to everyone who has run the addon before -- which cost
-- two rounds of a player testing an arc that had already been ruled out.
local DB_VERSION = 2

-- version to run at -> what to do. Each file registers its own, next to the
-- setting it concerns.
local migrations = {}

function ns.AddMigration(version, fn)
    migrations[version] = migrations[version] or {}
    table.insert(migrations[version], fn)
end

--- Merge a defaults table into a saved table without clobbering stored values.
-- Recursive, so config added in a later version gets filled in on upgrade
-- instead of the whole branch being left empty.
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

-- Settings registry. A file declares the config it owns, and Settings.lua
-- renders what it finds, so adding a setting needs no edit there.
local settings = {}
ns.settings = settings

-- A slider for a number, a checkbox for a flag, and keybind for the one
-- setting that is neither: a key is not a value to be typed, it is a key to
-- be pressed, and the panel captures it that way.
local SETTING_TYPES = { checkbox = true, slider = true, keybind = true }

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
    if type(FishScaleDB) ~= "table" then
        FishScaleDB = {}
    end

    applyDefaults(FishScaleDB, defaults)
    ns.db = FishScaleDB

    -- Run after the defaults, so a migration can rely on every key existing,
    -- and in order, so a database several versions behind arrives by the
    -- same route as one a single version behind.
    local from = tonumber(FishScaleDB.version) or 1
    for version = from + 1, DB_VERSION do
        for _, migrate in ipairs(migrations[version] or {}) do
            migrate(FishScaleDB)
        end
    end
    FishScaleDB.version = DB_VERSION
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
        ns.Print(string.format("/fs %s - %s", name, commands[name].help))
    end
end

local function runCommand(msg)
    local input = msg and msg:match("^%s*(.-)%s*$") or ""

    -- A bare /fs opens the panel, where the sibling addons list their
    -- commands. Everything here can be set by pointing at it, so the list is
    -- the second thing a player wants and the window is the first; `/fs help`
    -- still prints it, and every command still works for when something
    -- needs diagnosing.
    if input == "" then
        if ns.OpenSettings then
            ns.OpenSettings()
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

SLASH_FISHSCALE1 = "/fishscale"
SLASH_FISHSCALE2 = "/fs"
SlashCmdList.FISHSCALE = runCommand

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

        -- /fs opens the panel now; it stopped listing commands when there
        -- was somewhere better to send people. A login line still promising
        -- a list is the sort of small lie that wastes someone's first minute.
        ns.Print("Loaded. Type /fs for settings, or /fs help for commands.")
    end
end)
