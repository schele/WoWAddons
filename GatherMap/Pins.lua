local addonName, ns = ...

-- A pin, the same on the world map and the minimap, one per spot however
-- many places share it: the icon of what grows there with a gold edge, a
-- tooltip, and a Shift-right-click to forget the spot.

local Pins = {}
ns.Pins = Pins

-- For nodes with no loot to take an icon from, and herbs or ore whose item
-- the client does not know.
Pins.KIND_ICONS = {
    herb = "Interface\\Icons\\INV_Misc_Herb_07",
    ore = "Interface\\Icons\\INV_Ore_Copper_01",
}

local GOLD = { 1, 0.82, 0 }

local icons = {}

function Pins.Icon(node)
    if node.item and icons[node.item] == nil then
        icons[node.item] = ns.Guarded(function()
            if C_Item and C_Item.GetItemIconByID then
                return C_Item.GetItemIconByID(node.item)
            end
            return GetItemIcon(node.item)
        end) or false
    end
    return (node.item and icons[node.item]) or Pins.KIND_ICONS[node.kind]
end

--- "A", "A or B", "A, B or C".
local function joinNames(names)
    if #names == 1 then
        return names[1]
    end
    return table.concat(names, ", ", 1, #names - 1) .. " or " .. names[#names]
end

--- The tooltip for a pin's `members`, the places at its spot it shows:
-- their names, each one's skill, how often, and how to forget the spot.
function Pins.ShowTooltip(owner, members)
    if not GameTooltip or #members == 0 then
        return
    end
    local names, nodes, count = {}, {}, 0
    for _, spawn in ipairs(members) do
        local node = ns.Spawns.Node(spawn)
        nodes[#nodes + 1] = node
        names[#names + 1] = node.name
        count = count + ((spawn.point and spawn.point.count) or 0)
    end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(joinNames(names))
    for _, node in ipairs(nodes) do
        if node.skill then
            local rgb = ns.Skills.RGB[ns.Skills.Color(node.skill, ns.Skills.Get(node.kind))]
            GameTooltip:AddLine(string.format("%s %d", ns.Skills.LABEL[node.kind], node.skill), rgb[1], rgb[2], rgb[3])
        end
    end
    GameTooltip:AddLine(string.format("Gathered here %d %s", count, count == 1 and "time" or "times"), 1, 1, 1)
    GameTooltip:AddLine("Shift-right-click: forget this place", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

-- The pin under the cursor is gone once the maps redraw, and so is its
-- tooltip.
local function forget(pin)
    ns.Recorder.Forget(pin.members)
    if GameTooltip then
        GameTooltip:Hide()
    end
end

local function shiftDown()
    return ns.Guarded(function()
        return IsShiftKeyDown() and true or false
    end, false)
end

--- A pin on `parent`. Shift-right-click forgets its spot; a plain
-- right-click calls `onRightClick(pin)`, if given. Left clicks go through to
-- whatever is beneath.
function Pins.Create(parent, onRightClick)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetFrameLevel(parent:GetFrameLevel() + 5)
    pin:EnableMouse(true)
    -- The mouse is for the tooltip; a left click belongs to the map.
    ns.Guarded(function() pin:SetPassThroughButtons("LeftButton") end)

    local edge = pin:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(pin)
    edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    pin.edge = edge

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", pin, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -1, 1)
    -- Trimmed of the icon art's own dark rim, which at this size is most of it.
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pin.icon = icon

    pin:SetScript("OnEnter", function(self)
        if self.members then
            Pins.ShowTooltip(self, self.members)
        end
    end)
    pin:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    pin:SetScript("OnMouseUp", function(self, mouseButton)
        if mouseButton ~= "RightButton" then
            return
        end
        if shiftDown() then
            if self.members then
                forget(self)
            end
        elseif onRightClick then
            onRightClick(self)
        end
    end)
    return pin
end

--- Point `pin` at a spot's `members` shown (at least one), `size` pixels
-- across, drawn as the first, and show it.
function Pins.Set(pin, members, size)
    pin.spawn = members[1]
    pin.members = members
    pin:SetSize(size, size)
    pin.icon:SetTexture(Pins.Icon(ns.Spawns.Node(members[1])))
    pin.edge:Show()
    pin:Show()
end

--- Pins on one parent, reused from draw to draw: Begin, then Acquire one per
-- spot drawn, then Finish hides whatever was not acquired. `onRightClick`
-- goes to every pin (see Pins.Create).
function Pins.Pool(parent, onRightClick)
    local pool = { pins = {}, used = 0 }

    function pool:Begin()
        self.used = 0
    end

    function pool:Acquire()
        self.used = self.used + 1
        local pin = self.pins[self.used]
        if not pin then
            pin = Pins.Create(parent, onRightClick)
            self.pins[self.used] = pin
        end
        return pin
    end

    function pool:Finish()
        for index = self.used + 1, #self.pins do
            self.pins[index]:Hide()
            self.pins[index].spawn = nil
            self.pins[index].members = nil
        end
    end

    --- The pins handed out since Begin, in order.
    function pool:Shown()
        local shown = {}
        for index = 1, self.used do
            shown[index] = self.pins[index]
        end
        return shown
    end

    return pool
end
