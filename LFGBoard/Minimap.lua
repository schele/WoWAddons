local addonName, ns = ...

-- A round button on the minimap's rim: click to open the board, drag to
-- slide it round the rim. Built as BankBags' is.

local MinimapButton = {}
ns.MinimapButton = MinimapButton

ns.AddDefaults({
    -- Degrees anticlockwise from the right, clear of the other addons'.
    minimap = { angle = 125, hide = false },
})

local SIZE = 31
local RIM_OFFSET = 10 -- how far past the minimap's edge the button's centre sits
local ICON = "Interface\\AddOns\\LFGBoard\\minimap"

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

-- Guarded: this client has made values secret before, and a drag that
-- raised every frame would flood the error log.
local function followCursor()
    ns.Guarded(function()
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
    GameTooltip:SetText("LFG Board")
    GameTooltip:AddLine("Click to open the board, drag to move.", 1, 1, 1)
    GameTooltip:Show()
end

local function create()
    button = CreateFrame("Button", "LFGBoardMinimapButton", Minimap)
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

    button:SetScript("OnClick", function()
        ns.Window.Toggle()
    end)
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

ns.OnLogin(function()
    if Minimap then
        create()
    end
end)

--- Hide the button, or show it again; remembered. The board is told, so its
-- switch follows a change made by command.
function MinimapButton.SetHidden(hide)
    ns.db.minimap.hide = hide and true or false
    if button then
        button:SetShown(not ns.db.minimap.hide)
    end
    ns.Changed()
end

ns.RegisterCommand("minimap", "hide or show the minimap button", function()
    MinimapButton.SetHidden(not ns.db.minimap.hide)
    ns.Print(ns.db.minimap.hide and "Minimap button hidden. /lfgb minimap brings it back."
        or "Minimap button shown.")
end)
