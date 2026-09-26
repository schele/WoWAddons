local addonName, ns = ...

-- A round button on the minimap's rim: click to open the settings; drag to
-- slide it round the rim. Built by hand, as BossLoot's is.

local MinimapButton = {}
ns.MinimapButton = MinimapButton

ns.AddDefaults({
    -- Degrees anticlockwise from the right, apart from the other addons' buttons.
    minimap = { angle = 175, hide = false },
})

local SIZE = 31
local RIM_OFFSET = 10 -- how far past the minimap's edge the button's centre sits
local ICON = "Interface\\AddOns\\ForeverPanel\\logo"

local button

function MinimapButton.PositionFor(angle, radius)
    local radians = math.rad(angle)
    return math.cos(radians) * radius, math.sin(radians) * radius
end

-- Lua 5.1 has math.atan2; later versions take two arguments to math.atan.
local atan2 = math.atan2 or math.atan

function MinimapButton.AngleFor(dx, dy)
    local angle = math.deg(atan2(dy, dx))
    if angle < 0 then
        angle = angle + 360
    end
    return angle
end

local function radius()
    return (Minimap:GetWidth() / 2) + RIM_OFFSET
end

local function place()
    local x, y = MinimapButton.PositionFor(ns.db.minimap.angle, radius())
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Guarded: this client has made values secret before, and a drag that raised
-- every frame would flood the error log.
local function followCursor()
    pcall(function()
        local centerX, centerY = Minimap:GetCenter()
        local cursorX, cursorY = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        ns.db.minimap.angle = MinimapButton.AngleFor(cursorX / scale - centerX, cursorY / scale - centerY)
        place()
    end)
end

local function showTooltip(self)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("ForeverPanel")
    GameTooltip:AddLine("Click to open or close the settings, drag to move.", 1, 1, 1)
    GameTooltip:Show()
end

local function onClick()
    ns.ToggleSettings()
end

local function create()
    button = CreateFrame("Button", "ForeverPanelMinimapButton", Minimap)
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- The standard minimap-button layers: a dark disc, the icon on it, and
    -- the gold tracking ring over both.
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(ICON)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    button:SetScript("OnClick", onClick)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", followCursor)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    place()
    button:SetShown(not ns.db.minimap.hide)
end

function MinimapButton.Button()
    return button
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if Minimap then
        create()
    end
end)

ns.RegisterCommand("minimap", "Hide or show the minimap button", function()
    ns.db.minimap.hide = not ns.db.minimap.hide
    if button then
        button:SetShown(not ns.db.minimap.hide)
    end
    if ns.db.minimap.hide then
        ns.Print("Minimap button hidden. /fp minimap brings it back.")
    else
        ns.Print("Minimap button shown.")
    end
end)
