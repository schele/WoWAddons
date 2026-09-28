local addonName, ns = ...

-- A pin, the same on the world map and the minimap: the node's icon, a gold
-- edge where the player has gathered, dimmed where only vMaNGOS says so, a
-- tooltip, and a right-click for "not here".

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

function Pins.ShowTooltip(owner, spawn)
    local node = ns.Nodes[spawn.entry]
    if not node or not GameTooltip then
        return
    end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(node.name)
    if node.skill then
        local rgb = ns.Skills.RGB[ns.Skills.Color(node.skill, ns.Skills.Get(node.kind))]
        GameTooltip:AddLine(string.format("%s %d", ns.Skills.LABEL[node.kind], node.skill), rgb[1], rgb[2], rgb[3])
    end

    local point = ns.db.gathered[spawn.key]
    if type(point) == "table" and point.count then
        GameTooltip:AddLine(string.format("Gathered here %d %s", point.count, point.count == 1 and "time" or "times"), 1, 1, 1)
    elseif ns.confirmed[spawn.key] then
        GameTooltip:AddLine("Confirmed in WoW Forever", 1, 1, 1)
    else
        GameTooltip:AddLine("From the classic database, not seen in WoW Forever yet", 0.7, 0.7, 0.7)
    end

    if ns.db.missing[spawn.key] then
        GameTooltip:AddLine("Marked not here. Right-click to undo.", 1, 0.5, 0.25)
    else
        GameTooltip:AddLine("Right-click: not here", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

-- The pin under the cursor may be drawn for another spawn, or gone, once
-- the maps redraw, so the tooltip follows the spawn rather than the frame.
local function toggleMissing(pin)
    local spawn = pin.spawn
    ns.Recorder.ToggleMissing(spawn)
    if not GameTooltip then
        return
    end
    if pin:IsShown() and pin.spawn == spawn then
        Pins.ShowTooltip(pin, spawn)
    else
        GameTooltip:Hide()
    end
end

function Pins.Create(parent)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetFrameLevel(parent:GetFrameLevel() + 5)
    pin:EnableMouse(true)

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
        if self.spawn then
            Pins.ShowTooltip(self, self.spawn)
        end
    end)
    pin:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    pin:SetScript("OnMouseUp", function(self, mouseButton)
        if mouseButton == "RightButton" and self.spawn then
            toggleMissing(self)
        end
    end)
    return pin
end

--- Point `pin` at `spawn`, `size` pixels across, and show it.
function Pins.Set(pin, spawn, size)
    pin.spawn = spawn
    pin:SetSize(size, size)
    pin.icon:SetTexture(Pins.Icon(ns.Nodes[spawn.entry]))
    pin.edge:SetShown(ns.db.gathered[spawn.key] ~= nil)
    pin:SetAlpha(ns.Filter.Confirmed(spawn) and 1 or Pins.DIM)
    pin:Show()
end

--- Pins on one parent, reused from draw to draw: Begin, then Acquire one per
-- spawn drawn, then Finish hides whatever was not acquired.
function Pins.Pool(parent)
    local pool = { pins = {}, used = 0 }

    function pool:Begin()
        self.used = 0
    end

    function pool:Acquire()
        self.used = self.used + 1
        local pin = self.pins[self.used]
        if not pin then
            pin = Pins.Create(parent)
            self.pins[self.used] = pin
        end
        return pin
    end

    function pool:Finish()
        for index = self.used + 1, #self.pins do
            self.pins[index]:Hide()
            self.pins[index].spawn = nil
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
