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

local function slotSet(groups)
    local set = {}
    for _, group in ipairs(groups) do
        for _, slot in ipairs(group.slots) do
            set[slot] = true
        end
    end
    return set
end

--- Say what changed, spell by spell. A slot still outdated afterwards is
-- named rather than counted: a placing the client ignored is not done.
local function report(before, after)
    local left = slotSet(after)

    for _, group in ipairs(before) do
        local done = 0
        for _, slot in ipairs(group.slots) do
            if left[slot] then
                ns.Print(string.format("could not upgrade %s on action slot %d", group.name, slot))
            else
                done = done + 1
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
            PlaceAction(slot)
            -- Placing hands back the old rank on the cursor; this drops it.
            ClearCursor()
        end
    end

    report(groups, ns.Ranks.Outdated())
    return true
end
