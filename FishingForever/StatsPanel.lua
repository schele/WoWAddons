local addonName, ns = ...

-- The fishing stats window. A click on the skill bar opens it around the
-- bar: the bar moves inside, across the top under the title, without
-- moving on the screen, and the window hangs under it. Another click, or
-- the red X, closes it and leaves the bar on its own where it was. Dragging
-- either moves both. It goes with the bar when the pole comes off.
--
-- One zone at a time, the zone fished in now to begin with, and the
-- spellbook's page arrows to turn to the others. Its level, coloured as the
-- world map colours it against the character's. The totals, a row for each
-- skill (the skill you are at in gold) with the share of casts that landed a
-- fish, and the fish caught there as the loot window lists them: icon, name
-- in its quality's colour, count, and the item's own tooltip. A skill's row
-- has its fish, points, subzones and any lure's bonus in its tooltip.

local StatsPanel = {}
ns.StatsPanel = StatsPanel

local WIDTH = 330
local INSET = 16 -- from the window's sides to what is in it
local BAR_TOP = 30 -- the bar, under the title
local BAR_HEIGHT = 18
local CONTENT_TOP = BAR_TOP + BAR_HEIGHT + 8 -- the zone's name, under the bar
local LOGO, LOGO_GAP = 16, 6
local ZONE_HEIGHT = 30
local TOTALS_HEIGHT = 40
local HEAD_HEIGHT = 18
local LINE = 16 -- a skill's row
local ROWS = 10 -- skill rows on view; the mouse wheel scrolls through the rest
local FISH_LINE = 20
local FISH_ROWS = 6 -- fish listed; the rest are counted under them
local GAP = 10
local BOTTOM = 14

local INNER = WIDTH - INSET * 2
-- The skill's column, then the others, each right-aligned to its edge.
local SKILL_X = 8
local COLUMNS = {
    { key = "caught", label = "Caught", right = 110 },
    { key = "away", label = "Got away", right = 175 },
    { key = "refused", label = "Refused", right = 238 },
    { key = "landed", label = "Landed", right = INNER - 8 },
}

-- Each column's colour: what was caught in green, what got away in orange,
-- what was refused in red, the share landed in FishingForever's blue; a nought,
-- or no share, in grey.
local COLOURS = {
    caught = { 0.3, 1, 0.3 },
    away = { 1, 0.6, 0.2 },
    refused = { 1, 0.3, 0.3 },
    landed = { 0.4, 0.8, 1 },
}
local NOUGHT = { 0.5, 0.5, 0.5 }
local GOLD = { 1, 0.82, 0 }
local WHITE = { 1, 1, 1 }
local RED = { 1, 0.3, 0.3 }
local LABEL = { 0.8, 0.8, 0.8 }
-- Casts seen in a zone before FishingForever says how many fish land there.
local MEASURED_CASTS = 10

local panel
local attached = false -- whether the bar is inside the window
local selected -- the zone shown, by map ID; nil for the zone fished in now
local offset = 0 -- the first skill row on view

function StatsPanel.Frame()
    return panel
end

--- Whether the window is open with the bar inside it.
function StatsPanel.Attached()
    return attached
end

local function settings()
    return ns.db.skillBar
end

local function paint(fontString, colour)
    fontString:SetTextColor(colour[1], colour[2], colour[3])
end

--- The share of casts that landed a fish, as "86%", or "-" without a cast
-- that got as far as a bite.
local function landed(data)
    local casts = data.caught + data.away
    if casts == 0 then
        return "-", 0
    end
    return string.format("%d%%", math.floor(data.caught / casts * 100 + 0.5)), casts
end

--- Fill a column's text: a count in its colour, or a grey nought.
local function show(fontString, key, data)
    local text, value
    if key == "landed" then
        text, value = landed(data)
    else
        value = data[key]
        text = tostring(value)
    end
    fontString:SetText(text)
    paint(fontString, value > 0 and COLOURS[key] or NOUGHT)
end

