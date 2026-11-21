local addonName, ns = ...

-- Reads who has how much threat on the mob you are fighting, and tells the
-- window and the warning whenever it changes.
--
-- WoW Forever hands the numbers out secret when the mob is a boss
-- (UnitDetailedThreatSituation is SecretWhenUnitThreatValuesRestricted), but
-- not who is tanking or over the tank (UnitThreatSituation is only
-- SecretWhenUnitThreatStateRestricted, plain against a boss or your target).
-- A secret number cannot be compared, so on a boss the list is ordered by
-- that state instead, and the numbers are handed on for a status bar to draw.

local Threat = {}
ns.Threat = Threat

local IsSecret = ns.IsSecret

local function attackable(token)
    return ns.Guarded(function()
        return UnitExists(token) and UnitCanAttack("player", token) and not UnitIsDeadOrGhost(token)
    end, false)
end

--- The mob whose threat list to read: your target, or with a friendly
-- target (a healer on the tank), whatever that one has targeted. Nil when
-- neither is an enemy.
function Threat.Mob()
    if attackable("target") then
        return "target"
    end
    if UnitExists("target") and attackable("targettarget") then
        return "targettarget"
    end
    return nil
end

--- Everyone who can be on the threat list with you: you and your pet, then
-- the party or the raid and their pets, in the group's own order.
function Threat.Units()
    local units = { "player" }
    local function add(token)
        if UnitExists(token) then
            table.insert(units, token)
        end
    end
    add("pet")

    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            local token = "raid" .. index
            -- Your own raid token, and its pet, are already in as player and pet.
            if UnitExists(token) and not UnitIsUnit(token, "player") then
                table.insert(units, token)
                add("raidpet" .. index)
            end
        end
    elseif IsInGroup() then
        for index = 1, GetNumSubgroupMembers() do
            add("party" .. index)
            add("partypet" .. index)
        end
    end
    return units
end

local function counted(...)
    return select("#", ...), ...
end

--- One unit's place on `mob`'s threat list, or nil when it has none.
local function readUnit(token, mob)
    local count, tanking, status, scaled = counted(UnitDetailedThreatSituation(token, mob))
    if count == 0 then
        return nil
    end

    local _, classFile = UnitClass(token)
    local row = {
        unit = token,
        name = UnitName(token),
        classFile = classFile,
        isPlayer = token == "player",
    }

    if IsSecret(tanking) or IsSecret(status) or IsSecret(scaled) then
        -- Who is tanking or over the tank, from the call the game leaves plain.
        local plain = UnitThreatSituation(token, mob)
        row.status = (not IsSecret(plain)) and plain or nil
        row.tanking = row.status ~= nil and row.status >= 2
        row.scaled = scaled
        row.secret = true
        return row
    end

    if status == nil then
        return nil
    end
    row.status = status
    row.tanking = tanking and true or false
    row.scaled = scaled or 0
    return row
end

--- A threat list as it stands: { mob, name, secret, rows }, the rows in
-- the order to show them. Plain numbers sort by threat, the most first.
-- Secret ones cannot, so then it is the tank, anyone over the tank, you,
-- and the group in its own order. Of `mob`, or else the one you fight.
function Threat.Read(mob)
    local list = { rows = {}, secret = false }
    mob = mob or Threat.Mob()
    if not mob then
        return list
    end
    list.mob = mob
    list.name = UnitName(mob)

    for index, token in ipairs(Threat.Units()) do
        local row = ns.Guarded(function() return readUnit(token, mob) end)
        if row then
            row.order = index
            list.secret = list.secret or row.secret or false
            table.insert(list.rows, row)
        end
    end

    if list.secret then
        table.sort(list.rows, function(a, b)
            local sa, sb = a.status or -1, b.status or -1
            if sa ~= sb then return sa > sb end
            if a.isPlayer ~= b.isPlayer then return a.isPlayer end
            return a.order < b.order
        end)
    else
        table.sort(list.rows, function(a, b)
            if a.scaled ~= b.scaled then return a.scaled > b.scaled end
            if a.tanking ~= b.tanking then return a.tanking end
            return a.order < b.order
        end)
    end
    return list
