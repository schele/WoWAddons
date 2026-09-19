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
    bar = {
        -- On by default: icons beside the party frames is what people
        -- picture when they ask for this, and Row.Attached drops back to the
        -- standalone bar by itself on a UI with no frames to hang from.
        attached = true,
        -- Clear of the frame rather than flush against it. The space to the
        -- right of a party frame is also where its buffs and debuffs draw,
        -- so these are settings rather than constants.
        attachX = 8,
        attachY = 0,
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
        -- move a reset or drag needs when something did. Guarded the same
        -- way Group.Build and Group.ApplyAll guard themselves, unlike those
        -- two this call had no check of its own: PLAYER_ENTERING_WORLD can
        -- fire while still in combat (the whole reason it also calls this),
        -- and SetPoint on the anchor moves every row of secure buttons
        -- hanging off it.
        if not (InCombatLockdown and InCombatLockdown()) then
            repositionAnchor()
        end
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
    anchor:SetSize(ns.Row.CurrentWidth(), ns.Row.HEIGHT)

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
--- Hang each row off its unit's own Blizzard frame.
--
-- The anchor stays shown even though nothing of it is drawn: the rows are
-- its children, and hiding a frame hides everything under it, so hiding the
-- anchor here would take every row -- icons included -- with it. Its
-- backdrop is hidden instead, and its mouse turned off so an invisible
-- rectangle cannot be dragged around by accident.
--
-- A unit whose frame is missing keeps whatever position it had. That is the
-- ordinary case for party2-4 in a small group, not a failure: those rows are
-- hidden by RegisterUnitWatch anyway, so where they sit does not matter.
-- How many deferred passes a single layout is allowed to ask for before it
-- gives up. Bounded because a frame that is never coming would otherwise
-- queue a retry on every pass, for ever. Reset whenever something happens
-- that could plausibly have created the frames.
-- Seconds to wait before each successive retry. Backing off rather than
-- repeating: the first version fired all its tries inside five frames, about
-- eighty milliseconds, which is no wait at all for a UI that is still
-- building itself. This covers the first eight seconds after login and then
-- stops, so a UI that will never have party frames is not left queueing
-- passes for the rest of the session.
local RELAYOUT_DELAYS = { 0, 0.1, 0.25, 0.5, 1, 2, 4 }
local relayoutStep = 0
local relayoutQueued = false

--- Ask for one more layout pass shortly, because a frame we wanted was not
-- there yet.
--
-- Blizzard builds its party frames in its own handler for GROUP_ROSTER_UPDATE
-- -- the same event this addon watches -- and nothing orders the two. At
-- login ours runs first, finds no PartyMemberFrame1, and has nothing to hang
-- that row off. A pass on the next frame finds it.
local function scheduleRelayout()
    local delay = RELAYOUT_DELAYS[relayoutStep + 1]
    if relayoutQueued or not delay then
        return
    end
    if not (C_Timer and C_Timer.After) then
        return
    end

    relayoutQueued = true
    relayoutStep = relayoutStep + 1

    C_Timer.After(delay, function()
        relayoutQueued = false
        -- Laying out moves rows full of secure buttons, which is refused
        -- mid-fight. The next roster event or regen-enabled will come back
        -- to it; there is nothing worth queueing here.
        if not (InCombatLockdown and InCombatLockdown()) then
            Group.Layout()
        end
    end)
end

--- Hang each row off its unit's own Blizzard frame. Returns true if some
-- frame was missing and the layout is worth repeating.
local function layoutAttached()
    anchor.background:Hide()
    anchor:EnableMouse(false)

    local missing = false
    local y = 0

    for _, unit in ipairs(Group.Units()) do
        local row = rows[unit]
        local frame = ns.Anchors.For(unit)

        if row then
            row:ClearAllPoints()

            if frame then
                row:SetPoint(
                    "LEFT", frame, "RIGHT", ns.db.bar.attachX, ns.db.bar.attachY
                )
            else
                -- Not skipped. A row is given no point at all when it is
                -- built -- Layout is what places it -- and a frame with no
                -- points does not render, so skipping one here made it
                -- vanish rather than leave it where it was. It goes on the
                -- bar instead: somewhere visible beats nowhere, and
                -- RegisterUnitWatch keeps it hidden anyway unless the unit
                -- is really there.
                row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, y)
                y = y - (ns.Row.HEIGHT + ROW_GAP)
                missing = true
            end
        end
    end

    return missing
end

function Group.Layout()
    if not anchor then
        return
    end

    if ns.Row.Attached() then
        if layoutAttached() then
            scheduleRelayout()
        else
            -- Everything found its frame, so the next time one goes missing
            -- gets a full set of tries rather than the remains of this one.
            relayoutStep = 0
        end
        return
    end

    -- The backdrop and the drag handle only mean anything on our own bar, and
    -- the attached layout may have just put them away.
    anchor.background:Show()
    anchor:EnableMouse(true)

    local y = 0
    local placed = 0

    for _, unit in ipairs(Group.Units()) do
        local row = rows[unit]
        if row and ns.Row.Exists(unit) then
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
    -- Width from what the rows are showing, not from the slot maximum: the
    -- anchor is the visible backdrop as well as the drag handle, so sized to
    -- the maximum it would trail empty space past the last icon.
    anchor:SetSize(
        ns.Row.CurrentWidth(),
        rowCount * ns.Row.HEIGHT + (rowCount - 1) * ROW_GAP
    )
