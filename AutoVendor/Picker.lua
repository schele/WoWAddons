local addonName, ns = ...

-- The settings page's grid of bag items: each item in the bags that could go
-- on the junk list, once, as its icon. Hover for the item's tooltip; click to
-- always sell it. The page places the grid and redraws it.

local Picker = {}
ns.Picker = Picker

local ICON = 32
local GAP = 4
-- The square the icon is drawn in when the mouse is over it, as the bags do.
local HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"

-- One per item shown, made as the grid first grows that big and kept after,
-- hidden when it is smaller, so a redraw never leaves frames behind.
Picker.buttons = {}

--- Make the grid on `parent`, `width` across. The page anchors
-- `Picker.frame`; until `Refresh` it shows nothing.
function Picker.Build(parent, width)
    Picker.columns = math.max(1, math.floor((width + GAP) / (ICON + GAP)))

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, ICON)
    Picker.frame = frame

    local empty = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    empty:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    empty:SetWidth(width)
    empty:SetJustifyH("LEFT")
    empty:SetText("Nothing else in your bags can be sold.")
    Picker.empty = empty
end

local function showTooltip(button)
    if not (GameTooltip and button.itemID) then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(button.itemID)
    else
        GameTooltip:SetHyperlink("item:" .. button.itemID)
    end
    GameTooltip:Show()
end

local function addButton(index)
    local button = CreateFrame("Button", nil, Picker.frame)
    button:SetSize(ICON, ICON)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints(button)
    button:SetHighlightTexture(HIGHLIGHT, "ADD")

    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    -- The button's item changes as the grid redraws, so the click reads it
    -- then rather than holding the one it was made for.
    button:SetScript("OnClick", function(self)
        if self.itemID then
            ns.Junk.Add(self.itemID, self.name)
        end
    end)

    Picker.buttons[index] = button
    return button
end

--- Draw the grid from the bags as they are now. How tall it stands.
function Picker.Refresh()
    local items = ns.Bags.Sellable(ns.Keep.All(), ns.Junk.All())

    for index, item in ipairs(items) do
        local button = Picker.buttons[index] or addButton(index)
        local column = (index - 1) % Picker.columns
        local row = math.floor((index - 1) / Picker.columns)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", Picker.frame, "TOPLEFT", column * (ICON + GAP), -row * (ICON + GAP))
        button.itemID = item.itemID
        button.name = item.name
        button.icon:SetTexture(item.icon)
        button:Show()
    end
    for index = #items + 1, #Picker.buttons do
        local button = Picker.buttons[index]
        button.itemID = nil
        button.name = nil
        button:Hide()
    end

    local height
    if #items == 0 then
        Picker.empty:Show()
        height = Picker.empty:GetStringHeight()
    else
        Picker.empty:Hide()
        local rows = math.ceil(#items / Picker.columns)
        height = rows * (ICON + GAP) - GAP
    end
    Picker.frame:SetHeight(height)
    return height
end