end

-- A part for each mob you fight: your target, then the mobs with a
-- nameplate that you or your group are on the threat list of, the one
-- closest to changing hands first. Nameplate tokens are among those the
-- game shows threat numbers for, but for a boss.
ns.AddDefaults({
    split = true,
    maxMobs = 3,
})
Threat.MOST_MOBS = 5
local PLATES = 40

local function plateOf(token)
    return ns.Guarded(function()
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(token)
        return plate and plate.namePlateUnitToken
    end)
end

local function fighting(token)
    return ns.Guarded(function()
        return (UnitExists(token) and UnitCanAttack("player", token) and not UnitIsDeadOrGhost(token)
            and UnitAffectingCombat(token)) and true or false
    end, false)
end

--- How close a mob is to changing hands: anyone the game says is over the
-- tank comes first, numbers hidden or not; then the highest threat of
-- anyone not tanking, where the numbers show.
local function danger(list)
    local most = 0
    for _, row in ipairs(list.rows) do
        if not row.tanking then
            if row.status == 1 then
                return 1000
            end
            if not row.secret and type(row.scaled) == "number" and row.scaled > most then
                most = row.scaled
            end
        end
    end
    return most
end

--- The lists to show, given `first`, your target's: just that one, or with
-- a part per mob, it and the other mobs your group fights, up to the most
-- set. With nothing targeted, the mobs alone; with none of those either,
-- the empty `first`, which says no enemy is targeted.
function Threat.ReadAll(first)
    first = first or Threat.Read()
    local settings = ns.settings
    if not (settings and settings.split) then
        return { first }
    end
    local most = math.max(1, math.min(Threat.MOST_MOBS, settings.maxMobs or 3))

    local lists, skip = {}, {}
    if first.mob then
        lists[1] = first
        local plate = plateOf(first.mob)
        if plate then
            skip[plate] = true
        end
    end

    local others = {}
    for index = 1, PLATES do
        local token = "nameplate" .. index
        if not skip[token] and fighting(token) then
            local list = Threat.Read(token)
            if #list.rows > 0 then
                list.order, list.danger = index, danger(list)
                others[#others + 1] = list
            end
        end
    end
    table.sort(others, function(a, b)
        if a.danger ~= b.danger then return a.danger > b.danger end
        return a.order < b.order
    end)
    for _, list in ipairs(others) do
        if #lists >= most then
            break
        end
        lists[#lists + 1] = list
    end

    if #lists == 0 then
        lists[1] = first
    end
    return lists
end

-- Keeping up: every change to the list, the target or the group asks for
-- one read on the next moment, however many arrive together.
local listeners = {}
local current = { rows = {}, secret = false }
local all = { current }
local pending = false
local inCombat = false

function Threat.OnUpdate(fn)
    table.insert(listeners, fn)
end

--- Your target's list as last read.
function Threat.Current()
    return current
end

--- Every list to show as last read: your target's first.
function Threat.All()
    return all
end

function Threat.InCombat()
    return inCombat
end

-- The demo: made-up mobs and a party, to see how the window looks without
-- a fight or a group. /threat demo, again or a fight, ends it.
local demo = false

local function demoRow(name, classFile, scaled, status, isPlayer)
    return {
        unit = "demo", name = name, classFile = classFile, scaled = scaled, status = status,
        tanking = status >= 2, isPlayer = isPlayer or false,
    }
end

local function demoLists()
    local me = UnitName("player") or "You"
    local _, myClass = UnitClass("player")
    local function list(name, rows)
        return { mob = "demo", name = name, rows = rows, secret = false }
    end
    return {
        list("Defias Pillager", {
            demoRow("Brann", "WARRIOR", 100, 3), demoRow(me, myClass, 87, 0, true),
            demoRow("Celia", "MAGE", 64, 0), demoRow("Dorn", "PRIEST", 31, 0),
            demoRow("Wolf", nil, 18, 0), demoRow("Aldira", "DRUID", 9, 0),
        }),
        list("Defias Thug", {
            demoRow("Brann", "WARRIOR", 100, 2), demoRow("Celia", "MAGE", 96, 1),
            demoRow(me, myClass, 40, 0, true),
        }),
        list("Defias Looter", { demoRow("Brann", "WARRIOR", 100, 3), demoRow("Dorn", "PRIEST", 22, 0) }),
        list("Defias Miner", { demoRow(me, myClass, 100, 3, true) }),
    }
end

--- The demo's lists, as the settings would show them.
local function demoAll(lists)
    local settings = ns.settings or {}
    if not settings.split then
        return { lists[1] }
    end
    local shown = {}
    for index = 1, math.min(#lists, settings.maxMobs or 3) do
        shown[index] = lists[index]
    end
    return shown
end

function Threat.InDemo()
    return demo
end

local function update()
    pending = false
    if demo then
        local lists = demoLists()
        current, all = lists[1], demoAll(lists)
    else
        current = Threat.Read()
        all = Threat.ReadAll(current)
    end
    for _, fn in ipairs(listeners) do
        ns.Guarded(function() fn(current) end)
    end
end

--- Show the made-up mobs, or stop.
function Threat.Demo(on)
    demo = on and true or false
    update()
end

function Threat.Update()
    if pending then
        return
    end
    pending = true
    C_Timer.After(0.1, update)
end

local EVENTS = {
    "PLAYER_TARGET_CHANGED", "UNIT_TARGET", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
    "GROUP_ROSTER_UPDATE", "UNIT_PET", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
}

-- A setting changed (a part per mob, how many): read again.
ns.OnRefresh(function() Threat.Update() end)

local frame = CreateFrame("Frame")
for _, event in ipairs(EVENTS) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        -- A real fight ends the demo.
        demo = false
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif event == "UNIT_TARGET" and unit ~= "target" then
        -- Only your target's target matters, for a healer on the tank.
        return
    end
    Threat.Update()
end)

ns.OnLogin(function()
    inCombat = UnitAffectingCombat("player") and true or false
    Threat.Update()
end)

--- A row as a line of /threat check: "Brann 100% (tanking)".
local function describe(row)
    local amount = ns.Guarded(function()
        return string.format("%d%%", math.floor(row.scaled + 0.5))
    end, "hidden")
    local note = ""
    if row.tanking then
        note = " (tanking)"
    elseif row.status == 1 then
        note = " (over the tank)"
    end
    return string.format("%s %s%s", tostring(row.name), amount, note)
end

ns.RegisterCommand("demo", "Show the window with made-up numbers, to see how it looks", function()
    if demo then
        Threat.Demo(false)
        ns.Print("Demo ended.")
    else
        Threat.Demo(true)
        ns.Print("Showing made-up numbers. /threat demo again, or a fight, ends it.")
    end
end)

ns.RegisterCommand("check", "Say what the game tells about threat on your target", function()
    local list = Threat.Read()
    if not list.mob then
        ns.Print("No enemy targeted.")
        return
    end

    -- A mob's name can come secret, and a secret is no use in chat.
    local name = "Your target"
    if type(list.name) == "string" and not IsSecret(list.name) then
        name = list.name
    end
    ns.Print(string.format("%s: the game %s the numbers.", name, list.secret and "hides" or "shows"))
    if #list.rows == 0 then
        ns.Print("Nobody in your group is on its threat list.")
        return
    end
    local lines = {}
    for _, row in ipairs(list.rows) do
        table.insert(lines, describe(row))
    end
    ns.Print(table.concat(lines, ", ") .. ".")
end)