end

function Group.RefreshAll()
    for _, row in pairs(rows) do
        ns.Row.Refresh(row)
    end
end

--- Redraw every row's cooldown sweeps.
--
-- Every row, not the row that was clicked: a cooldown belongs to the player,
-- so one cast puts that spell on cooldown on all five rows at once. Updating
-- only the row that was clicked would leave the other four showing a spell
-- as ready that is not.
function Group.RefreshCooldowns()
    for _, row in pairs(rows) do
        ns.Row.RefreshCooldowns(row)
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
watcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
watcher:RegisterEvent("SPELLS_CHANGED")

watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "SPELLS_CHANGED" then
        -- Which buttons exist at all depends on what the player knows, so
        -- learning a spell changes the bar's shape -- and its width. ApplyAll
        -- is what redraws both, and holds it for combat to end if it has to.
        Group.ApplyAll()
        return
    end

    if event == "SPELL_UPDATE_COOLDOWN" then
        -- Carries no unit, and wants none: this is the one event here that
        -- is about the player's spells rather than about somebody's health.
        Group.RefreshCooldowns()
        return
    end

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
    -- A fresh set of retries: whatever prompted this apply -- a roster
    -- change, entering the world, a settings toggle -- is exactly the kind
    -- of thing that brings Blizzard's party frames into being.
    relayoutStep = 0
    -- This is the only place `pending` is ever cleared, so the reposition it
    -- was guarding belongs here too -- not just in runPending -- or whichever
    -- of ApplyAll's other callers (GROUP_ROSTER_UPDATE, a Slots.lua onChange,
    -- a Row.lua assignment) happens to be the one that clears a pending
    -- /hc reset or drag-stop discards it silently instead of performing it.
    repositionAnchor()
    Group.Layout()

    for _, row in pairs(rows) do
        ns.Row.ApplySpells(row)
    end

    -- A button whose spell just changed is showing the sweep of the spell it
    -- used to hold, and nothing else will correct that until the next time
    -- some cooldown happens to start. Drawing them here means a spell
    -- assigned mid-cooldown looks right the instant it lands.
    Group.RefreshCooldowns()

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

-- Layout settings live here rather than with the rest in Slots.lua because
-- this is the file that acts on them.
ns.RegisterSetting({
    store = "bar",
    key = "attached",
    type = "checkbox",
    name = "Sit beside the party frames",
    tooltip = "Hang the icons off Blizzard's own unit frames instead of putting them on a bar of their own. Falls back to the bar if your UI has no party frames -- raid-style party frames replace them, and so do most unit-frame addons.",
    onChange = function()
        if ns.Group then ns.Group.ApplyAll() end
    end,
})

ns.RegisterSetting({
    store = "bar",
    key = "attachX",
    type = "slider",
    name = "Distance from the frame",
    tooltip = "How far right of the unit frame the icons sit. Negative puts them on the left instead.",
    -- Wide enough to clear a party frame's buffs, and negative because the
    -- left of the frame is a perfectly good place to want them.
    min = -300,
    max = 300,
    step = 1,
    onChange = function()
        if ns.Group then ns.Group.ApplyAll() end
    end,
})

ns.RegisterSetting({
    store = "bar",
    key = "attachY",
    type = "slider",
    name = "Height against the frame",
    tooltip = "How far above the middle of the unit frame the icons sit. Negative puts them below it.",
    min = -100,
    max = 100,
    step = 1,
    onChange = function()
        if ns.Group then ns.Group.ApplyAll() end
    end,
})

--- Report what the attached layout actually found, per unit.
--
-- The layout depends entirely on frames this addon does not own and cannot
-- see from outside the game: whether PartyMemberFrame1 exists yet, whether
-- it has the health bar we prefer, and where a row ended up as a result.
-- None of that is visible on screen -- a row that found nothing looks
-- exactly like one that was never built.
local function frameLabel(frame)
    if not frame then
        return "NONE"
    end

    local name = frame.GetName and frame:GetName()
    return name or "unnamed"
end

ns.RegisterCommand("anchors", "Report which unit frames the icons found", function()
    ns.Print(string.format(
        "Attached: %s (setting %s, frames available %s)",
        tostring(ns.Row.Attached()),
        tostring(ns.db.bar.attached),
        tostring(ns.Anchors.Available())
    ))

    for _, unit in ipairs(Group.Units()) do
        local row = rows[unit]
        local point, relativeTo, _, x, y

        if row then
            point, relativeTo, _, x, y = row:GetPoint(1)
        end

        -- The path as well as the widget: which candidate name answered is
        -- the thing worth knowing when nothing does, since Blizzard has
        -- moved these frames between client versions.
        local _, path = ns.Anchors.Frame(unit)

        ns.Print(string.format(
            "%s: frame=%s anchor=%s exists=%s | row %s -> %s at %s,%s shown=%s",
            unit,
            path or "NONE",
            frameLabel(ns.Anchors.For(unit)),
            tostring(UnitExists and UnitExists(unit)),
            tostring(point),
            frameLabel(relativeTo),
            tostring(x),
            tostring(y),
            row and tostring(row:IsShown()) or "no row"
        ))
    end
end)