--- The zones the arrows turn through: the one the player is in first, though
-- nothing is fished there yet, then the ones fished, the latest first.
local function zonePages()
    local zones = ns.Stats.Zones()
    local here = ns.Water and ns.Water.Here()
    if here then
        for _, id in ipairs(zones) do
            if id == here.id then
                return zones
            end
        end
        table.insert(zones, 1, here.id)
    end
    return zones
end

--- The zone to show: the one chosen with the arrows, or the one the player
-- is in, or the one fished in last.
local function zoneShown()
    if selected then
        return selected
    end
    local here = ns.Water and ns.Water.Here()
    return here and here.id or ns.Stats.Zones()[1]
end

local function hideTooltip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

local function plural(value, one, many)
    return string.format("%d %s", value, value == 1 and one or many)
end

local function rowTooltip(row)
    local data = row.data
    if not (data and GameTooltip) then
        return
    end
    local function line(text, grey)
        local shade = grey and 0.7 or 1
        GameTooltip:AddLine(text, shade, shade, shade, true)
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(string.format("%s, %s", panel.zoneName or "Here", row.skill:GetText()))
    line(string.format("%d caught, %d got away, %d refused.", data.caught, data.away, data.refused))
    if data.perPoint then
        line(string.format("%s, %.1f catches each (the old rule: %.1f).",
            plural(data.points, "point", "points"), data.perPoint, data.rule))
    end
    if data.caught > 0 then
        line("Fish: " .. ns.Stats.List(data.fish, ns.Stats.ItemName))
    end
    local subs = {}
    for name, value in pairs(data.subs) do
        if name ~= "" then
            subs[name] = value
        end
    end
    if next(subs) then
        line("Where: " .. ns.Stats.List(subs), true)
    end
    local bonuses = {}
    for bonus, value in pairs(data.bonus) do
        if bonus ~= 0 then
            bonuses[string.format("%+d", bonus)] = value
        end
    end
    if next(bonuses) then
        line("With a lure or gear: " .. ns.Stats.List(bonuses) .. " casts", true)
    end
    if next(data.levels) then
        line("Character level: " .. ns.Stats.List(data.levels), true)
    end
    GameTooltip:Show()
end

local function rounded(value)
    return math.floor(value + 0.5)
end

--- The summary under the rows: a line for each thing known, { label, value,
-- colour, tip }. The count since the last point and the chance a catch
-- gives one; a lure's bonus; and in the zone the player is in, whether the
-- game refused a cast, the share of casts that landed a fish there, as the
-- rows count it, and so how many casts a point takes. Nothing predicted:
-- the old game's rule for fish getting away does not fit WoW Forever.
local function summary()
    local lines = {}
    local function add(label, value, tip, colour)
        lines[#lines + 1] = { label = label, value = value, tip = tip, colour = colour }
    end
    local rank, maxRank = ns.Skill.Rank()
    if not rank then
        return lines
    end
    local bonus = ns.Skill.Bonus()
    local skill = rank + bonus
    local here = ns.Water and ns.Water.Here()
    local zone = here and here.name or "this zone"

    local expected
    if ns.Skill.Capped() then
        add("Skill at its cap", string.format("%d/%d", rank, maxRank),
            "No catch can raise it until a trainer raises the cap.")
    else
        -- The catches since the last point are the bar's fill, not a line.
        local source, points
        expected, source, points = ns.Skill.Expected(rank)
        add("Chance of a point per catch", string.format("1 in %d", math.max(1, rounded(expected))),
            source == "measured"
                and string.format("Measured from %d of your points near %d.", points, rank)
                or "The old game's rule: a guess for WoW Forever until FishingForever has measured "
                    .. "five of your points near your skill.")
    end
    if bonus ~= 0 then
        add("Lure or gear bonus", string.format("%+d", bonus),
            string.format("Counts for landing a fish and for a zone's minimum: %d. Points go by your own %d.",
                skill, rank))
    end
    if not here then
        return lines
    end

    local tooLow, detail = ns.Water.TooLowFor(here.id, skill)
    if tooLow == "refused" then
        add("Too low to fish here", string.format("refused at %d", detail),
            string.format("The game refused your cast in %s at %d: \"Skill not high enough\".",
                zone, detail), RED)
        return lines
    elseif tooLow == "away" then
        add("Too low to land fish here", string.format("none of %d landed", detail),
            string.format("Every fish of your %d casts in %s at %d or more got away. The game lets "
                .. "you cast here, but your skill is too low to land a fish.", detail, zone, skill), RED)
        return lines
    end

    -- The share landed, from the same log as the rows: a catch or a fish
    -- that got away is a cast that got as far as a bite.
    local counted = ns.Stats.Zone(here.id)
    local casts = counted.caught + counted.away
    if casts == 0 then
        return lines
    elseif casts < MEASURED_CASTS then
        add("Fish that land here", string.format("%d of %d casts", casts, MEASURED_CASTS),
            string.format("FishingForever needs %d casts in %s before it tells how many fish land.",
                MEASURED_CASTS, zone), NOUGHT)
        return lines
    end
    local landing = counted.caught / casts
    add("Fish that land here", string.format("%d%%", math.floor(landing * 100 + 0.5)),
        string.format("%d of %d casts in %s landed a fish; the rest got away. The rows show it by skill.",
            counted.caught, casts, zone), landing == 0 and RED or nil)
    -- Only where enough fish get away that it is more than the catches: with
    -- one in twenty getting away, it would say the chance's number again.
    if expected and landing > 0 then
        local castsPerPoint = math.max(1, rounded(expected / landing))
        if castsPerPoint ~= math.max(1, rounded(expected)) then
            add("Casts a point takes here", string.format("about %d", castsPerPoint),
                "The catches a point takes, with the fish that get away here.")
        end
    end
    return lines
end

local function statTooltip(row)
    if not (row.tip and GameTooltip) then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.label:GetText())
    GameTooltip:AddLine(row.tip, 1, 1, 1, true)
    GameTooltip:Show()
