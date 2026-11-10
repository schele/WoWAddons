local addonName, ns = ...

-- Buff timers the game draws. In combat 1.60.1 refuses ClickHeal every aura
-- read ("Auras cannot be accessed when secret while tainted by 'ClickHeal'"),
-- by index and by instance ID alike, so the numbers ClickHeal worked out
-- itself went blank the moment a fight began. Blizzard's aura container is a
-- frame an addon may create and the game fills from its own protected code,
-- which may read secret auras. See
-- docs/superpowers/specs/2026-09-27-clickheal-combat-timers-design.md.
--
-- Every button has containers of its own, on the row's unit, each holding
-- two groups of numbers: your copies of the button's buff, and anyone
-- else's. A buff can be on someone twice -- two druids' Rejuvenations, or
-- two of your own -- and a slot, which is what the timers were first, shows
-- one aura only, so the second copy had no number. A group shows each copy
-- on a frame of its own and the game lays them out: upward from just under
-- the icon, so one copy's number stays where it always was and a second
-- goes above the icon. Yours come first. A container lays out everything in
-- it as one run, which is why each button needs its own.
--
-- Two of them, alike but for colour, because the number over the icon is
-- green. The game hands a group's frames out from a pool and keeps a frame
-- with its aura, so the frame over the icon now is the one under it once
-- the lower copy runs out: a colour given frame by frame would move with
-- it. Instead each container sits in a box cut off at the icon's middle.
-- Both lay the same numbers out in the same places; the lower box lets
-- through only the white number under the icon, the upper box only the
-- green one over it.
--
-- The row has a container as well, which blinks a cure. Each button has a
-- slot there, over its icon, matching debuffs of the types the button's
-- spell removes: a Remove Curse button blinks while its row's person
-- carries a curse. The game shows that slot and plays its blink, so it
-- works in combat, when ClickHeal itself cannot see a single debuff.

local AuraSlots = {}
ns.AuraSlots = AuraSlots

-- Spell IDs seen on buffs out of combat, by the buff's name: other ranks,
-- and other casters' copies, that the spellbook knows nothing about. Kept
-- for the session only. Filled by AuraSlots.Learn.
local learned = {}

-- Every row the game draws, so an ID learned on one reaches them all.
local attached = {}

-- Names whose learned IDs have not reached the numbers yet: filters are
-- changed out of combat only.
local pending = {}

--- What a group takes: the buff's spell IDs, and whose cast.
local function filtersFor(ids, own)
    return { includeSpellIDs = ids, isFromPlayerOrPlayerPet = own }
end

-- How many copies of a buff each group numbers: under the icon and over it.
-- Yours and anyone else's are counted apart, so a third copy on one person
-- -- two druids' and a double of your own -- climbs on above the second
-- rather than going unnumbered. Rare enough to leave at that.
local COPIES = 2

--- Where the game puts a group's numbers, one above the other: as tall as
-- the timer's box, with room between them for the icon and a gap either
-- side of it. Follows the icon's size, which is a setting.
local function layoutFor(iconHeight)
    return {
        elementWidth = ns.Row.TIMER_WIDTH,
        elementHeight = ns.Row.TIMER_HEIGHT,
        elementSpacing = iconHeight + ns.Row.TIMER_GAP * 2,
    }
end

--- The height of the icons the numbers go under and over: the setting
-- Row.ApplySpells sizes every button by. Not the button's own GetHeight,
-- which the game answers with a secret number once these containers hang
-- off the button; a sum on that raised, and took every ApplySpells after
-- login down with it.
local function iconHeight()
    return ns.Row.ButtonSize()
end

--- Every spell ID `spell` is known by, as the map a group's filter wants:
-- the spellbook's, and any learned. Nil when there are none, and then the
-- button's numbers are switched off rather than left to match every buff.
local function idsFor(spell)
    if not spell then
        return nil
    end

    local ids, any = {}, false
    local fromBook = ns.Spells.SpellID(spell)
    if fromBook then
        ids[fromBook] = true
        any = true
    end
    for id in pairs(learned[spell] or {}) do
        ids[id] = true
        any = true
    end

    return any and ids or nil
end

--- Point both of a button's containers, and both groups in each, at its
-- spell's IDs, or switch them off. Guarded: a refusal here costs this
-- button its numbers, never the caller -- Row.ApplySpells, which the whole
-- bar goes through.
local function applyFilters(timers)
    ns.Guarded(function()
        local ids = idsFor(timers.spell)
        for _, set in ipairs({ timers.under, timers.over }) do
            for _, group in ipairs({ set.own, set.other }) do
                if ids then
                    set.container:SetAuraGroupCandidateFilters(group.key, filtersFor(ids, group == set.own))
                end
                set.container:SetAuraGroupEnabled(group.key, ids ~= nil)
            end
        end
    end)
