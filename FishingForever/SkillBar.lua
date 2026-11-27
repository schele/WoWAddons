local addonName, ns = ...

-- A bar for the Fishing skill, in two halves. The left is the next point: the
-- catches since the last point against how many a point takes (Skill.lua),
-- where "too low here" says the game refused a cast and "capped" says the
-- skill is at its cap. The right is the skill itself against its cap. Shown
-- while a pole is equipped. Dragged to move it, unless locked. Its tooltip is
-- short; the count and what the numbers mean are in the stats window
-- (StatsPanel.lua), which a click opens around it.

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
-- The next point is FishingForever's own blue, as in its chat prefix; the
-- skill is green; both are grey at the cap.
local BLUE = { 0.4, 0.8, 1 }
local GREEN = { 0.3, 0.75, 0.35 }
local CAPPED = { 0.5, 0.5, 0.5 }
-- The left half's words: white, or the game's error red where it refused a cast.
local WHITE = { 1, 1, 1 }
local REFUSED = { 1, 0.3, 0.3 }
-- Room before a label's first letter.
local LABEL_INSET = 6
-- The highest rank of Fishing: a cap of this, reached, is the end of it. A
-- lower cap reached is a trainer's, and a reason to go and train.
local FINAL_CAP = 300

local bar
-- What the bar last drew, which its halves are laid out for again when the
-- stats window widens or narrows it.
local shownMode = "both"

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

--- How full a fill is, from 0 to 1. A whole below 1 counts as 1, so a cap of
-- 0, or an average of no catches, is never a division by zero.
local function fraction(value, whole)
    return math.min(1, value / math.max(whole, 1))
end

local function setFill(fill, value, colour)
    fill:SetValue(value)
    fill:SetStatusBarColor(colour[1], colour[2], colour[3])
end

--- What the bar shows: "both" halves, the "skill" alone, or only the "strip"
-- of words. The next point has nothing to say while every catch raises the
-- skill, as it does early on, unless a warning or a trainer's cap has
-- something to say about it. At the last rank there is nothing left to show
-- but the words, which are still a click away from the stats.
local function mode()
    local rank, maxRank = ns.Skill.Rank()
    -- A warning is worth saying at any skill, the last rank included.
    if tooLowHere() then
        return "both"
    end
    if ns.Skill.Capped() then
        return maxRank >= FINAL_CAP and "strip" or "both"
    end
    if ns.Skill.Expected(rank) <= 1 then
        return "skill"
    end
    return "both"
end

--- Put the halves where `mode` has them, from the bar's width now: with both,
-- the left half takes half the bar and the right the rest; the skill alone
-- takes it all; the strip has no fills, only its words at the bar's edge.
local function layout(mode)
    shownMode = mode
    local width = bar:GetWidth()
    local both = mode == "both"
    local strip = mode == "strip"
    local half = math.floor(width / 2)
    local left, right = bar.pointFill, bar.skillFill

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", bar, "TOPLEFT")
    left:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT")
    left:SetWidth(half)
    left:SetShown(both)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", bar, "TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
    right:SetWidth(both and width - half or width)
    right:SetShown(not strip)

    bar.divider:ClearAllPoints()
    bar.divider:SetPoint("TOPLEFT", right, "TOPLEFT")
    bar.divider:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT")
    bar.divider:SetShown(both)

    bar.pointLabel:ClearAllPoints()
    bar.pointLabel:SetPoint("LEFT", left, "LEFT", LABEL_INSET, 0)
    bar.pointLabel:SetShown(both)
    bar.skillLabel:ClearAllPoints()
    bar.skillLabel:SetPoint("LEFT", strip and bar or right, "LEFT", LABEL_INSET, 0)
end

--- Draw the bar from the skill and the count.
local function draw()
    local rank, maxRank = ns.Skill.Rank()
    local capped = ns.Skill.Capped()
    layout(mode())

    -- The left half: the next point, or what stops one.
    local words, wordsColour = "Next point", WHITE
    if tooLowHere() then
        words, wordsColour = "too low here", REFUSED
    elseif capped then
        words = "capped"
    end
    bar.pointLabel:SetText(words)
    bar.pointLabel:SetTextColor(wordsColour[1], wordsColour[2], wordsColour[3])

    -- The fill alone says how close the next point is. The count is in the
    -- tooltip, and in the stats window's row. A warning leaves it as it is.
    if capped then
        setFill(bar.pointFill, 1, CAPPED)
        setFill(bar.skillFill, fraction(rank, maxRank), CAPPED)
    else
        local expected = ns.Skill.Expected(rank)
        setFill(bar.pointFill, fraction(ns.Skill.Catches(), expected), BLUE)
        setFill(bar.skillFill, fraction(rank, maxRank), GREEN)
    end
    bar.skillLabel:SetText(title())
end

--- Keep the fills and the words in their order over the bar, whatever level
-- the bar is at: the fills just over it, the words over the fills. The stats
-- window raises the bar over itself, and not every client carries a parent's
-- new level down to its children.
local function levels()
    local level = bar:GetFrameLevel()
    bar.pointFill:SetFrameLevel(level + 1)
    bar.skillFill:SetFrameLevel(level + 1)
    bar.overlay:SetFrameLevel(level + 3)
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
    -- After the window has taken the bar or given it back, which sets its level.
    levels()
end

-- What the halves showing are, for the tooltip: none, at the last rank.
local HALVES = {
    both = "Left: catches toward your next skill point. Right: your skill against its cap.",
    skill = "Your skill against its cap.",
}

--- Short: the skill, what the halves are, and where the rest is. The count,
-- the chance of a point and the water here are in the stats window, under its
-- rows.
local function showTooltip(self)
    if not (ns.Skill.Rank() and GameTooltip) then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(title())
    local halves = HALVES[mode()]
    if halves then
        GameTooltip:AddLine(halves, 0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine("Click to open or close your fishing stats.", 0.7, 0.7, 0.7, true)
    if not settings().locked then
        GameTooltip:AddLine("Drag to move it.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

--- One half's fill, a child of the bar. It takes no mouse, so a click or a
-- drag on it reaches the bar.
local function createFill()
    local fill = CreateFrame("StatusBar", nil, bar)
    fill:SetStatusBarTexture(TEXTURE)
    fill:SetMinMaxValues(0, 1)
    fill:SetValue(0)
    fill:EnableMouse(false)
    return fill
end

local function create()
    bar = CreateFrame("Frame", "FishingForeverSkillBar", UIParent)
    bar:SetSize(WIDTH, HEIGHT)

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

    bar.pointFill = createFill()
    bar.skillFill = createFill()

    -- The words and the divider sit on a frame of their own above the fills:
    -- a child frame is drawn over its parent's own text, so words on the bar
    -- itself would be hidden behind them.
    local overlay = CreateFrame("Frame", nil, bar)
    overlay:SetAllPoints()
    bar.overlay = overlay
    levels()

    local divider = overlay:CreateTexture(nil, "OVERLAY")
    divider:SetColorTexture(0, 0, 0, 1)
    divider:SetWidth(1)
    bar.divider = divider

    bar.pointLabel = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.skillLabel = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

    -- The stats window widens the bar: the halves follow it.
    bar:SetScript("OnSizeChanged", function()
        layout(shownMode)
    end)
    layout(shownMode)

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