end

--- CreateFrame with a template, or without it on a client that lacks it.
local function createFrame(kind, name, parent, template)
    local ok, created = pcall(CreateFrame, kind, name, parent, template)
    if ok and created then
        return created
    end
    return CreateFrame(kind, name, parent)
end

-- The window's frame, as BossLoot's, BankBags' and RareMob's: the options
-- window's own, the name in its title bar and its red X, so this reads as one
-- of the game's windows. On a client without it, the dialog border, a name
-- and a close button of our own. Solid either way.
local function createWindowFrame()
    local ok, made = pcall(CreateFrame, "Frame", "FishingForeverStatsPanel", UIParent, "SettingsFrameTemplate")
    if not (ok and made) then
        made = createFrame("Frame", "FishingForeverStatsPanel", UIParent, "BackdropTemplate")
    end
    local native = made.NineSlice and made.NineSlice.Text and made.ClosePanelButton and made.Bg

    if native then
        made.background = made.Bg:CreateTexture(nil, "BACKGROUND", nil, 7)
        made.background:SetAllPoints(made.Bg)
        made.title = made.NineSlice.Text
        made.title:ClearAllPoints()
        made.title:SetPoint("TOP", made, "TOP", (LOGO + LOGO_GAP) / 2, -5)
        made.close = made.ClosePanelButton
    else
        made.background = made:CreateTexture(nil, "BACKGROUND", nil, -8)
        made.background:SetPoint("TOPLEFT", made, "TOPLEFT", 4, -4)
        made.background:SetPoint("BOTTOMRIGHT", made, "BOTTOMRIGHT", -4, 4)
        if made.SetBackdrop then
            made:SetBackdrop({
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
        end
        made.title = made:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        made.title:SetPoint("TOP", made, "TOP", (LOGO + LOGO_GAP) / 2, -14)
        made.close = createFrame("Button", nil, made, "UIPanelCloseButton")
        made.close:SetPoint("TOPRIGHT", made, "TOPRIGHT", -4, -4)
    end
    made.background:SetColorTexture(0.06, 0.045, 0.03, 1)
    made.title:SetText("Fishing stats")

    made.logo = (native and made.NineSlice or made):CreateTexture(nil, "OVERLAY")
    made.logo:SetSize(LOGO, LOGO)
    made.logo:SetPoint("RIGHT", made.title, "LEFT", -LOGO_GAP, 0)
    made.logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\minimap")

    -- Our own, not the game's: that asks the window manager, which an addon
    -- may not do in combat.
    made.close:SetScript("OnClick", function()
        StatsPanel.SetShown(false)
    end)
    return made
end

local function text(parent, font, justify)
    local fontString = parent:CreateFontString(nil, "OVERLAY", font)
    fontString:SetJustifyH(justify or "LEFT")
    if fontString.SetWordWrap then
        fontString:SetWordWrap(false)
    end
    return fontString
end

--- The spellbook's page arrow, `direction` "Prev" or "Next".
local function arrow(direction, step)
    local button = CreateFrame("Button", nil, panel)
    button:SetSize(26, 26)
    local path = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-"
    button:SetNormalTexture(path .. "Up")
    button:SetPushedTexture(path .. "Down")
    button:SetDisabledTexture(path .. "Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", function()
        local zones = zonePages()
        if #zones < 2 then
            return
        end
        local current, at = zoneShown(), 0
        for index, id in ipairs(zones) do
            if id == current then
                at = index
            end
        end
        selected = zones[((at - 1 + step) % #zones) + 1]
        offset = 0
        StatsPanel.Refresh()
    end)
    return button
end

local function makeTotal(key, label, index)
    local width = INNER / #COLUMNS
    local x = INSET + (index - 1) * width
    local number = text(panel, "GameFontHighlightLarge", "CENTER")
    number:SetPoint("TOP", panel, "TOPLEFT", x + width / 2, -(CONTENT_TOP + ZONE_HEIGHT))
    local name = text(panel, "GameFontDisableSmall", "CENTER")
    name:SetPoint("TOP", number, "BOTTOM", 0, -3)
    name:SetText(label)
    panel.totals[key] = number
end

local function makeRow(index)
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(INNER, LINE)
    row:SetPoint("TOPLEFT", panel.head, "BOTTOMLEFT", 0, -(index - 1) * LINE)
    -- Every other row a shade lighter, as the game's lists are.
    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.05)
    end
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.skill = text(row, "GameFontHighlightSmall")
    row.skill:SetPoint("LEFT", row, "LEFT", SKILL_X, 0)
    for _, column in ipairs(COLUMNS) do
        local cell = text(row, "GameFontHighlightSmall", "RIGHT")
        cell:SetPoint("RIGHT", row, "LEFT", column.right, 0)
        row[column.key] = cell
    end
    row:SetScript("OnEnter", rowTooltip)
    row:SetScript("OnLeave", hideTooltip)
    return row
end

local function itemIcon(id)
    return ns.Guarded(function()
        if C_Item and C_Item.GetItemIconByID then
            return C_Item.GetItemIconByID(id)
        end
        return GetItemIcon and GetItemIcon(id)
    end) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function itemColour(id)
    return ns.Guarded(function()
        local quality = C_Item.GetItemQualityByID(id)
        local colour = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        return colour and { colour.r, colour.g, colour.b }
    end) or WHITE
end

local function makeStatRow(index)
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(INNER, LINE)
    row:SetPoint("TOPLEFT", panel.summaryHead, "BOTTOMLEFT", 0, -4 - (index - 1) * LINE)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.label = text(row, "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row, "LEFT", SKILL_X, 0)
    paint(row.label, LABEL)
    row.value = text(row, "GameFontHighlightSmall", "RIGHT")
    row.value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row:SetScript("OnEnter", statTooltip)
    row:SetScript("OnLeave", hideTooltip)
    return row
end

--- "Summary" under the rows. Returns how many lines it has.
local function fillSummary()
    local lines = summary()
    for index, entry in ipairs(lines) do
        local row = panel.statRows[index] or makeStatRow(index)
        panel.statRows[index] = row
        row.label:SetText(entry.label)
        row.value:SetText(entry.value)
        paint(row.value, entry.colour or WHITE)
        row.tip = entry.tip
        row:Show()
    end
    for index = #lines + 1, #panel.statRows do
        panel.statRows[index].tip = nil
        panel.statRows[index]:Hide()
    end
    return #lines
end

local function makeFishRow(index)
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(INNER, FISH_LINE)
    row:SetPoint("TOPLEFT", panel.fishHead, "BOTTOMLEFT", 0, -4 - (index - 1) * FISH_LINE)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(FISH_LINE - 2, FISH_LINE - 2)
    row.icon:SetPoint("LEFT", row, "LEFT", SKILL_X - 2, 0)
    row.name = text(row, "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.count = text(row, "GameFontHighlightSmall", "RIGHT")
    row.count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row:SetScript("OnEnter", function(self)
        if self.id and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            ns.Guarded(function() GameTooltip:SetItemByID(self.id) end)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", hideTooltip)
    return row
end

--- Start dragging the window, and the bar in it, unless the bar is locked.
function StatsPanel.StartMoving()
    if panel and not settings().locked then
        panel:StartMoving()
    end
end

--- Stop dragging, and remember where the bar inside was left: it stays there
-- when the window closes.
function StatsPanel.StopMoving()
    if not panel then
        return
    end
    panel:StopMovingOrSizing()
    local x, y = ns.SkillBar.Frame():GetCenter()
    if x and y then
        local db = settings()
        db.point, db.relativePoint, db.x, db.y = "CENTER", "BOTTOMLEFT", x, y
    end
end

local function create()
    panel = createWindowFrame()
    panel:SetSize(WIDTH, 200)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", StatsPanel.StartMoving)
    panel:SetScript("OnDragStop", StatsPanel.StopMoving)

    panel.prev = arrow("Prev", -1)
    panel.prev:SetPoint("TOPLEFT", panel, "TOPLEFT", INSET - 4, -(CONTENT_TOP - 2))
    panel.next = arrow("Next", 1)
    panel.next:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -INSET + 4, -(CONTENT_TOP - 2))
    panel.zone = text(panel, "GameFontNormalLarge", "CENTER")
    panel.zone:SetPoint("TOP", panel, "TOP", 0, -(CONTENT_TOP + 4))
    panel.zone:SetWidth(INNER - 60)

    panel.totals = {}
    for index, column in ipairs(COLUMNS) do
        makeTotal(column.key, column.label, index)
    end

    -- The column heads, gold on a dark strip with a gold rule under it.
    local head = CreateFrame("Frame", nil, panel)
    head:SetSize(INNER, HEAD_HEIGHT)
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", INSET, -(CONTENT_TOP + ZONE_HEIGHT + TOTALS_HEIGHT))
    local strip = head:CreateTexture(nil, "BACKGROUND")
    strip:SetAllPoints()
    strip:SetColorTexture(0, 0, 0, 0.5)
    local rule = head:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT")
    rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.4)
    local skillHead = text(head, "GameFontNormalSmall")
    skillHead:SetPoint("LEFT", head, "LEFT", SKILL_X, 0)
    skillHead:SetText("Skill")
    for _, column in ipairs(COLUMNS) do
        local label = text(head, "GameFontNormalSmall", "RIGHT")
        label:SetPoint("RIGHT", head, "LEFT", column.right, 0)
        label:SetText(column.label)
    end
    panel.head = head

    panel.rows = {}
    for index = 1, ROWS do
        panel.rows[index] = makeRow(index)
    end

    panel.empty = text(panel, "GameFontDisable", "CENTER")
    panel.empty:SetPoint("TOP", head, "BOTTOM", 0, -8)
    panel.empty:SetText("Nothing fished here yet.")

    -- "Summary" and "Fish caught here", gold, as the game heads a
    -- section.
    panel.summaryHead = CreateFrame("Frame", nil, panel)
    panel.summaryHead:SetSize(INNER, HEAD_HEIGHT)
    panel.summaryHead.label = text(panel.summaryHead, "GameFontNormal")
    panel.summaryHead.label:SetPoint("LEFT", panel.summaryHead, "LEFT", SKILL_X - 2, 0)
    panel.summaryHead.label:SetText("Summary")
    panel.statRows = {}

    panel.fishHead = CreateFrame("Frame", nil, panel)
    panel.fishHead:SetSize(INNER, HEAD_HEIGHT)
    local fishLabel = text(panel.fishHead, "GameFontNormal")
    fishLabel:SetPoint("LEFT", panel.fishHead, "LEFT", SKILL_X - 2, 0)
    fishLabel:SetText("Fish caught here")
    panel.fishRows = {}
    panel.more = text(panel, "GameFontDisableSmall")

    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        StatsPanel.Refresh()
    end)
    panel:Hide()
end

--- Open the window around the bar: where the bar is on the screen, the bar
-- stays, inside the window and as wide as its inside.
local function attach()
    local bar = ns.SkillBar.Frame()
    local x = bar:GetCenter()
    local top = bar:GetTop()
    panel:ClearAllPoints()
    if x and top then
        panel:SetPoint("TOP", UIParent, "BOTTOMLEFT", x, top + BAR_TOP)
    else
        panel:SetPoint("TOP", UIParent, "CENTER", 0, 0)
    end
    bar:SetParent(panel)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", panel, "TOPLEFT", INSET, -BAR_TOP)
    bar:SetWidth(INNER)
    -- Over the window's background and border, which sit at its own level.
    bar:SetFrameLevel(panel:GetFrameLevel() + 5)
    -- The window is its frame now.
    if bar.border then
        bar.border:Hide()
    end
    attached = true
    panel:Show()
end

--- Close the window and give the bar back to the screen, where it was.
local function detach()
    local bar = ns.SkillBar.Frame()
    attached = false
    panel:Hide()
    bar:SetParent(UIParent)
    bar:SetWidth(ns.SkillBar.WIDTH)
    if bar.border then
        bar.border:Show()
    end
    ns.SkillBar.Place()
end

--- Take the bar out of the window, if it is in, as a reset of its place
-- needs; the next Sync puts it back.
function StatsPanel.Detach()
    if panel and attached then
        detach()
    end
end

--- Follow the bar: open around it while it shows and the stats are wanted,
-- closed otherwise. The skill bar calls this each time it is drawn.
function StatsPanel.Sync(barShown)
    if not panel then
        return
    end
    local wanted = barShown and settings().stats
    if wanted then
        if not attached then
            attach()
        end
        StatsPanel.Refresh()
    elseif attached then
        detach()
    else
        panel:Hide()
    end
end

--- The zone's level range, coloured as the world map colours it against
-- the character's level, or "" where the map has none.
local function levelText(zone)
    if not (zone.zlo and zone.zhi) then
        return ""
    end
    local range = zone.zlo == zone.zhi and tostring(zone.zhi) or string.format("%d-%d", zone.zlo, zone.zhi)
    local colour = ns.Guarded(function()
        local level = UnitLevel("player")
        if level < zone.zlo then
            return GetQuestDifficultyColor(zone.zlo)
        elseif level > zone.zhi then
            return GetQuestDifficultyColor(zone.zhi - 2)
        end
        return QuestDifficultyColors.difficult
    end)
    if not (colour and colour.r) then
        return " (" .. range .. ")"
    end
    return string.format(" |cff%02x%02x%02x(%s)|r", colour.r * 255, colour.g * 255, colour.b * 255, range)
end

local function fillFish(zone)
    local ids = {}
    for id in pairs(zone.fish) do
        ids[#ids + 1] = id
    end
    table.sort(ids, function(a, b)
        if zone.fish[a] ~= zone.fish[b] then
            return zone.fish[a] > zone.fish[b]
        end
        return a < b
    end)
    local shown = math.min(#ids, FISH_ROWS)
    for index = 1, shown do
        local row = panel.fishRows[index] or makeFishRow(index)
        panel.fishRows[index] = row
        local id = ids[index]
        row.id = id
        row.icon:SetTexture(itemIcon(id))
        row.name:SetText(ns.Stats.ItemName(id))
        paint(row.name, itemColour(id))
        row.count:SetText("×" .. zone.fish[id])
        row:Show()
    end
    for index = shown + 1, #panel.fishRows do
        panel.fishRows[index].id = nil
        panel.fishRows[index]:Hide()
    end
    local rest = #ids - shown
    panel.more:ClearAllPoints()
    panel.more:SetPoint("TOPLEFT", panel.fishHead, "BOTTOMLEFT", SKILL_X, -4 - shown * FISH_LINE)
    panel.more:SetText(rest > 0 and string.format("and %d more", rest) or "")
    panel.more:SetShown(rest > 0)
    return shown + (rest > 0 and 1 or 0), #ids > 0
end

function StatsPanel.Refresh()
    if not (panel and panel:IsShown()) then
        return
    end
    local id = zoneShown()
    local zone = id and ns.Stats.Zone(id)
        or { rows = {}, fish = {}, caught = 0, away = 0, refused = 0, points = 0 }
    if id and not zone.name then
        zone.name = ns.Guarded(function() return C_Map.GetMapInfo(id).name end)
    end
    panel.zoneName = zone.name
    panel.zone:SetText((zone.name or "Unknown zone") .. levelText(zone))

    for _, column in ipairs(COLUMNS) do
        show(panel.totals[column.key], column.key, zone)
    end

    -- A row for each ten skills; the one you are in now in gold.
    local bands = ns.Stats.Bands(zone.rows)
    local rank = ns.Skill.Rank()
    local here = rank and math.floor(rank / ns.Stats.BAND) * ns.Stats.BAND
    offset = math.min(offset, math.max(0, #bands - ROWS))
    local shownRows = 0
    for index, row in ipairs(panel.rows) do
        local data = bands[offset + index]
        row.data = data
        if data then
            shownRows = index
            row.skill:SetText(data.from == data.to and tostring(data.from)
                or string.format("%d-%d", data.from, data.to))
            paint(row.skill, data.key == here and GOLD or WHITE)
            for _, column in ipairs(COLUMNS) do
                show(row[column.key], column.key, data)
            end
            row:Show()
        else
            row:Hide()
        end
    end
    panel.empty:SetShown(#bands == 0)

    -- Under the rows the summary, then the fish, and the window as tall as
    -- what it lists.
    local listed = math.max(shownRows, #bands == 0 and 2 or 0)
    local height = CONTENT_TOP + ZONE_HEIGHT + TOTALS_HEIGHT + HEAD_HEIGHT + listed * LINE + BOTTOM

    panel.summaryHead:ClearAllPoints()
    panel.summaryHead:SetPoint("TOPLEFT", panel.head, "BOTTOMLEFT", 0, -(listed * LINE + GAP))
    local stats = fillSummary()
    panel.summaryHead:SetShown(stats > 0)
    -- The fish go under whatever is last: the next point's lines, or the rows.
    local above, aboveGap = panel.head, listed * LINE
    if stats > 0 then
        height = height + GAP + HEAD_HEIGHT + 4 + stats * LINE
        above, aboveGap = panel.summaryHead, 4 + stats * LINE
    end

    panel.fishHead:ClearAllPoints()
    panel.fishHead:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -(aboveGap + GAP))
    local fishLines, anyFish = fillFish(zone)
    panel.fishHead:SetShown(anyFish)
    if anyFish then
        height = height + GAP + HEAD_HEIGHT + 4 + fishLines * FISH_LINE
    end
    panel:SetHeight(height)

    local several = #zonePages() > 1
    panel.prev:SetEnabled(several)
    panel.next:SetEnabled(several)
end

function StatsPanel.SetShown(value)
    settings().stats = value and true or false
    ns.SkillBar.Refresh()
    if ns.SettingsPanel then
        ns.SettingsPanel.Refresh()
    end
end

function StatsPanel.Toggle()
    StatsPanel.SetShown(not settings().stats)
end

ns.RegisterCommand("stats", "Show or hide your fishing stats around the skill bar", function()
    StatsPanel.Toggle()
end)

local events = CreateFrame("Frame")
-- Another zone: show the one fished in now.
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function()
    selected, offset = nil, 0
    StatsPanel.Refresh()
end)

ns.OnLogin(function()
    create()
    ns.SkillBar.Refresh()
end)
