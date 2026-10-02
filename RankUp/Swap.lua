local addonName, ns = ...

-- Putting the highest rank on a button: picked up and placed, as a drag
-- from the spellbook does. The client refuses placing in combat, so this
-- never tries.

local Swap = {}
ns.Swap = Swap

local function pickup(spellID)
    if C_Spell and C_Spell.PickupSpell then
        C_Spell.PickupSpell(spellID)
    elseif PickupSpell then
        PickupSpell(spellID)
    end
end

--- Whether the cursor holds `spellID`. Placing with nothing on it would
-- empty the button and throw the old rank away. A client that names no
-- spell ID for the cursor is taken at its word that it holds a spell.
local function holding(spellID)
    return ns.Guarded(function()
        local kind, _, _, id = GetCursorInfo()
        return kind == "spell" and (type(id) ~= "number" or id == spellID)
    end, false)
end

local function slotHolds(slot, spellID)
    return ns.Guarded(function()
        local kind, id = GetActionInfo(slot)
        return kind == "spell" and id == spellID
    end, false)
end

--- Say what changed, spell by spell. Only a slot that now holds the new
-- rank counts as done; any other is named, since a placing the client
-- ignored, or one that left the slot empty, is not an upgrade.
local function report(groups)
    for _, group in ipairs(groups) do
        local done = 0
        for _, slot in ipairs(group.slots) do
            if slotHolds(slot, group.toID) then
                done = done + 1
            else
                ns.Print(string.format("could not upgrade %s on action slot %d", group.name, slot))
            end
        end

        if done > 0 then
            ns.Print(string.format("%s -> %s (%s)", group.name, group.toRank or "highest rank", ns.Buttons(done)))
        end
    end
end

--- Put the highest rank on every outdated button. From a fresh look, not
-- the list the popup showed: a button may have changed since. False when
-- combat stopped it, before or partway; what is left waits for the fight
-- to end.
function Swap.Run()
    if InCombatLockdown() then
        return false
    end

    local groups = ns.Ranks.Outdated()

    for _, group in ipairs(groups) do
        for _, slot in ipairs(group.slots) do
            if InCombatLockdown() then
                return false
            end
            ClearCursor()
            pickup(group.toID)
            if holding(group.toID) then
                PlaceAction(slot)
            end
            -- Placing hands back the old rank on the cursor; this drops it.
            ClearCursor()
        end
    end

    report(groups)
    return true
end