end

--- Keep the number over the icon clear of it after the icon is resized.
-- Out of combat only, as every change to a button is; guarded like the
-- filters, and left alone when the size has not moved.
local function applyLayout(timers)
    local height = iconHeight()
    if height == timers.iconHeight then
        return
    end

    ns.Guarded(function()
        for _, set in ipairs({ timers.under, timers.over }) do
            for _, group in ipairs({ set.own, set.other }) do
                set.container:SetAuraGroupLayout(group.key, layoutFor(height))
            end
        end
        timers.iconHeight = height
    end)
end

--- One group of numbers in a button's container: your copies of its buff
-- or anyone else's, coloured for the place its box lets it show: white or
-- grey under the icon, green over it (Row.TimerColour). The game makes the
-- group's frames as it is added, and later as more are wanted, and runs
-- initializeFrame on each before it locks the frame down; everything a
-- frame needs is done there. The label has to be that frame's own:
-- SetDurationText refuses any other ("must be the owner or a direct or
-- indirect descendant of owner"). The client runs initializeFrame through
-- securecallfunction, so a refusal in it never reaches this code; `ready`
-- is how it is noticed.
local function addGroup(container, key, own, over, height)
    local group = { key = key }

    local function initializeFrame(frame)
        -- Blizzard's aura button takes the mouse, and in the stacked bar
        -- the box under an icon sits over the top of the icon on the row
        -- below, and the box over it over the row above: a click there
        -- would land on the timer and cast nothing. On its own guard, so a
        -- refusal costs the click-through and not the number.
        pcall(frame.EnableMouse, frame, false)
        frame:SetSize(ns.Row.TIMER_WIDTH, ns.Row.TIMER_HEIGHT)
        frame:SetFrameLevel(container:GetFrameLevel() + (own and 2 or 1))

        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetSize(ns.Row.TIMER_WIDTH, ns.Row.TIMER_HEIGHT)
        label:SetPoint("CENTER", frame, "CENTER")
        label:SetTextColor(ns.Row.TimerColour(over, not own))

        -- No formatter of ours: the game's default is the one its own aura
        -- frames use -- seconds cut, seconds up to 90, minutes rounded up --
        -- and matches its buff icons. Ours rounded seconds up and read a
        -- second ahead of them.
        frame:SetDurationText(label)
        group.ready = true
    end

    -- An empty map matches nothing, so the group shows nothing until
    -- SetSpell gives it a spell; switched off as well, for good measure.
    container:AddAuraGroup(key, "HELPFUL", {
        maxFrameCount = COPIES,
        candidateFilters = filtersFor({}, own),
        initializeFrame = initializeFrame,
        layout = layoutFor(height),
    })
    -- Off before the check below, so a group that was not set up is not
    -- left switched on behind the refusal.
    container:SetAuraGroupEnabled(key, false)
    if not group.ready then
        error("group " .. key .. " was not set up", 0)
    end

    return group
end

-- How far each box reaches from the middle of its icon: past every number
-- it lets through, at the biggest icon there is.
local CLIP_REACH = 400

--- One of `button`'s two sets of numbers, `over` for the one over the icon:
-- a box cut off at the icon's middle, below it or above, and a container
-- in the box with its two groups.
--
-- The container hangs by its bottom edge from just under the button, where
-- the timer's box always was, and the game stacks the numbers in it upward:
-- the first in that box, the next above the icon. The game sizes it as it
-- lays them out, so it is given one point and the size of one number to
-- start from. The flow layout is the container's, set before any group is
-- added. `track` takes every frame made, so a refusal can put them away.
local function addSet(row, button, over, height, track)
    local clip = track(CreateFrame("Frame", nil, row))
    clip:SetClipsChildren(true)
    clip:SetSize(ns.Row.TIMER_WIDTH, CLIP_REACH)
    clip:SetPoint(over and "BOTTOM" or "TOP", button, "CENTER", 0, 0)

    local container = track(CreateFrame("AuraContainer", nil, clip, "CustomAuraContainerTemplate"))
    container:SetPoint("BOTTOM", button, "BOTTOM", 0, -(ns.Row.TIMER_GAP + ns.Row.TIMER_HEIGHT))
    container:SetSize(ns.Row.TIMER_WIDTH, ns.Row.TIMER_HEIGHT)
    container:SetUnit(row.unit)
    container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Vertical)
    container:SetFlowLayoutAnchorPoint("BOTTOM")
    container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)

    return {
        clip = clip,
        container = container,
        -- Added in this order, and laid out in it: yours take the place
        -- under the icon.
        own = addGroup(container, "own", true, over, height),
        other = addGroup(container, "other", false, over, height),
    }
