local addonName, ns = ...

-- Bank counts in item tooltips: how many of the item this character's saved
-- bank holds, then each other character's on this realm, by name. Added
-- through the client's tooltip post-call, which runs addon code apart from
-- Blizzard's, on the main tooltip and a linked item's; the comparison
-- tooltips beside them are left alone.

ns.AddDefaults({
    tooltipCounts = true,
})

-- BankBags' teal, for the labels; the counts are white.
local LABEL_R, LABEL_G, LABEL_B = 0.31, 0.82, 0.77

local function addCounts(tooltip, data)
    if not (ns.db and ns.db.tooltipCounts) then
        return
    end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
        return
    end
    local itemID = data and data.id
    if not itemID then
        return
    end

    local added = false
    local function add(label, count)
        if count and count > 0 then
            tooltip:AddDoubleLine(label, count, LABEL_R, LABEL_G, LABEL_B, 1, 1, 1)
            added = true
        end
    end
    add("Bank", ns.Bank.Counts(ns.Bank.CharacterKey()).byID[itemID])
    for _, other in ipairs(ns.Bank.Others()) do
        add(other.name .. "'s bank", ns.Bank.Counts(other.key).byID[itemID])
    end
    if added and tooltip.Show then
        tooltip:Show() -- to fit the lines just added
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
    and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, addCounts)
end
