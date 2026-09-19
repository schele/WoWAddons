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

-- Faint enough not to compete with the rows drawn over it, visible enough
-- that the drag region reads as a thing you can grab rather than empty air.
local ANCHOR_BACKDROP_ALPHA = 0.12

--- Move the anchor to wherever the database currently says. Shared by the
-- initial placement, the deferred reset, and the drag-position save, so
-- there is exactly one place that turns db.anchor into a real SetPoint.
local function repositionAnchor()
    if anchor then
        anchor:ClearAllPoints()
        anchor:SetPoint(ns.db.anchor.point, ns.db.anchor.x, ns.db.anchor.y)
    end
end

-- Nothing secure may be written in combat: not a spell attribute, not showing
-- or hiding a button, not moving a row, because moving a row moves the secure
-- buttons inside it. Rather than attempt it and put an error in the player's
-- face, hold the change and do it the moment the fight ends. ForeverPanel's
-- ChatKeys.Apply holds its bindings the same way.
local pending = false

-- Set when Build was asked for during combat and could not run. Row.Create
-- writes secure attributes the same way ApplySpells does, so the whole build
-- -- not just the spells -- has to wait for the fight to end. Declared next
-- to pending, not further down with the rest of the queue, because Build
-- (above the queue in this file) has to be able to set both.
local buildPending = false

--- Run whatever combat is currently holding back. Cheap to call on spec --
-- Build returns immediately once the anchor exists, and ApplyAll re-checks
-- combat itself -- so both PLAYER_REGEN_ENABLED and PLAYER_ENTERING_WORLD
-- (which can arrive after a loading screen that swallowed the regen event)
-- call this rather than duplicating the build-then-apply order between them.
local function runPending()
    if buildPending and Group.Build() then
        Group.RefreshAll()
    end

    if pending then
        -- Covers a deferred /hc reset or drag-stop as well as a deferred
        -- ApplyAll: repositioning to whatever db.anchor already holds is a
        -- harmless no-op when nothing moved the anchor, and is exactly the
        -- move a reset or drag needs when something did.
        repositionAnchor()
        Group.ApplyAll()
    end
end

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
    -- Real height comes from Group.Layout, which always runs right after
    -- this (from Build); this starting size only matters for the instant
    -- before that first Layout call.
    anchor:SetSize(ns.Row.WIDTH, ns.Row.HEIGHT)

    local background = anchor:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(1, 1, 1, ANCHOR_BACKDROP_ALPHA)
    anchor.background = background

    repositionAnchor()
    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")

    anchor:SetScript("OnDragStart", function(self)
        if ns.db.bar.locked then
            return
        end

        if InCombatLockdown and InCombatLockdown() then
            -- StartMoving repositions every row hanging off this frame --
            -- rows full of secure buttons -- which the client refuses in
            -- combat the same as any other secure change.
            ns.Print("Cannot move the frame in combat.")
            return
        end

        self:StartMoving()
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
        -- pending is armed here too, not left for the caller to arm: the
        -- rows this build will eventually create start with no spell
        -- attributes at all, so whoever finishes the build later must also
        -- apply, whether they reached Build through the login handler or
        -- called it directly.
        buildPending = true
        pending = true
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

--- Stack the rows under the anchor, in the configured order, and size the
-- anchor to match.
--
-- A unit that is not in the party is skipped here, not just left for
-- RegisterUnitWatch to hide: hiding a row does not free its slot in the
-- stack, so with selfBottom on -- where your own row is always last -- a
-- two-person party used to lay out party1, party2, [hidden], [hidden],
-- player, leaving your row floating below a gap where the absent party
-- members would have gone. Skipping them keeps the visible rows contiguous.
function Group.Layout()
    if not anchor then
        return
    end

    local y = 0
    local placed = 0

    for _, unit in ipairs(Group.Units()) do
        local row = rows[unit]
        if row and UnitExists(unit) then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, y)
            y = y - (ns.Row.HEIGHT + ROW_GAP)
            placed = placed + 1
        end
    end

    -- The anchor is the whole draggable region, so it must cover the stack
    -- it is actually holding -- placed, not #Group.Units() -- or dragging
    -- would be grabbing a strip sized for rows that are not there.
    local rowCount = math.max(placed, 1)
    anchor:SetSize(ns.Row.WIDTH, rowCount * ns.Row.HEIGHT + (rowCount - 1) * ROW_GAP)
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

    if InCombatLockdown and InCombatLockdown() then
        -- The database is written either way; only the actual SetPoint --
        -- which moves every row hanging off the anchor, rows full of secure
        -- buttons -- waits, through the same pending queue ApplyAll uses.
        pending = true
        ns.Print("Frame will move to the middle once combat ends.")
    else
        repositionAnchor()
        ns.Print("Frame back in the middle.")
    end
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

        -- A roster change is also when Layout's contiguous stack can need
        -- reshuffling (a unit appearing or vanishing). ApplyAll is what
        -- knows to hold that re-stack, and the spell attributes it also
        -- reasserts, for combat to end -- RefreshAll alone never re-runs
        -- Layout at all.
        Group.ApplyAll()

        if event == "PLAYER_ENTERING_WORLD" then
            -- The one other point, besides regen-enabled, where a build or
            -- apply held by combat is worth retrying -- entering the world
            -- always follows combat ending, even on the runs where the
            -- regen-enabled event itself does not reach us.
            runPending()
        end
    elseif unit then
        refreshUnit(unit)
    end
end)

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
combatWatcher:SetScript("OnEvent", runPending)

ns.OnLogin(function()
    local _, class = UnitClass("player")
    ns.Slots.Seed(class)

    -- Build arms pending itself when combat holds it, so there is nothing
    -- left to queue here: a deferred build already guarantees the apply and
    -- the refresh it also needs will follow, once runPending gets to run.
    if Group.Build() then
        Group.ApplyAll()
        Group.RefreshAll()
    end

    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(RANGE_INTERVAL, Group.RefreshAll)
    end
end)
