local addonName, ns = ...

ns.PREFIX = "|cff66ccffTalentPlanner|r"

-- Defaults are contributed by each file at load time, so every piece of config
-- lives next to the code that reads it and this file never learns the others.
local defaults = {
    version = 1,
    -- The four switches on the settings page.
    remind = true,
    overlay = true,
    learn = false,
    -- Plans, per character: chars["Name-Realm"] = { active = name, plans = {} }.
    chars = {},
}

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

local function ensureDatabase()
    if type(TalentPlannerDB) ~= "table" then
        TalentPlannerDB = {}
    end

    applyDefaults(TalentPlannerDB, defaults)
    ns.db = TalentPlannerDB
end

--------------------------------------------------------------------------------
-- Changes: whoever draws a plan redraws when one changes
--------------------------------------------------------------------------------

local listeners = {}

function ns.OnChange(fn)
    table.insert(listeners, fn)
end

function ns.Changed()
    for _, fn in ipairs(listeners) do
        fn()
    end
end

--- Turn one of the settings page's switches; remembered.
function ns.SetSetting(key, value)
    ns.db[key] = value and true or false
    ns.Changed()
    if ns.SettingsPanel then
        ns.SettingsPanel.Refresh()
    end
end

--------------------------------------------------------------------------------
-- The character and its plans
--------------------------------------------------------------------------------

function ns.CharKey()
    local name = ns.Guarded(function() return UnitName("player") end) or "?"
    local realm = ns.Guarded(function() return GetRealmName() end) or "?"
    return name .. "-" .. realm:gsub("%s", "")
end

function ns.PlayerClass()
    return ns.Guarded(function()
        local _, class = UnitClass("player")
        return class
    end)
end

local function character()
    local key = ns.CharKey()
    local saved = ns.db.chars[key]
    if type(saved) ~= "table" then
        saved = {}
        ns.db.chars[key] = saved
    end
    if type(saved.plans) ~= "table" then
        saved.plans = {}
    end
    return saved
end

local Plans = {}
ns.Plans = Plans

local function newPlan()
    return { class = ns.PlayerClass() or "?", points = {} }
end

--- The first "<base>", "<base> 2", ... not yet taken.
local function freeName(plans, base, numberFirst)
    if not numberFirst and not plans[base] then
        return base
    end
    local n = numberFirst and 1 or 2
    while plans[base .. " " .. n] do
        n = n + 1
    end
    return base .. " " .. n
end

function Plans.Names()
    local names = {}
    for name in pairs(character().plans) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

--- The plan being worked on and its name. A character without one gets
-- "Plan 1", so there is always something to draw and add to.
function Plans.Active()
    local saved = character()
    local plan = saved.active and saved.plans[saved.active]
    if not plan then
        saved.active = Plans.Names()[1]
        plan = saved.active and saved.plans[saved.active]
    end
    if not plan then
        saved.active = freeName(saved.plans, "Plan", true)
        plan = newPlan()
        saved.plans[saved.active] = plan
    end
    if type(plan.points) ~= "table" then
        plan.points = {}
    end
    return plan, saved.active
end

local function checkName(name)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then
        return nil, "A plan needs a name."
    end
    if character().plans[name] then
        return nil, "There is already a plan called " .. name .. "."
    end
    return name
end

function Plans.Select(name)
    local saved = character()
    if saved.plans[name] then
        saved.active = name
        ns.Changed()
    end
end

--- A plan holding `points`, made active. Taken as given: the caller checked it.
function Plans.Store(name, points)
    local checked, why = checkName(name)
    if not checked then
        return false, why
    end
    local saved = character()
    local plan = newPlan()
    plan.points = points or {}
    saved.plans[checked] = plan
    saved.active = checked
    ns.Changed()
    return true, checked
end

function Plans.New(name)
    return Plans.Store(name, {})
end

function Plans.Rename(name)
    local plan, old = Plans.Active()
    if name and name:match("^%s*(.-)%s*$") == old then
        return true, old
    end
    local checked, why = checkName(name)
    if not checked then
        return false, why
    end
    local saved = character()
    saved.plans[old] = nil
    saved.plans[checked] = plan
    saved.active = checked
    ns.Changed()
    return true, checked
end

function Plans.Delete()
    local _, name = Plans.Active()
    local saved = character()
    saved.plans[name] = nil
    saved.active = nil
    ns.Changed()
    return name
end

--------------------------------------------------------------------------------
-- Export and import
--------------------------------------------------------------------------------

function ns.Export()
    local plan = Plans.Active()
    return ns.Codec.Encode(plan.class, plan.points)
end

