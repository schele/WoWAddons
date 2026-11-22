local addonName, ns = ...

-- What the player sees: a pulsing border on every action button that holds
-- a Ferocious Bite, and the Bite's icon above the middle of the screen, lit
-- when a Bite now would kill the target. Each is made of status bars whose
-- fill Gate sets: on WoW Forever the client fills them, comparing a health
-- this code never sees. That is also why there is no sound or chat line:
-- those would need this code to know the answer.

local Glow = {}
ns.Glow = Glow

ns.AddDefaults({ buttons = true, center = true })

-- The action bars' buttons, as the client names them: twelve to a bar.
Glow.BARS = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}
Glow.PER_BAR = 12

Glow.COLOUR = { 1, 0.42, 0.12 } -- ember orange, apart from the game's own yellow proc glow
Glow.TICK = 0.2 -- seconds between looks, for anything the events missed
Glow.TEST_SECONDS = 3
Glow.CENTER_SIZE = 56
Glow.CENTER_Y = 140 -- above the character's head

-- Each button that has held a Bite, and the border drawn on it.
Glow.buttons = {}

--- Pieces of `frame.gate` (see Gate.lua): a border just outside `frame`,
-- `thickness` thick, and a faint wash over it, pulsing while shown.
local function border(frame, thickness)
    local r, g, b = unpack(Glow.COLOUR)
    local gate = frame.gate
    local function edge(width, height, ...)
        local piece = gate:Piece(nil, r, g, b, 1, "ADD", 2)
        if width then piece:SetWidth(width) end
        if height then piece:SetHeight(height) end
        for _, anchor in ipairs({ ... }) do
            piece:SetPoint(unpack(anchor))
        end
    end
    local t = thickness
    edge(nil, t, { "BOTTOMLEFT", frame, "TOPLEFT", -t, 0 }, { "BOTTOMRIGHT", frame, "TOPRIGHT", t, 0 })
    edge(nil, t, { "TOPLEFT", frame, "BOTTOMLEFT", -t, 0 }, { "TOPRIGHT", frame, "BOTTOMRIGHT", t, 0 })
    edge(t, nil, { "TOPRIGHT", frame, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0 })
    edge(t, nil, { "TOPLEFT", frame, "TOPRIGHT", 0, 0 }, { "BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, 0 })
    local wash = gate:Piece(nil, r, g, b, 0.3, "ADD", 2)
    wash:SetAllPoints(frame)

    local pulse = gate.holder:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.45)
    fade:SetSmoothing("IN_OUT")
    frame.pulse = pulse
    frame:SetScript("OnShow", function() pulse:Play() end)
end

local function overlayFor(button)
    local overlay = Glow.buttons[button]
    if overlay then
        return overlay
    end
    overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    local level = ns.Guarded(function() return button:GetFrameLevel() end, 1)
    overlay:SetFrameLevel((tonumber(level) or 1) + 5)
    overlay.gate = ns.Gate.New(overlay)
    border(overlay, 2)
    overlay:Hide()
    Glow.buttons[button] = overlay
    return overlay
end

local function buildCenter()
    local center = CreateFrame("Frame", nil, UIParent)
    center:SetSize(Glow.CENTER_SIZE, Glow.CENTER_SIZE)
    center:SetPoint("CENTER", UIParent, "CENTER", 0, Glow.CENTER_Y)
    center:SetFrameStrata("HIGH")
    center.gate = ns.Gate.New(center)
    center.icon = center.gate:Piece(nil, 1, 1, 1, 1, nil, 1) -- the Bite's icon, once known
    center.icon:SetAllPoints(center)
    border(center, 4)
    center:Hide()
    return center
end

Glow.center = buildCenter()

local function setIcon(icon)
    if icon and Glow.center.iconID ~= icon then
        Glow.center.icon:SetStatusBarTexture(icon)
        Glow.center.iconID = icon
    end
end

local function slotOf(button)
    return ns.Guarded(function()
        local slot = button.action
        if type(slot) ~= "number" and button.GetAttribute then
            slot = button:GetAttribute("action")
        end
        return ns.Number(slot)
    end)
end

--- The Bite rank in action slot `slot`, or nil.
local function biteIn(slot)
    return ns.Guarded(function()
        local kind, id = GetActionInfo(slot)
        if kind == "spell" and ns.Bite.Is(id) then
            return id
        end
        return nil
    end)
end

--- Find the buttons that hold a Bite now, and which rank each holds.
function Glow.Scan()
    for _, bar in ipairs(Glow.BARS) do
        for index = 1, Glow.PER_BAR do
            local button = _G[bar .. index]
            if button then
                local slot = slotOf(button)
                local id = slot and biteIn(slot)
                if id then
                    overlayFor(button).rankID = id
                elseif Glow.buttons[button] then
                    Glow.buttons[button].rankID = nil
                end
            end
        end
    end
end

--- How many buttons hold a Bite.
function Glow.Count()
    local count = 0
    for _, overlay in pairs(Glow.buttons) do
        if overlay.rankID then
            count = count + 1
        end
    end
    return count
end

local function weakest(rank)
    return rank.ranges[#rank.ranges][1]
end

--- The rank the icon in the middle goes by: the weakest on the bars, since a
-- press might cast that one, or the highest known when none is there.
function Glow.CenterRank()
    local best
    for _, overlay in pairs(Glow.buttons) do
        local rank = overlay.rankID and ns.Bite.Read(overlay.rankID)
        if rank and (not best or weakest(rank) < weakest(best)) then
            best = rank
        end
    end
    return best or ns.Bite.Read(ns.Bite.TopRank())
end

-- Until when /bt test keeps everything lit.
local testUntil = 0

local function testing()
    return GetTime() < testUntil
end

--- Show `frame` lit as a Bite of `rank` would kill now, or hide it when that
-- cannot be weighed. The target's health goes to the frame's gate unseen.
local function show(frame, rank)
    if testing() then
        frame.gate:Test()
        frame:Show()
        return
    end
    local reach, health = ns.Kill.Weigh(rank)
    if not reach then
        frame:Hide()
        return
    end
    frame.gate:Set(reach, health)
    frame:Show()
end

--- Light or darken every border and the icon for the target as it is now.
function Glow.Update()
    local settings = ns.settings
    if not settings then
        return
    end
    for _, overlay in pairs(Glow.buttons) do
        if overlay.rankID and settings.buttons then
            show(overlay, ns.Bite.Read(overlay.rankID))
        else
            overlay:Hide()
        end
    end

    local rank = settings.center and Glow.CenterRank()
    if rank then
        setIcon(rank.icon)
        show(Glow.center, rank)
    else
        Glow.center:Hide()
    end
end

--- Light everything for a few seconds, to see what it looks like.
function Glow.Test()
    local settings = ns.settings
    if not (settings.buttons or settings.center) then
        ns.Print("Both are off. Turn one on in the settings page (/bt).")
        return
    end
    Glow.Scan()
    if Glow.Count() == 0 and not ns.Bite.TopRank() then
        ns.Print(string.format("You have not learned %s, so there is nothing to light.", ns.Bite.Name()))
        return
    end
    testUntil = GetTime() + Glow.TEST_SECONDS
    Glow.Update()
    C_Timer.After(Glow.TEST_SECONDS, Glow.Update)
end

ns.RegisterCommand("test", "Light the buttons and the icon for a few seconds", Glow.Test)

-- A number as a tooltip would write it: 177.5, but 40 rather than 40.0.
local function figure(value)
    if value == math.floor(value) then
        return string.format("%d", value)
    end
    return string.format("%.1f", value)
end

local function rankText(id)
    local text = ns.Guarded(function()
        return C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
    end)
    return type(text) == "string" and text ~= "" and string.format(" (%s)", text) or ""
end

local WHY = {
    notCat = "You are not in Cat Form.",
    noTarget = "No target you can attack.",
    player = "Your target is a player. BiteTime weighs only mobs.",
    hiddenPoints = "The game hides your combo points from addons, so BiteTime cannot tell what a Bite does.",
    noPoints = "No combo points on your target.",
}

--- The target's name, if the client lets addons read it.
local function targetName()
    local name = ns.Guarded(function() return UnitName(ns.Kill.UNIT) end)
    if ns.IsSecret(name) or type(name) ~= "string" then
        return "?"
    end
    return name
end

local function probeTarget(why)
    if why == "noTarget" or why == "player" then
        return WHY[why]
    end
    local name = targetName()
    local health = ns.Guarded(function() return UnitHealth(ns.Kill.UNIT) end)
    if ns.IsSecret(health) then
        return string.format("Target: %s. The game hides its health from addons, so the game itself does the "
            .. "comparing.", name)
    end
    health = ns.Number(health)
    local max = ns.Kill.MaxHealth()
    if health and max then
        return string.format("Target: %s, %d of %d health.", name, health, max)
    end
    if health then
        return string.format("Target: %s, %d health.", name, health)
    end
    return string.format("Target: %s. The game does not say its health.", name)
end

--- What a Bite of `rank` does now and what it takes, given combo points.
local function probeNow(rank)
    local points, energy = ns.Kill.Points(), ns.Kill.Energy()
    local have = energy and string.format("%d energy", energy) or "energy the game hides"
    ns.Print(string.format("Now: %d combo points and %s, so a Bite does at least %s. Counted at %d%%, that takes %d "
        .. "health.", points, have, figure(ns.Bite.Damage(rank, points, energy)),
        tonumber(ns.settings.share) or 100, ns.Kill.Reach(rank) or 0))
end

--- Say what this client lets BiteTime see: the Bite and its numbers, where
-- it sits, the target, and what a Bite would do now.
function Glow.Probe()
    Glow.Scan()
    local name = ns.Bite.Name()
    local rank = Glow.CenterRank()
    if not rank and Glow.Count() == 0 and not ns.Bite.TopRank() then
        ns.Print(string.format("You have not learned %s, so BiteTime has nothing to light.", name))
        return
    end

    if rank then
        local ranges = {}
        for index, range in ipairs(rank.ranges) do
            ranges[index] = string.format("%d-%d", range[1], range[2])
        end
        ns.Print(string.format("%s%s: %s damage for 1 to %d combo points. Each energy over %d adds %s.", name,
            rankText(rank.id), table.concat(ranges, ", "), #rank.ranges, rank.cost, figure(rank.perEnergy)))
    else
        ns.Print(string.format("%s's tooltip has no damage BiteTime can read.", name))
    end

    local count = Glow.Count()
    if count == 0 then
        ns.Print("It is on none of your action buttons, so only the icon in the middle can light.")
    else
        ns.Print(string.format("It is on %d of your action buttons.", count))
    end

    local why = ns.Kill.Why()
    ns.Print(probeTarget(why))
    if why == "notCat" or why == "noPoints" or why == "hiddenPoints" then
        ns.Print(WHY[why])
    elseif not why and rank then
        probeNow(rank)
    end

    if ns.Gate.Needed() then
        if ns.Gate.Check() then
            ns.Print("Bar check: the game keeps a bar's value inside its range, as BiteTime needs.")
        else
            ns.Print("Bar check failed: the game lets a bar's value leave its range, so BiteTime cannot light on "
                .. "WoW Forever.")
        end
    end
end

ns.RegisterCommand("probe", "Say what BiteTime can see: your Bite, your target and your combo points", Glow.Probe)

-- Events that may change what a Bite does or what the target has, those that
-- may move a Bite on the bars, and those that may change its tooltip.
local UPDATE = {
    PLAYER_TARGET_CHANGED = true, UPDATE_SHAPESHIFT_FORM = true, PLAYER_ENTERING_WORLD = true,
    COMBO_TARGET_CHANGED = true, -- combo points moving to another target, as Forever's own combo frame hears
}
local UNIT_UPDATE = {
    UNIT_HEALTH = "target", UNIT_MAXHEALTH = "target", UNIT_POWER_FREQUENT = "player",
    UNIT_POWER_UPDATE = "player", UNIT_ATTACK_POWER = "player",
}
local SCAN = {
    ACTIONBAR_SLOT_CHANGED = true, UPDATE_BONUS_ACTIONBAR = true, ACTIONBAR_PAGE_CHANGED = true,
    SPELLS_CHANGED = true, PLAYER_ENTERING_WORLD = true,
}
local FORGET = {
    UNIT_ATTACK_POWER = true, PLAYER_LEVEL_UP = true, SPELLS_CHANGED = true, SPELL_TEXT_UPDATE = true,
}

-- The game hides Lua errors by default, and a glow that errors just stays
-- dark. So the first error says so in chat; later ones would only repeat it.
local failed = false

local function safely(fn)
    local ok, err = pcall(fn)
    if not ok and not failed then
        failed = true
        ns.Print("Something went wrong, so BiteTime may not light: " .. tostring(err))
    end
end

local function scanAndUpdate()
    Glow.Scan()
    Glow.Update()
end

local events = CreateFrame("Frame")

events:SetScript("OnEvent", function(_, event)
    safely(function()
        if FORGET[event] then
            ns.Bite.Forget()
        end
        if SCAN[event] then
            Glow.Scan()
            -- The bars may only page after this event's other listeners run.
            C_Timer.After(0, function() safely(scanAndUpdate) end)
        end
        Glow.Update()
    end)
end)

local function listen()
    -- A client without one of these events refuses it; the rest still count.
    local all = {}
    for event in pairs(UPDATE) do all[event] = true end
    for event in pairs(SCAN) do all[event] = true end
    for event in pairs(FORGET) do all[event] = true end
    for event in pairs(all) do
        if not UNIT_UPDATE[event] then
            pcall(events.RegisterEvent, events, event)
        end
    end
    for event, unit in pairs(UNIT_UPDATE) do
        pcall(events.RegisterUnitEvent, events, event, unit)
    end

    local since = 0
    events:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since >= Glow.TICK then
            since = 0
            safely(Glow.Update)
        end
    end)
end

ns.OnRefresh(function() safely(Glow.Update) end)

ns.OnLogin(function()
    listen()
    safely(scanAndUpdate)
end)
