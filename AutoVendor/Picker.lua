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

--- Whether the mouse is over the grid. While it is, the page holds the grid
-- still: each click lengthens the junk list above it, and a grid that slid
-- down under the mouse would put the next click on another item.
function Picker.Hovered()
    local frame = Picker.frame
    return frame ~= nil and frame.IsMouseOver ~= nil and frame:IsMouseOver() and true or false
end

--- Called once the mouse has left the grid, for the page to catch up. Set
-- by the page.
Picker.OnLeft = nil

-- Leaving one icon may only be moving to the next, so look again once the
-- mouse has arrived wherever it was going.
local function leaving()
    C_Timer.After(0, function()
        if Picker.OnLeft and not Picker.Hovered() then
            Picker.OnLeft()
        end
    end)
end

--- Make the grid on `parent`, `width` across. The page anchors
-- `Picker.frame`; until `Refresh` it shows nothing.
function Picker.Build(parent, width)
    Picker.columns = math.max(1, math.floor((width + GAP) / (ICON + GAP)))

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, ICON)
    -- Takes the mouse between the icons too, so leaving the grid through a
    -- gap is noticed as much as leaving it from an icon.
    frame:EnableMouse(true)
    frame:SetScript("OnLeave", leaving)
    Picker.frame = frame

    local empty = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    empty:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    empty:SetWidth(width)
    empty:SetJustifyH("LEFT")
    empty:SetText("Nothing else in your bags can be sold.")
    Picker.empty = empty
end

local function addButton(index)
    local button = CreateFrame("Button", nil, Picker.frame)
    button:SetSize(ICON, ICON)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints(button)
    button:SetHighlightTexture(HIGHLIGHT, "ADD")

    -- Redrawn while it shows, so it names what the icon holds now, not what
    -- it held when the mouse came.
    button:SetScript("OnEnter", ns.ShowItemTooltip)
    button.UpdateTooltip = ns.ShowItemTooltip
    button:SetScript("OnLeave", function()
        ns.HideItemTooltip()
        leaving()
    end)
    -- The button's item changes as the grid redraws, so the click reads it
    -- then rather than holding the one it was made for. A plain click only:
    -- Shift-click means "link this" everywhere else, and an item put on the
    -- junk list by surprise is sold at the next merchant. An icon already
    -- clicked, still showing while the mouse is over the grid, does nothing.
    button:SetScript("OnClick", function(self)
        if not self.itemID or self.taken then
            return
        end
        if IsModifierKeyDown and IsModifierKeyDown() then
            return
        end
        ns.Junk.Add(self.itemID, self.name)
    end)

    Picker.buttons[index] = button
    return button
end

--- Grey out each icon whose item has gone on a list, without moving
-- anything: what the grid shows while the mouse is still over it.
function Picker.MarkTaken()
    for _, button in ipairs(Picker.buttons) do
        if button.itemID and (ns.Junk.Has(button.itemID) or ns.Keep.Has(button.itemID)) then
            button.taken = true
            button.icon:SetDesaturated(true)
            button:SetAlpha(0.5)
        end
    end
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
        button.taken = false
        button.icon:SetTexture(item.icon)
        button.icon:SetDesaturated(false)
        button:SetAlpha(1)
        button:Show()
    end
    for index = #items + 1, #Picker.buttons do
        local button = Picker.buttons[index]
        button.itemID = nil
        button.name = nil
        button.taken = false
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
