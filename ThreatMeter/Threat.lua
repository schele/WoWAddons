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

--- The threat list as it stands: { mob, name, secret, rows }, the rows in
-- the order to show them. Plain numbers sort by threat, the most first.
-- Secret ones cannot, so then it is the tank, anyone over the tank, you,
-- and the group in its own order.
function Threat.Read()
    local list = { rows = {}, secret = false }
    local mob = Threat.Mob()
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

-- Keeping up: every change to the list, the target or the group asks for
-- one read on the next moment, however many arrive together.
local listeners = {}
local current = { rows = {}, secret = false }
local pending = false
local inCombat = false

function Threat.OnUpdate(fn)
    table.insert(listeners, fn)
end

--- The list as last read.
function Threat.Current()
    return current
end

function Threat.InCombat()
    return inCombat
end

local function update()
    pending = false
    current = Threat.Read()
    for _, fn in ipairs(listeners) do
        ns.Guarded(function() fn(current) end)
    end
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
    "PLAYER_ENTERING_WORLD",
}

local frame = CreateFrame("Frame")
for _, event in ipairs(EVENTS) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
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
