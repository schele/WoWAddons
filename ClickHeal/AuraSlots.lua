local addonName, ns = ...

-- Buff timers the game draws. In combat 1.60.1 refuses ClickHeal every aura
-- read ("Auras cannot be accessed when secret while tainted by 'ClickHeal'"),
-- by index and by instance ID alike, so the numbers ClickHeal worked out
-- itself went blank the moment a fight began. Blizzard's aura container is a
-- frame an addon may create and the game fills from its own protected code,
-- which may read secret auras: one per row, on the row's unit, with two slots
-- under every button that the game shows, hides and counts down. See
-- docs/superpowers/specs/2026-09-27-clickheal-combat-timers-design.md.
--
-- The same container blinks a cure. Each button has a third slot, over its
-- icon, matching debuffs of the types the button's spell removes: a Remove
-- Curse button blinks while its row's person carries a curse. The game shows
-- that slot and plays its blink, so it works in combat, when ClickHeal
-- itself cannot see a single debuff.

local AuraSlots = {}
ns.AuraSlots = AuraSlots

-- Spell IDs seen on buffs out of combat, by the buff's name: other ranks,
-- and other casters' copies, that the spellbook knows nothing about. Kept
-- for the session only. Filled by AuraSlots.Learn.
local learned = {}

-- Every row the game draws, so an ID learned on one reaches them all.
local attached = {}

-- Names whose learned IDs have not reached the slots yet: filters are
-- changed out of combat only.
local pending = {}

--- What a slot takes: the buff's spell IDs, and whose cast.
local function filtersFor(ids, own)
    return { includeSpellIDs = ids, isFromPlayerOrPlayerPet = own }
end

--- Every spell ID `spell` is known by, as the map a slot's filter wants:
-- the spellbook's, and any learned. Nil when there are none, and then the
-- button's slots are switched off rather than left to match every buff.
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

--- Point a button's two slots at its spell's IDs, or switch them off.
-- Guarded: a refusal here costs this button its number, never the caller
-- -- Row.ApplySpells, which the whole bar goes through.
local function applyFilters(row, slots)
    ns.Guarded(function()
        local ids = idsFor(slots.spell)
        for _, slot in ipairs({ slots.own, slots.other }) do
            if ids then
                row.auraContainer:SetAuraSlotCandidateFilters(slot.key, filtersFor(ids, slot == slots.own))
            end
            row.auraContainer:SetAuraSlotEnabled(slot.key, ids ~= nil)
        end
    end)
end

