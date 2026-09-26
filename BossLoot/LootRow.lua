local addonName, ns = ...

-- One row of the loot column: an item's icon, its name in its quality colour,
-- a grey line under it, and the drop chance on the right. It behaves like an
-- item anywhere else in the game: hover for the tooltip, shift-click to link,
-- ctrl-click to preview.

local LootRow = {}
ns.LootRow = LootRow

LootRow.HEIGHT = 30

local ICON_SIZE = 26
local CHANCE_WIDTH = 48
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--- What the client knows about an item, or nil if it has not loaded it yet.
function LootRow.ItemInfo(itemID)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get then
        return nil
    end

    local name, link, quality, _, _, itemType, itemSubType, _, equipLoc, icon = get(itemID)
    if not name then
        return nil
    end

    return {
        name = name, link = link, quality = quality, itemType = itemType,
        itemSubType = itemSubType, equipLoc = equipLoc, icon = icon,
    }
end

--- Ask the client to load an item. GET_ITEM_INFO_RECEIVED says when it has.
function LootRow.RequestLoad(itemID)
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    elseif GetItemInfo then
        -- Older clients start loading on any lookup.
        GetItemInfo(itemID)
    end
end

-- The icon lookup by ID works before the item itself has loaded, so even a
-- placeholder row shows the right picture.
local function iconFor(itemID, info)
    if info and info.icon then
        return info.icon
    end
    if C_Item and C_Item.GetItemIconByID then
        local icon = C_Item.GetItemIconByID(itemID)
        if icon then
            return icon
        end
    end
    return UNKNOWN_ICON
end

local function showTooltip(row)
    if not (row.entry and GameTooltip) then
        return
    end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(row.entry.id)
    else
        GameTooltip:SetHyperlink("item:" .. row.entry.id)
    end
    GameTooltip:Show()
end

local function hideTooltip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

-- Shift-click links in chat, ctrl-click opens the dressing room: the game's
-- own handler does both, the same as for an item in your bags.
local function click(row)
    if row.link and HandleModifiedItemClick then
        HandleModifiedItemClick(row.link)
    end
end

function LootRow.Create(list)
    local row = CreateFrame("Button", nil, list)
    row:SetSize(list.options.width, LootRow.HEIGHT)
    row:RegisterForClicks("LeftButtonUp")

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -CHANCE_WIDTH, 0)
    row.name:SetJustifyH("LEFT")

    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 0)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -CHANCE_WIDTH, 0)
    row.detail:SetJustifyH("LEFT")

    row.chance = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.chance:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.chance:SetJustifyH("RIGHT")

    row:SetScript("OnEnter", showTooltip)
    row:SetScript("OnLeave", hideTooltip)
    row:SetScript("OnClick", click)

    return row
end

function LootRow.Render(row, entry)
    row.entry = entry
    local info = LootRow.ItemInfo(entry.id)

    row.icon:SetTexture(iconFor(entry.id, info))

    if info then
        row.name:SetText(ns.Format.Colored(info.name, info.quality))
        row.link = info.link
    else
        row.name:SetText("|cff808080Loading item " .. entry.id .. "...|r")
        row.link = nil
        LootRow.RequestLoad(entry.id)
    end

    if entry.sources then
        row.detail:SetText(table.concat(entry.sources, ", "))
    elseif info then
        row.detail:SetText(ns.Format.TypeLabel(info.itemType, info.itemSubType, info.equipLoc))
    else
        row.detail:SetText("")
    end

    row.chance:SetText(ns.Format.Chance(entry.chance))
end
