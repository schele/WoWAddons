local addonName, ns = ...

-- A bar for the Fishing skill: the skill and its cap on the left, filled by
-- the catches since the last point against how many a point takes
-- (Skill.lua). The right end is kept for a warning: "too low here" where the
-- game refused a cast, "capped" at the cap. Shown while a pole is equipped.
-- Dragged to move it, unless locked. Its tooltip is short; the count and what
-- the numbers mean are in the stats window (StatsPanel.lua), which a click
-- opens around it.

local SkillBar = {}
ns.SkillBar = SkillBar

local DEFAULT = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -200 }

ns.AddDefaults({
    skillBar = {
        shown = true,
        locked = false,
        -- The fishing stats under the bar (StatsPanel.lua).
        stats = false,
        point = DEFAULT.point,
        relativePoint = DEFAULT.relativePoint,
        x = DEFAULT.x,
        y = DEFAULT.y,
    },
})

local WIDTH, HEIGHT = 220, 18
-- On its own; inside the stats window it is as wide as the window's inside.
SkillBar.WIDTH = WIDTH
local TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
-- FishingForever's own blue, as in its chat prefix; grey at the cap.
local COLOUR = { 0.4, 0.8, 1 }
local CAPPED = { 0.5, 0.5, 0.5 }
-- The count's words: white, or the game's error red where it refused a cast.
local WHITE = { 1, 1, 1 }
local REFUSED = { 1, 0.3, 0.3 }

local bar

function SkillBar.Frame()
    return bar
end

local function settings()
    return ns.db.skillBar
end

local function changed()
    if ns.SettingsPanel then
        ns.SettingsPanel.Refresh()
    end
end

local function place()
    local db = settings()
    local point = type(db.point) == "string" and db.point or DEFAULT.point
    local relativePoint = type(db.relativePoint) == "string" and db.relativePoint or point
    bar:ClearAllPoints()
    bar:SetPoint(point, UIParent, relativePoint, tonumber(db.x) or DEFAULT.x, tonumber(db.y) or DEFAULT.y)
end

--- Put the bar where it was left on its own, for the stats window closing.
function SkillBar.Place()
    if bar then
        place()
    end
end

--- Whether the bar is inside the stats window, which moves it then.
local function inWindow()
    return ns.StatsPanel ~= nil and ns.StatsPanel.Attached()
end

local function title()
    local rank, maxRank = ns.Skill.Rank()
    return string.format("%s %d/%d", ns.Fishing.SpellName(), rank, maxRank)
end

--- Whether the bar belongs on screen: switched on, with Fishing learned, and
-- a pole in hand.
local function wanted()
    if not (settings().shown and ns.Skill.Rank()) then
        return false
    end
    return ns.Fishing.PoleEquipped()
end

--- Whether the water in the zone the player is in is too low for their
-- skill: the game refused a cast, or every fish of five casts got away.
local function tooLowHere()
    local zone = ns.Water and ns.Water.Here()
    return zone ~= nil and ns.Water.TooLowFor(zone.id, ns.Skill.Effective()) ~= nil
end

local function countColour(colour)
    bar.count:SetTextColor(colour[1], colour[2], colour[3])
end

--- Draw the bar from the skill and the count.
local function draw()
    bar.label:SetText(title())
    if tooLowHere() then
        countColour(REFUSED)
        bar.count:SetText("too low here")
        return
    end
    countColour(WHITE)
    if ns.Skill.Capped() then
        bar:SetStatusBarColor(CAPPED[1], CAPPED[2], CAPPED[3])
        bar:SetValue(1)
        bar.count:SetText("capped")
        return
    end

    local rank = ns.Skill.Rank()
    local catches = ns.Skill.Catches()
    local expected = ns.Skill.Expected(rank)
    bar:SetStatusBarColor(COLOUR[1], COLOUR[2], COLOUR[3])
    -- The fill alone says how close the next point is; the words were
    -- clutter. The count is in the tooltip, and in the stats window's row.
    bar:SetValue(math.min(1, catches / expected))
    bar.count:SetText("")