--- One slot under `button`: yours (white, drawn on top) or
-- anyone else's (grey). Everything its frame needs is done in
-- initializeFrame, which the game runs on the new frame before it locks the
-- frame down. The label has to be that frame's own: SetDurationText refuses
-- any other ("must be the owner or a direct or indirect descendant of
-- owner"). The client runs initializeFrame through securecallfunction, so a
-- refusal in it never reaches this code; `ready` is how it is noticed.
local function addSlot(container, button, key, own)
    local slot = { key = key }

    local function initializeFrame(frame)
        -- Blizzard's aura button takes the mouse, and in the stacked bar
        -- this box sits over the top of the icon on the row below: a click
        -- there would land on the timer and cast nothing. On its own guard,
        -- so a refusal costs the click-through and not the number.
        pcall(frame.EnableMouse, frame, false)
        frame:SetSize(ns.Row.TIMER_WIDTH, ns.Row.TIMER_HEIGHT)
        frame:SetPoint("TOP", button, "BOTTOM", 0, -3)
        frame:SetFrameLevel(container:GetFrameLevel() + (own and 2 or 1))

        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetSize(ns.Row.TIMER_WIDTH, ns.Row.TIMER_HEIGHT)
        label:SetPoint("CENTER", frame, "CENTER")
        if own then
            label:SetTextColor(1, 1, 1)
        else
            label:SetTextColor(ns.Row.OTHERS_DIM, ns.Row.OTHERS_DIM, ns.Row.OTHERS_DIM)
        end
        slot.label = label

        -- No formatter of ours: the game's default is the one its own aura
        -- frames use -- seconds cut, seconds up to 90, minutes rounded up --
        -- and matches its buff icons. Ours rounded seconds up and read a
        -- second ahead of them.
        frame:SetDurationText(label)
        slot.ready = true
    end

    -- An empty map matches nothing, so the slot shows nothing until
    -- SetSpell gives it a spell; switched off as well, for good measure.
    slot.frame = container:AddAuraSlot(key, "HELPFUL", {
        candidateFilters = filtersFor({}, own),
        initializeFrame = initializeFrame,
    })
    if not slot.ready then
        error("slot " .. key .. " was not set up", 0)
    end
    container:SetAuraSlotEnabled(key, false)

    return slot
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
-- Set up in initializeFrame, like the timers' slots, and for the same
-- reason. Only the frame and its textures are needed for the slot to be of
-- use; the blink and the colour are each on a guard of their own, so a
-- refusal of either leaves a steady white frame rather than nothing.
local function addDispelSlot(container, button, key)
    local slot = { key = key }

    local function initializeFrame(frame)
        pcall(frame.EnableMouse, frame, false)
        frame:SetAllPoints(button)
        -- Over the icon and its cooldown sweep, and the timers' slots too.
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
-- row its blinking and nothing else, since the timers on the same
-- container are already built. Whatever was built before the refusal is
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

--- Give `row` a container on its unit, two slots under every button and a
-- dispel slot over each. True if the game will draw this row's timers.
-- False on a client without the container, or if the game refuses any step
-- of the timers -- and then the row keeps ClickHeal's own timers, with
-- nothing half-built left on screen, and blinks nothing. Called once per
-- row, from Row.Create, out of combat.
function AuraSlots.Attach(row)
    local container
    local built = pcall(function()
        container = CreateFrame("AuraContainer", nil, row, "CustomAuraContainerTemplate")
        -- The row's place, as the probe's container had one: a frame with no
        -- points is not drawn, and the slots hang off this one.
        container:SetAllPoints(row)
        container:SetUnit(row.unit)

        local slots = {}
        for index, button in ipairs(row.buttons) do
            slots[index] = {
                own = addSlot(container, button, "own" .. index, true),
                other = addSlot(container, button, "other" .. index, false),
            }
        end
        row.auraSlots = slots
    end)

    if not built then
        if container then
            pcall(container.Hide, container)
        end
        row.auraContainer, row.auraSlots = nil, nil
        return false
    end

    row.auraContainer = container
    attached[#attached + 1] = row
    attachDispels(row)
    return true
end

--- Whether the game draws this row's timers, rather than ClickHeal.
function AuraSlots.Drawn(row)
    return row.auraContainer ~= nil
end

--- Have the game read this row's unit afresh. The container re-reads a
-- unit only when one of its auras changes, and after a roster change the
-- same token can mean somebody else: without this, a row could go on
-- showing the last person's buffs. Only marks the container for an update,
-- which Blizzard exposes for exactly this ("external events ... e.g. target
-- changes"), so it is safe in combat; guarded all the same.
function AuraSlots.Refresh(row)
    if row.auraContainer then
        ns.Guarded(function()
            row.auraContainer:UpdateAllAuras()
        end)
    end
end

--- Point the slots of button `index` at `spell`, or at nothing: the timers
-- under it at the spell's buff, the dispel slot over it at the debuffs it
-- removes. Out of combat only, like every other change to a button:
-- Row.ApplySpells calls it for every button, every time.
function AuraSlots.SetSpell(row, index, spell)
    local slots = row.auraSlots and row.auraSlots[index]
    if slots then
        slots.spell = spell
        applyFilters(row, slots)
    end

    local dispel = row.dispelSlots and row.dispelSlots[index]
    if dispel then
        applyDispel(row, dispel, spell)
    end
end

--- Take the ID of every rank the spellbook holds -- Spells.Ranks(), by
-- name -- so a slot matches the rank a button casts on someone too low for
-- the top one, and anybody's lower rank, from the first cast. Learned like
-- an ID seen on a buff, but without reaching for the slots: Row.ApplySpells
-- calls this just before it points every slot of its row anew.
function AuraSlots.LearnRanks(ranks)
    for name, list in pairs(ranks or {}) do
        learned[name] = learned[name] or {}
        for _, rank in ipairs(list) do
            learned[name][rank.id] = true
        end
    end
end

--- Take spell IDs from buffs read out of combat -- Spells.HelpfulAuras'
-- table, by name, each with its spellId -- and widen the slots of every
-- button holding that name, on every row. In combat the IDs wait for it to
-- end: slot filters are only changed out of combat. On 1.60.1 nothing can
-- be read in combat anyway, so what waits is only what a test stages.
function AuraSlots.Learn(auras)
    for name, aura in pairs(auras or {}) do
        local id = aura.spellId
        if type(id) == "number" then
            learned[name] = learned[name] or {}
            if not learned[name][id] then
                learned[name][id] = true
                pending[name] = true
            end
        end
    end

    if next(pending) == nil or (InCombatLockdown and InCombatLockdown()) then
        return
    end

    for _, row in ipairs(attached) do
        for _, slots in pairs(row.auraSlots) do
            if slots.spell and pending[slots.spell] then
                applyFilters(row, slots)
            end
        end
    end
    pending = {}
end
