local addonName, ns = ...

-- A pin, the same on the world map and the minimap, one per spot however
-- many spawns share it: the node's icon, a gold edge where the player has
-- gathered, dimmed where only vMaNGOS says so, a tooltip, and a
-- Shift-right-click for "not here".

local Pins = {}
ns.Pins = Pins

-- A spawn only the database has is a guess: WoW Forever is not vanilla.
Pins.DIM = 0.55

-- For nodes with no loot to take an icon from, and herbs or ore whose item
-- the client does not know.
Pins.KIND_ICONS = {
    herb = "Interface\\Icons\\INV_Misc_Herb_07",
    ore = "Interface\\Icons\\INV_Ore_Copper_01",
    pool = "Interface\\Icons\\INV_Misc_Fish_02",
    chest = "Interface\\Icons\\INV_Box_01",
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

--- The tooltip for a pin's `members`, the spawns at its spot it shows: their
-- names, each one's skill, then one line for the spot and one for "not here".
function Pins.ShowTooltip(owner, members)
    if not GameTooltip then
        return
    end
    local names, nodes = {}, {}
    for _, spawn in ipairs(members) do
        local node = ns.Nodes[spawn.entry]
        if node then
            nodes[#nodes + 1] = node
            names[#names + 1] = node.name
        end
    end
    if #nodes == 0 then
        return
    end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(joinNames(names))
    for _, node in ipairs(nodes) do
        if node.skill then
            local rgb = ns.Skills.RGB[ns.Skills.Color(node.skill, ns.Skills.Get(node.kind))]
            GameTooltip:AddLine(string.format("%s %d", ns.Skills.LABEL[node.kind], node.skill), rgb[1], rgb[2], rgb[3])
        end
    end

    local count, confirmed, marked = nil, false, true
    for _, spawn in ipairs(members) do
        local point = ns.db.gathered[spawn.key]
        if type(point) == "table" and point.count then
            count = (count or 0) + point.count
        end
        if ns.confirmed[spawn.key] then
            confirmed = true
        end
        if not ns.db.missing[spawn.key] then
            marked = false
        end
    end

    if count then
        GameTooltip:AddLine(string.format("Gathered here %d %s", count, count == 1 and "time" or "times"), 1, 1, 1)
    elseif confirmed then
        GameTooltip:AddLine("Confirmed in WoW Forever", 1, 1, 1)
    else
        GameTooltip:AddLine("From the classic database, not seen in WoW Forever yet", 0.7, 0.7, 0.7)
    end

    if marked then
        GameTooltip:AddLine("Marked not here. Shift-right-click to undo.", 1, 0.5, 0.25)
    else
        GameTooltip:AddLine("Shift-right-click: not here", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

-- The pin under the cursor may be drawn for another spot, or gone, once the
-- maps redraw, so the tooltip follows the spot rather than the frame.
local function toggleMissing(pin)
    local stack = pin.spawn.stack
    ns.Recorder.ToggleMissingAll(pin.members)
    if not GameTooltip then
        return
    end
    if pin:IsShown() and pin.spawn and pin.spawn.stack == stack then
        Pins.ShowTooltip(pin, pin.members)
    else
        GameTooltip:Hide()
    end
end

local function shiftDown()
    return ns.Guarded(function()
        return IsShiftKeyDown() and true or false
    end, false)
end

--- A pin on `parent`. Shift-right-click marks it "not here"; a plain
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
                toggleMissing(self)
            end
        elseif onRightClick then
            onRightClick(self)
        end
    end)
    return pin
end

--- Point `pin` at a spot's `members` shown (at least one), `size` pixels
-- across, and show it. It is drawn as the first member confirmed in game,
-- else the first; gold-edged if the player gathered any, full strength if
-- any is confirmed.
function Pins.Set(pin, members, size)
    local spawn, gathered
    for _, member in ipairs(members) do
        if not spawn and ns.Filter.Confirmed(member) then
            spawn = member
        end
        gathered = gathered or ns.db.gathered[member.key] ~= nil
    end
    local confirmed = spawn ~= nil
    spawn = spawn or members[1]

    pin.spawn = spawn
    pin.members = members
    pin:SetSize(size, size)
    pin.icon:SetTexture(Pins.Icon(ns.Nodes[spawn.entry]))
    pin.edge:SetShown(gathered)
    pin:SetAlpha(confirmed and 1 or Pins.DIM)
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