end

--- Draw the bar, or hide it, and have the stats window follow it.
function SkillBar.Refresh()
    if not bar then
        return
    end
    local show = wanted()
    bar:SetShown(show)
    if show then
        draw()
    end
    if ns.StatsPanel and ns.StatsPanel.Sync then
        ns.StatsPanel.Sync(show)
    end
end

--- Short: the skill, and where the rest is. The count, the chance of a
-- point and the water here are in the stats window, under its rows.
local function showTooltip(self)
    if not (ns.Skill.Rank() and GameTooltip) then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(title())
    GameTooltip:AddLine("Click to open or close your fishing stats.", 0.7, 0.7, 0.7, true)
    if not settings().locked then
        GameTooltip:AddLine("Drag to move it.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

local function create()
    bar = CreateFrame("StatusBar", "FishingForeverSkillBar", UIParent)
    bar:SetSize(WIDTH, HEIGHT)
    bar:SetStatusBarTexture(TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.6)
    bar.background = background

    -- The tooltip's own thin border, where the client has the template.
    local ok, border = pcall(CreateFrame, "Frame", nil, bar, "BackdropTemplate")
    if ok and border and border.SetBackdrop then
        border:SetPoint("TOPLEFT", -3, 3)
        border:SetPoint("BOTTOMRIGHT", 3, -3)
        border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
        border:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        bar.border = border
    end

    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 6, 0)
    bar.label = label

    local count = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("RIGHT", -6, 0)
    bar.count = count

    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    -- A click shows or hides the stats under the bar; a drag moves it, and
    -- is not a click when the button comes up.
    bar:SetScript("OnMouseDown", function(self)
        self.dragged = false
    end)
    bar:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and not self.dragged and ns.StatsPanel then
            ns.StatsPanel.Toggle()
        end
    end)
    -- Inside the stats window, the drag moves the window, bar and all.
    bar:SetScript("OnDragStart", function(self)
        self.dragged = true
        if inWindow() then
            ns.StatsPanel.StartMoving()
            return
        end
        if settings().locked then
            return
        end
        self:StartMoving()
    end)
    bar:SetScript("OnDragStop", function(self)
        if inWindow() then
            ns.StatsPanel.StopMoving()
            return
        end
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        local db = settings()
        db.point, db.relativePoint, db.x, db.y = point, relativePoint, x, y
    end)
    bar:SetScript("OnEnter", showTooltip)
    bar:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    place()
end

function SkillBar.SetShown(value)
    settings().shown = value and true or false
    SkillBar.Refresh()
    changed()
end

function SkillBar.SetLocked(value)
    settings().locked = value and true or false
    changed()
end

--- Put the bar back where it starts: under the middle of the screen.
function SkillBar.ResetPosition()
    local db = settings()
    db.point, db.relativePoint, db.x, db.y = DEFAULT.point, DEFAULT.relativePoint, DEFAULT.x, DEFAULT.y
    if bar then
        -- Out of the stats window, placed, and back in it, opened there.
        if ns.StatsPanel then
            ns.StatsPanel.Detach()
        end
        place()
        SkillBar.Refresh()
    end
end

ns.RegisterCommand("bar", "Hide or show the skill bar; /ff bar lock locks it, /ff bar reset puts it back",
    function(rest)
        local word = (rest or ""):lower()
        if word == "lock" then
            SkillBar.SetLocked(not settings().locked)
            ns.Print(settings().locked and "Skill bar locked." or "Skill bar unlocked: drag it to move it.")
        elseif word == "reset" then
            SkillBar.ResetPosition()
            ns.Print("Skill bar back in its place.")
        else
            SkillBar.SetShown(not settings().shown)
            ns.Print(settings().shown and "Skill bar shown while a pole is equipped." or "Skill bar hidden.")
        end
    end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
-- Another zone, another water: "too low here" belongs to the one it was said in.
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("ZONE_CHANGED")
events:SetScript("OnEvent", function()
    SkillBar.Refresh()
end)

ns.OnLogin(function()
    create()
    SkillBar.Refresh()
end)
