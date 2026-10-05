local addonName, ns = ...

-- A pin, the same on the world map and the minimap: RareMob's skull, bright
-- for a rare seen on WoW Forever and dimmed for one only in the classic
-- database, with a gold edge where the player saw it themselves. While its
-- rare is near, a glow behind it pulses; the rare picked in the list glows
-- steadily.

local Pins = {}
ns.Pins = Pins

ns.AddDefaults({ pinSize = 14 })

Pins.ICON = "Interface\\AddOns\\RareMob\\minimap"
Pins.GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
Pins.DIM = 0.55 -- a database-only pin's alpha

local GOLD = { 1, 0.82, 0 }
local PULSE = { 1, 0.25, 0.1 }
local PICKED = { 1, 0.9, 0.3 }
local GREY = { 0.6, 0.6, 0.6 }
local WHITE = { 1, 1, 1 }

-- The rare picked in the list, whose pins glow; nil for none.
Pins.highlight = nil

local pools = {}

--- What a pin's tooltip says of rare `id`, line by line: { text, r, g, b }.
function Pins.TooltipLines(id)
    local info = ns.Rares.Info(id)
    if not info then
        return {}
    end
    local lines = {
        { text = info.name, color = WHITE },
        { text = "Level " .. ns.Rares.LevelText(info), color = WHITE },
        { text = info.elite and "Rare elite" or "Rare", color = GREY },
    }
    if info.seen then
        if info.last then
            lines[#lines + 1] = { text = "Last seen " .. ns.Rares.Ago(time() - info.last), color = WHITE }
        end
        lines[#lines + 1] = { text = "Seen on WoW Forever", color = { 0.25, 1, 0.25 } }
    else
        lines[#lines + 1] = { text = "From the classic database, not seen on WoW Forever yet", color = GREY }
    end
    return lines
end

function Pins.ShowTooltip(owner, id)
    if not GameTooltip then
        return
    end
    local lines = Pins.TooltipLines(id)
    if #lines == 0 then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(lines[1].text)
    for index = 2, #lines do
        local color = lines[index].color
        GameTooltip:AddLine(lines[index].text, color[1], color[2], color[3])
    end
    GameTooltip:Show()
end

--- A pin on `parent`, at `frameLevel` if given, else just above `parent`.
-- Left clicks go through to whatever is beneath: the map's own.
function Pins.Create(parent, frameLevel)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetFrameLevel(frameLevel or parent:GetFrameLevel() + 5)
    pin:EnableMouse(true)
    ns.Guarded(function() pin:SetPassThroughButtons("LeftButton") end)

    local glow = pin:CreateTexture(nil, "BACKGROUND", nil, -8)
    glow:SetTexture(Pins.GLOW)
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER", pin, "CENTER", 0, 0)
    glow:Hide()
    pin.glow = glow

    local edge = pin:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(pin)
    edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    pin.edge = edge

    -- A dark square behind the skull, so it reads on any map art.
    local back = pin:CreateTexture(nil, "BORDER")
    back:SetPoint("TOPLEFT", pin, "TOPLEFT", 1, -1)
    back:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -1, 1)
    back:SetColorTexture(0, 0, 0, 0.7)
    pin.back = back

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", pin, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -1, 1)
    icon:SetTexture(Pins.ICON)
    pin.icon = icon

    pin:SetScript("OnEnter", function(self)
        if self.id then
            Pins.ShowTooltip(self, self.id)
        end
    end)
    pin:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    return pin
end

--- Point `pin` at `place` ({ id, x, y, sighting }), `size` pixels across,
-- and show it.
function Pins.Set(pin, place, size)
    local info = ns.Rares.Info(place.id)
    local seen = info ~= nil and info.seen
    pin.place = place
    pin.id = place.id
    pin:SetSize(size, size)
    pin.icon:SetDesaturated(not seen)
    pin:SetAlpha(seen and 1 or Pins.DIM)
    pin.edge:SetShown(info ~= nil and info.own)

    pin.pulsing = ns.Spotter.IsSpotted(place.id)
    local picked = Pins.highlight ~= nil and Pins.highlight == place.id
    pin.glow:SetSize(size * 2, size * 2)
    if pin.pulsing then
        pin.glow:SetVertexColor(PULSE[1], PULSE[2], PULSE[3], 1)
    elseif picked then
        pin.glow:SetVertexColor(PICKED[1], PICKED[2], PICKED[3], 1)
        pin.glow:SetAlpha(1)
    end
    pin.glow:SetShown(pin.pulsing or picked)
    pin:Show()
end

--- Pins on one parent, reused from draw to draw: Begin, then Acquire one per
-- place drawn, then Finish hides whatever was not acquired.
function Pins.Pool(parent, frameLevel)
    local pool = { pins = {}, used = 0 }

    function pool:Begin()
        self.used = 0
    end

    function pool:Acquire()
        self.used = self.used + 1
        local pin = self.pins[self.used]
        if not pin then
            pin = Pins.Create(parent, frameLevel)
            self.pins[self.used] = pin
        end
        return pin
    end

    function pool:Finish()
        for index = self.used + 1, #self.pins do
            local pin = self.pins[index]
            pin:Hide()
            pin.place, pin.id, pin.pulsing = nil, nil, false
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

    table.insert(pools, pool)
    return pool
end

--- Set the pulsing glows' strength for time `now`, in seconds: a beat
-- about every 0.8 seconds.
function Pins.Animate(now)
    local strength = 0.25 + 0.75 * math.abs(math.sin(now * 4))
    for _, pool in ipairs(pools) do
        for index = 1, pool.used do
            local pin = pool.pins[index]
            if pin.pulsing then
                pin.glow:SetAlpha(strength)
            end
        end
    end
end

ns.OnLogin(function()
    local animator = CreateFrame("Frame")
    animator:SetScript("OnUpdate", function()
        ns.Guarded(function() Pins.Animate(GetTime()) end)
    end)
    Pins.animator = animator
end)