--- Check a pasted string against the class and every rule, and keep it as
-- a new plan. True and its name, or false and why.
function ns.Import(text)
    local decoded, why = ns.Codec.Decode(text)
    if not decoded then
        return false, why
    end
    local class = ns.PlayerClass()
    if decoded.class ~= class then
        return false, string.format("This plan is for a %s; you are a %s.", decoded.class, tostring(class))
    end
    local trees, missing = ns.Trees.Read()
    if not trees then
        return false, ns.Trees.Unreadable(missing)
    end
    local ok, bad, reason = ns.Plan.Validate(trees, decoded.points)
    if not ok then
        return false, ns.Plan.Describe(trees, bad, decoded.points[bad]) .. ": " .. reason
    end
    return Plans.Store(freeName(character().plans, "Imported"), decoded.points)
end

--------------------------------------------------------------------------------
-- Slash commands. Each file registers its own, so a feature owns its commands
-- and its help text.
--------------------------------------------------------------------------------

local commands = {}
ns.commands = commands

function ns.RegisterCommand(name, help, handler)
    commands[name] = { help = help, handler = handler }
end

local function showHelp()
    ns.Print("Commands:")
    ns.Print("/tp - Open or close the planner")

    local names = {}
    for name in pairs(commands) do
        table.insert(names, name)
    end
    table.sort(names)

    for _, name in ipairs(names) do
        ns.Print(string.format("/tp %s - %s", name, commands[name].help))
    end
end

local function runCommand(msg)
    local input = msg and msg:match("^%s*(.-)%s*$") or ""

    if input == "" then
        if ns.Planner then
            ns.Planner.Toggle()
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

SLASH_TALENTPLANNER1 = "/talentplanner"
SLASH_TALENTPLANNER2 = "/tp"
SlashCmdList.TALENTPLANNER = runCommand

local function report(ok, result)
    if ok then
        ns.Print("Plan: " .. result .. ".")
    else
        ns.Print(result)
    end
end

ns.RegisterCommand("new", "Start a new plan: /tp new <name>", function(rest)
    report(Plans.New(rest))
end)

ns.RegisterCommand("rename", "Rename the plan: /tp rename <name>", function(rest)
    report(Plans.Rename(rest))
end)

ns.RegisterCommand("delete", "Delete the plan", function()
    ns.Print("Deleted " .. Plans.Delete() .. ".")
end)

--------------------------------------------------------------------------------
-- /tp probe: what this client has, for the in-game check
--------------------------------------------------------------------------------

local PROBED = {
    "GetNumTalentTabs", "GetTalentTabInfo", "GetNumTalents", "GetTalentInfo", "GetTalentPrereqs",
    "UnitCharacterPoints", "GetUnspentTalentPoints", "LearnTalent",
}

local function has(value)
    return value and "yes" or "no"
end

--- The game's talent window, if it has been made: its name and buttons.
function ns.TalentWindow()
    for _, name in ipairs({ "PlayerTalentFrame", "TalentFrame" }) do
        local frame = _G[name]
        if frame then
            local count = 0
            while _G[name .. "Talent" .. (count + 1)] do
                count = count + 1
            end
            return frame, name, count
        end
    end
end

local function probe()
    ns.Print("Talent calls on this client:")
    for _, name in ipairs(PROBED) do
        ns.Print(string.format("%s: %s", name, has(type(_G[name]) == "function")))
    end
    ns.Print("GameTooltip:SetTalent: " .. has(GameTooltip and GameTooltip.SetTalent))
    ns.Print("Menus: MenuUtil " .. has(MenuUtil and MenuUtil.CreateContextMenu) .. ", EasyMenu " .. has(EasyMenu))

    local shape = ns.Guarded(function()
        return type((GetTalentTabInfo(1))) == "string" and "name first" or "ID first"
    end, "unreadable")
    ns.Print("Tab info: " .. shape)

    local trees, missing = ns.Trees.Read()
    if trees then
        local parts = {}
        for _, tree in ipairs(trees) do
            local count = 0
            for _ in pairs(tree.talents) do
                count = count + 1
            end
            parts[#parts + 1] = tree.name .. " " .. count
        end
        ns.Print("Trees: " .. table.concat(parts, ", "))
    else
        ns.Print("Trees: " .. ns.Trees.Unreadable(missing))
    end
    ns.Print("Unspent points: " .. tostring(ns.Trees.Unspent()))

    local _, windowName, buttons = ns.TalentWindow()
    if windowName then
        ns.Print(string.format("Talent window: %s, %d buttons", windowName, buttons))
    else
        ns.Print("Talent window: not loaded yet (open it once, then probe again)")
    end

    local learn = ns.Reminder and ns.Reminder.LastLearn()
    if not learn then
        ns.Print("Learn next: not tried this session")
    elseif learn.result == "worked" then
        ns.Print("Learn next: the client learned " .. learn.name)
    elseif learn.result == "refused" then
        ns.Print("Learn next: the client refused " .. learn.name)
    else
        ns.Print("Learn next: asked for " .. learn.name .. ", no answer yet")
    end
end

ns.RegisterCommand("probe", "Show which talent calls this client has", probe)

--------------------------------------------------------------------------------
-- Login
--------------------------------------------------------------------------------

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

        ns.Print("Loaded. Type /tp for the planner.")
    end
end)
