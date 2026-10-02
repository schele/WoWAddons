local addonName, ns = ...

-- A round button on the minimap's rim: click to show or hide every pin,
-- right-click for the settings, drag to slide it round the rim. Built by
-- hand, as the other addons' buttons are.

local MinimapButton = {}
ns.MinimapButton = MinimapButton

ns.AddDefaults({
    -- Degrees anticlockwise from the right, apart from the other addons' buttons.
    button = { angle = 220, hide = false },
})

local SIZE = 31
local RIM_OFFSET = 10 -- how far past the minimap's edge the button's centre sits
local ICON = "Interface\\AddOns\\GatherMap\\minimap"

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
    local x, y = MinimapButton.PositionFor(ns.settings.button.angle, radius())
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Guarded: a drag that raised every frame would flood the error log.
local function followCursor()
    ns.Guarded(function()
        local centerX, centerY = Minimap:GetCenter()
        local cursorX, cursorY = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        ns.settings.button.angle = MinimapButton.AngleFor(cursorX / scale - centerX, cursorY / scale - centerY)
        place()
    end)
end

local function showTooltip(self)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local function state(on)
        return on and "|cff40ff40shown|r" or "|cffff4040hidden|r"
    end
    GameTooltip:SetText("GatherMap: pins " .. state(ns.settings.enabled)
        .. ", minimap pins " .. state(ns.settings.minimap.show))
    GameTooltip:AddLine("Click to show or hide every pin.", 1, 1, 1)
    GameTooltip:AddLine("Shift-click to show or hide the minimap's pins.", 1, 1, 1)
    GameTooltip:AddLine("Right-click for the settings, drag to move.", 1, 1, 1)
    GameTooltip:Show()
end

local function shiftDown()
    return ns.Guarded(function()
        return IsShiftKeyDown() and true or false
    end, false)
end

local function onClick(self, mouseButton)
    if mouseButton == "RightButton" then
        ns.ToggleSettings()
        return
    end
    if shiftDown() then
        ns.Filter.SetShown("minimap", not ns.settings.minimap.show)
        ns.Print(ns.settings.minimap.show and "Minimap pins shown." or "Minimap pins hidden.")
    else
        ns.SetEnabled(not ns.settings.enabled)
        ns.Print(ns.settings.enabled and "Pins shown." or "Pins hidden.")
    end
    if GameTooltip and GameTooltip:GetOwner() == self then
        showTooltip(self)
    end
end

local function create()
    button = CreateFrame("Button", "GatherMapMinimapButton", Minimap)
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", followCursor) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    place()
    button:SetShown(not ns.settings.button.hide)
end

function MinimapButton.Button()
    return button
end

ns.OnLogin(function()
    if Minimap then
        create()
    end
end)

--- Hide the button, or show it again; remembered. The settings page is told,
-- so its checkbox follows a change made by command.
function MinimapButton.SetHidden(hide)
    ns.settings.button.hide = hide and true or false
    if button then
        button:SetShown(not ns.settings.button.hide)
    end
    if ns.SettingsPanel then
        ns.SettingsPanel.Refresh()
    end
end

ns.RegisterCommand("minimap", "Hide or show the minimap button", function()
    MinimapButton.SetHidden(not ns.settings.button.hide)
    if ns.settings.button.hide then
        ns.Print("Minimap button hidden. /gmap minimap brings it back.")
    else
        ns.Print("Minimap button shown.")
    end
end)
