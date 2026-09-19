local addonName, ns = ...

-- The five rows, their order, and the frame you drag to put them somewhere.

local Group = {}
ns.Group = Group

local PARTY = { "party1", "party2", "party3", "party4" }
local ROW_GAP = 2

-- Range has no event. Five times a second is fast enough to be useful and slow
-- enough to cost nothing; it is the only polling in the addon.
local RANGE_INTERVAL = 0.2

local DEFAULT_ANCHOR = { point = "CENTER", x = 0, y = -200 }

ns.AddDefaults({
    anchor = {
        point = DEFAULT_ANCHOR.point,
        x = DEFAULT_ANCHOR.x,
        y = DEFAULT_ANCHOR.y,
    },
})

local anchor
local rows = {}

-- Set when Build was asked for during combat and could not run. Row.Create
-- writes secure attributes the same way ApplySpells does, so the whole build
-- -- not just the spells -- has to wait for the fight to end.
local buildPending = false

--- The five units in display order. A function rather than a constant,
-- because where your own row sits is the player's choice.
function Group.Units()
    local units = {}

    if not (ns.db and ns.db.bar.selfBottom) then
        units[#units + 1] = "player"
    end

    for _, unit in ipairs(PARTY) do
        units[#units + 1] = unit
    end

    if ns.db and ns.db.bar.selfBottom then
        units[#units + 1] = "player"
    end

    return units
end

function Group.Rows()
    return rows
end

function Group.Anchor()
    return anchor
end

local function createAnchor()
    anchor = CreateFrame("Frame", "HealclickAnchor", UIParent)
    anchor:SetSize(ns.Row.WIDTH, 1)
    anchor:SetPoint(ns.db.anchor.point, ns.db.anchor.x, ns.db.anchor.y)
    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")

    anchor:SetScript("OnDragStart", function(self)
        if not ns.db.bar.locked then
            self:StartMoving()
        end
    end)

    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        ns.db.anchor.point = point or DEFAULT_ANCHOR.point
        ns.db.anchor.x = x or DEFAULT_ANCHOR.x
        ns.db.anchor.y = y or DEFAULT_ANCHOR.y
    end)
end

--- Build the anchor and one row per unit. Out of combat only: Row.Create's
-- SetAttribute is refused mid-fight the same as anything ApplyAll queues,
-- and PLAYER_LOGIN genuinely can fire while the player is fighting -- a
-- /reload during a pull, or reconnecting after a disconnect mid-fight.
-- Returns true once the rows exist (now, or from an earlier call), false
-- when the build was held for later -- the same contract as ApplyAll.
function Group.Build()
    if anchor then
        return true
    end

    if InCombatLockdown and InCombatLockdown() then
        buildPending = true
        return false
    end

    -- Cleared only here, after the check above: creating the anchor is what
    -- satisfies the guard just above it, so it must not happen until we know
    -- the row loop below is actually about to run.
    buildPending = false
    createAnchor()

    -- Every unit gets a row, including ones nobody is standing in. They are
    -- built now because they cannot be built later: creating a frame with
    -- secure buttons is one more thing the client refuses mid-fight.
    for _, unit in ipairs(Group.Units()) do
        local row = ns.Row.Create(unit, anchor)
        rows[unit] = row

        if RegisterUnitWatch then
            RegisterUnitWatch(row)
        end
    end

    Group.Layout()
    return true
end

--- Stack the rows under the anchor, in the configured order.
function Group.Layout()
    if not anchor then
        return
    end

    local y = 0

    for _, unit in ipairs(Group.Units()) do
        local row = rows[unit]
        if row then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, y)
            y = y - (ns.Row.HEIGHT + ROW_GAP)
        end
    end
end

function Group.RefreshAll()
    for _, row in pairs(rows) do
        ns.Row.Refresh(row)
    end
end

local function refreshUnit(unit)
    local row = rows[unit]
    if row then
        ns.Row.Refresh(row)
    end
end

ns.RegisterCommand("lock", "Stop the frame being dragged", function()
    ns.db.bar.locked = not ns.db.bar.locked
    ns.Print(ns.db.bar.locked and "Frame locked." or "Frame unlocked.")
end)

ns.RegisterCommand("reset", "Put the frame back in the middle", function()
    ns.db.anchor.point = DEFAULT_ANCHOR.point
    ns.db.anchor.x = DEFAULT_ANCHOR.x
    ns.db.anchor.y = DEFAULT_ANCHOR.y

    if anchor then
        anchor:ClearAllPoints()
        anchor:SetPoint(ns.db.anchor.point, ns.db.anchor.x, ns.db.anchor.y)
    end

    ns.Print("Frame back in the middle.")
end)

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UNIT_HEALTH")
watcher:RegisterEvent("UNIT_MAXHEALTH")
watcher:RegisterEvent("UNIT_CONNECTION")
watcher:RegisterEvent("PLAYER_FLAGS_CHANGED")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")

watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        -- Names and classes change wholesale, so no single row is enough.
        Group.RefreshAll()
    elseif unit then
        refreshUnit(unit)
    end
end)

-- Nothing secure may be written in combat: not a spell attribute, not showing
-- or hiding a button, not moving a row, because moving a row moves the secure
-- buttons inside it. Rather than attempt it and put an error in the player's
-- face, hold the change and do it the moment the fight ends. ForeverPanel's
-- ChatKeys.Apply holds its bindings the same way.
local pending = false

function Group.Pending()
    return pending
end

--- Write every row's spells and re-stack the rows.
-- Returns true when it happened, false when it was held for later.
function Group.ApplyAll()
    if not anchor then
        return false
    end

    if InCombatLockdown and InCombatLockdown() then
        pending = true
        return false
    end

    pending = false
    Group.Layout()

    for _, row in pairs(rows) do
        ns.Row.ApplySpells(row)
    end

    return true
end

local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:SetScript("OnEvent", function()
    -- A build owed from login outranks the spells: there is nothing to apply
    -- them to until the rows it was waiting to create actually exist.
    if buildPending then
        Group.Build()
    end

    if pending then
        Group.ApplyAll()
    end
end)

ns.OnLogin(function()
    local _, class = UnitClass("player")
    ns.Slots.Seed(class)

    -- Build can be held by combat. When it is, Rows() is still empty, so
    -- applying spells or refreshing would either quietly do nothing (and be
    -- forgotten -- ApplyAll only remembers to retry once it has already been
    -- asked while anchor exists) or, for RefreshAll, just no-op on an empty
    -- table. Queue both behind the build instead, so the regen-enabled
    -- handler above carries them out once the rows are real.
    if Group.Build() then
        Group.ApplyAll()
        Group.RefreshAll()
    else
        pending = true
    end

    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(RANGE_INTERVAL, Group.RefreshAll)
    end
end)