end

--- Both sets of numbers for `button`.
local function addTimers(row, button, track)
    local height = iconHeight()
    return {
        iconHeight = height,
        under = addSet(row, button, false, height, track),
        over = addSet(row, button, true, height, track),
    }
end

-- The blink: the frame fades to BLINK_LOW and back, each way taking
-- BLINK_SECONDS. The wash brightens the icon under it, white and additive
-- so it shows over any icon's colours; the edges take the game's colour for
-- the debuff's type, purple for a curse, which says which cure is wanted
-- when Cleanse and its like answer to more than one.
local BLINK_LOW = 0.15
local BLINK_SECONDS = 0.4
local WASH_ALPHA = 0.45

--- The slot over `button` that blinks while its spell has a debuff to remove.
-- Set up in initializeFrame, like the timers' frames, and for the same
-- reason. Only the frame and its textures are needed for the slot to be of
-- use; the blink and the colour are each on a guard of their own, so a
-- refusal of either leaves a steady white frame rather than nothing.
local function addDispelSlot(container, button, key)
    local slot = { key = key }

    local function initializeFrame(frame)
        pcall(frame.EnableMouse, frame, false)
        frame:SetAllPoints(button)
        -- Over the icon and its cooldown sweep.
        frame:SetFrameLevel(container:GetFrameLevel() + 3)

        local wash = frame:CreateTexture(nil, "OVERLAY")
        wash:SetAllPoints(frame)
        wash:SetColorTexture(1, 1, 1, WASH_ALPHA)
        wash:SetBlendMode("ADD")

        local edges = {}
        for _, side in ipairs(ns.Row.HOVER_SIDES) do
            local edge = frame:CreateTexture(nil, "OVERLAY")
            edge:SetColorTexture(1, 1, 1, 1)
            edge:SetPoint(side[1], frame, side[1])
            edge:SetPoint(side[2], frame, side[2])
            if side.across then
                edge:SetHeight(ns.Row.HOVER_BORDER)
            else
                edge:SetWidth(ns.Row.HOVER_BORDER)
            end
            edges[#edges + 1] = edge
        end
        slot.ready = true

        pcall(function()
            local style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
            for _, edge in ipairs(edges) do
                frame:AddDispelTypeTexture(edge, { style = style })
            end
        end)

        -- BOUNCE runs out and back for as long as the game lets it play,
        -- which is for as long as the debuff is there.
        pcall(function()
            local blink = frame:CreateAnimationGroup()
            blink:SetLooping("BOUNCE")
            local fade = blink:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(BLINK_LOW)
            fade:SetDuration(BLINK_SECONDS)
            frame:AddAuraShownAnimation(blink)
        end)
    end

    -- Matches nothing, and switched off, until SetSpell gives it a cure.
    slot.frame = container:AddAuraSlot(key, "HARMFUL", {
        candidateFilters = { includeDispelTypes = {} },
        initializeFrame = initializeFrame,
    })
    -- Off before the check below, so a slot that was not set up is not
    -- left switched on behind the refusal.
    container:SetAuraSlotEnabled(key, false)
    if not slot.ready then
        error("slot " .. key .. " was not set up", 0)
    end

    return slot
end

--- A dispel slot over every button of `row`, or none: a refusal costs the
-- row its blinking and nothing else, since the timers are already built,
-- in containers of their own. Whatever was built before the refusal is
-- switched off, so it can never blink.
local function attachDispels(row)
    local slots = {}
    local built = pcall(function()
        for index, button in ipairs(row.buttons) do
            slots[index] = addDispelSlot(row.auraContainer, button, "dispel" .. index)
        end
    end)

    if built then
        row.dispelSlots = slots
        return
    end

    for _, slot in pairs(slots) do
        pcall(row.auraContainer.SetAuraSlotEnabled, row.auraContainer, slot.key, false)
    end
    row.dispelSlots = nil
end

--- Point a button's dispel slot at the debuff types its spell removes, or
-- switch it off for a spell that removes none.
local function applyDispel(row, slot, spell)
    ns.Guarded(function()
        local types = ns.Spells.DispelTypes(spell)
        if types then
            row.auraContainer:SetAuraSlotCandidateFilters(slot.key, { includeDispelTypes = types })
        end
        row.auraContainer:SetAuraSlotEnabled(slot.key, types ~= nil)
    end)
end

--- Give `row` a container on its unit for the dispel slots, and every
-- button two containers of its own for its numbers. True if the game will
-- draw this row's timers. False on a client without the container, or if
-- the game refuses any step of the timers -- and then the row keeps
-- ClickHeal's own timers, with nothing half-built left on screen, and blinks
-- nothing. Called once per row, from Row.Create, out of combat.
function AuraSlots.Attach(row)
    local made = {}
    local function track(frame)
        made[#made + 1] = frame
        return frame
    end

    local container, timers
    local built = pcall(function()
        container = track(CreateFrame("AuraContainer", nil, row, "CustomAuraContainerTemplate"))
        -- The row's place, as the probe's container had one: a frame with no
        -- points is not drawn, and the dispel slots hang off this one.
        container:SetAllPoints(row)
        container:SetUnit(row.unit)

        timers = {}
        for index, button in ipairs(row.buttons) do
            timers[index] = addTimers(row, button, track)
        end
    end)

    if not built then
        for _, frame in ipairs(made) do
            pcall(frame.Hide, frame)
        end
        row.auraContainer, row.auraTimers = nil, nil
        return false
    end

    row.auraContainer = container
    row.auraTimers = timers
    attached[#attached + 1] = row
    attachDispels(row)
    return true
end

--- Whether the game draws this row's timers, rather than ClickHeal.
function AuraSlots.Drawn(row)
    return row.auraTimers ~= nil
end

--- Have the game read this row's unit afresh, in every container. A
-- container re-reads a unit only when one of its auras changes, and after a
-- roster change the same token can mean somebody else: without this, a row
-- could go on showing the last person's buffs. Only marks the containers for
-- an update, which Blizzard exposes for exactly this ("external events ...
-- e.g. target changes"), so it is safe in combat; guarded all the same.
function AuraSlots.Refresh(row)
    if row.auraContainer then
        ns.Guarded(function()
            row.auraContainer:UpdateAllAuras()
        end)
    end

    for _, timers in ipairs(row.auraTimers or {}) do
        for _, set in ipairs({ timers.under, timers.over }) do
            ns.Guarded(function()
                set.container:UpdateAllAuras()
            end)
        end
    end
end

--- Point the numbers of button `index` at `spell`, or at nothing, and the
-- dispel slot over it at the debuffs the spell removes. Out of combat only,
-- like every other change to a button: Row.ApplySpells calls it for every
-- button, every time, after sizing the button.
function AuraSlots.SetSpell(row, index, spell)
    local timers = row.auraTimers and row.auraTimers[index]
    if timers then
        timers.spell = spell
        applyLayout(timers)
        applyFilters(timers)
    end

    local dispel = row.dispelSlots and row.dispelSlots[index]
    if dispel then
        applyDispel(row, dispel, spell)
    end
end

--- Take the ID of every rank the spellbook holds -- Spells.Ranks(), by
-- name -- so a button's numbers match the rank it casts on someone too low
-- for the top one, and anybody's lower rank, from the first cast. Learned
-- like an ID seen on a buff, but without reaching for the groups:
-- Row.ApplySpells calls this just before it points every button anew.
function AuraSlots.LearnRanks(ranks)
    for name, list in pairs(ranks or {}) do
        learned[name] = learned[name] or {}
        for _, rank in ipairs(list) do
            learned[name][rank.id] = true
        end
    end
end

--- Take spell IDs from buffs read out of combat -- Spells.HelpfulAuras'
-- table, by name, with the spellId of every copy -- and widen the numbers
-- of every button holding that name, on every row. Every copy, because a
-- second one is exactly when the number over the icon shows, and it can be
-- another rank. In combat the IDs wait for it to end: filters are only
-- changed out of combat. On 1.60.1 nothing can be read in combat anyway, so
-- what waits is only what a test stages.
function AuraSlots.Learn(auras)
    for name, aura in pairs(auras or {}) do
        for _, copy in ipairs(aura.copies or { aura }) do
            local id = copy.spellId
            if type(id) == "number" then
                learned[name] = learned[name] or {}
                if not learned[name][id] then
                    learned[name][id] = true
                    pending[name] = true
                end
            end
        end
    end

    if next(pending) == nil or (InCombatLockdown and InCombatLockdown()) then
        return
    end

    for _, row in ipairs(attached) do
        for _, timers in ipairs(row.auraTimers) do
            if timers.spell and pending[timers.spell] then
                applyFilters(timers)
            end
        end
    end
    pending = {}
end
