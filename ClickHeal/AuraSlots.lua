local addonName, ns = ...

-- Buff timers the game draws. In combat 1.60.1 refuses ClickHeal every aura
-- read ("Auras cannot be accessed when secret while tainted by 'ClickHeal'"),
-- by index and by instance ID alike, so the numbers ClickHeal worked out
-- itself went blank the moment a fight began. Blizzard's aura container is a
-- frame an addon may create and the game fills from its own protected code,
-- which may read secret auras: one per row, on the row's unit, with two slots
-- under every button that the game shows, hides and counts down. See
-- docs/superpowers/specs/2026-09-27-clickheal-combat-timers-design.md.

local AuraSlots = {}
ns.AuraSlots = AuraSlots

-- The dark plate behind your own number. It covers someone else's copy of
-- the same buff, drawn underneath -- two druids' Rejuvenations stack -- and
-- reads better over bright ground.
local PLATE_WIDTH = 26
local PLATE_HEIGHT = 13
local PLATE_ALPHA = 0.85

--- What a slot takes: the buff's spell IDs, and whose cast.
local function filtersFor(ids, own)
    return { includeSpellIDs = ids, isFromPlayerOrPlayerPet = own }
end

--- One slot under `button`: yours (white on the plate, drawn on top) or
-- anyone else's (grey). Everything its frame needs is done in
-- initializeFrame, which the game runs on the new frame before it locks the
-- frame down. The label has to be that frame's own: SetDurationText refuses
-- any other ("must be the owner or a direct or indirect descendant of
-- owner"). The client runs initializeFrame through securecallfunction, so a
-- refusal in it never reaches this code; `ready` is how it is noticed.
local function addSlot(container, button, key, own)
    local slot = { key = key }

    local function initializeFrame(frame)
        frame:SetSize(ns.Row.TIMER_WIDTH, ns.Row.TIMER_HEIGHT)
        frame:SetPoint("TOP", button, "BOTTOM", 0, -3)
        frame:SetFrameLevel(container:GetFrameLevel() + (own and 2 or 1))

        if own then
            local plate = frame:CreateTexture(nil, "BACKGROUND")
            plate:SetColorTexture(0, 0, 0, PLATE_ALPHA)
            plate:SetSize(PLATE_WIDTH, PLATE_HEIGHT)
            plate:SetPoint("CENTER", frame, "CENTER")
            slot.plate = plate
        end

        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetSize(ns.Row.TIMER_WIDTH, ns.Row.TIMER_HEIGHT)
        label:SetPoint("CENTER", frame, "CENTER")
        if own then
            label:SetTextColor(1, 1, 1)
        else
            label:SetTextColor(ns.Row.OTHERS_DIM, ns.Row.OTHERS_DIM, ns.Row.OTHERS_DIM)
        end
        slot.label = label

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

--- Give `row` a container on its unit and two slots under every button.
-- True if the game will draw this row's timers. False on a client without
-- the container, or if the game refuses any step -- and then the row keeps
-- ClickHeal's own timers, with nothing half-built left on screen. Called
-- once per row, from Row.Create, out of combat.
function AuraSlots.Attach(row)
    local container
    local built = pcall(function()
        container = CreateFrame("AuraContainer", nil, row, "CustomAuraContainerTemplate")
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
    return true
end

--- Whether the game draws this row's timers, rather than ClickHeal.
function AuraSlots.Drawn(row)
    return row.auraContainer ~= nil
end
