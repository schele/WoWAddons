local addonName, ns = ...

-- The threat window: a row per person on the threat list of the mob you are
-- fighting, each a bar filled to how close they are to pulling aggro (100%
-- pulls), in their class colour, the most threat first.

local Window = {}
ns.Window = Window

ns.AddDefaults({
    shown = true,
    -- A threat meter says nothing out of combat, so it waits for one.
    combatOnly = true,
    window = { point = "CENTER", relativePoint = "CENTER", x = 360, y = -120 },
})

local WIDTH = 230
local ROW_HEIGHT = 18
local ROW_GAP = 2
local MAX_ROWS = 10
local TOP = 52 -- the title bar and the mob's name above the first row
local BOTTOM = 26 -- room for the footer under the last row
local LOGO = 16 -- the glyph before the name, sized to the title bar
local LOGO_GAP = 6
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
-- A pet, or anyone else the client gives no class colour.
local PLAIN = { r = 0.6, g = 0.6, b = 0.6 }

-- With a part per mob and more than one mob shown, each shows this many.
local SPLIT_ROWS = 5
-- A mob's heading, from the top of its part; and the space between parts.
local HEADER_Y = 30
local PART_GAP = 8
-- One line of the small font at the bottom, which BOTTOM leaves room for.
local FOOTER_LINE = 12

Window.MAX_ROWS = MAX_ROWS
Window.SPLIT_ROWS = SPLIT_ROWS
Window.rows = {}
Window.headers = {}

local frame

--- CreateFrame with a template, or without it on a client that lacks it.
local function createFrame(kind, name, parent, template)
    local ok, created = pcall(CreateFrame, kind, name, parent, template)
    if ok and created then
        return created
    end
    return CreateFrame(kind, name, parent)
end

-- The window's frame, as BossLoot's, BankBags' and LFGBoard's: the options
-- window's own, the name in its title bar and its red X, so this reads as
-- one of the game's windows. On a client without it, the dialog border, a
-- name and a close button of our own. Solid either way.
local function createWindowFrame()
    local ok, made = pcall(CreateFrame, "Frame", "ThreatForeverFrame", UIParent, "SettingsFrameTemplate")
    if not (ok and made) then
        made = createFrame("Frame", "ThreatForeverFrame", UIParent, "BackdropTemplate")
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
    made.title:SetText("Threat Forever")

    made.logo = (native and made.NineSlice or made):CreateTexture(nil, "OVERLAY")
    made.logo:SetSize(LOGO, LOGO)
    made.logo:SetPoint("RIGHT", made.title, "LEFT", -LOGO_GAP, 0)
    made.logo:SetTexture("Interface\\AddOns\\ThreatForever\\logo")

    -- Our own, not the game's: that asks the window manager, which an addon
    -- may not do in combat.
    made.close:SetScript("OnClick", function()
        ns.settings.shown = false
        Window.Refresh()
        ns.Refresh()
        ns.Print("Threat window off. Type /threat to bring it back.")
    end)
    return made
end

--- A row: placed where it goes each time the window is drawn.
local function makeRow()
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(WIDTH - 24, ROW_HEIGHT)

    row.back = row:CreateTexture(nil, "BACKGROUND")
    row.back:SetAllPoints(row)
    row.back:SetColorTexture(0, 0, 0, 0.5)

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetAllPoints(row)
    row.bar:SetStatusBarTexture(BAR_TEXTURE)
    row.bar:SetMinMaxValues(0, 100)

    row.name = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name:SetJustifyH("LEFT")

    row.amount = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.amount:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.amount:SetJustifyH("RIGHT")

    row:Hide()
    return row
end

local function savePosition(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    local saved = ns.settings.window
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

local function create()
    frame = createWindowFrame()
    Window.frame = frame
    frame:SetSize(WIDTH, TOP + ROW_HEIGHT + BOTTOM)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", savePosition)
    local saved = ns.settings.window
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)

    -- The first mob's heading: your target, or that none is.
    frame.mob = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.mob:SetJustifyH("LEFT")
    frame.mob:SetWordWrap(false)
    Window.headers[1] = frame.mob

    -- Held at both ends, so a long line wraps inside the window instead of
    -- running out past its edge.
    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 10)
    frame.footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 10)
    frame.footer:SetJustifyH("LEFT")
    frame.footer:SetWordWrap(true)
    frame.footer:SetText("")

    for index = 1, MAX_ROWS do
        Window.rows[index] = makeRow()
    end
    frame:Hide()
end

--- The `index`th mob's heading, made the first time a part needs one.
local function headerAt(index)
    local header = Window.headers[index]
    if not header then
        header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetJustifyH("LEFT")
        header:SetWordWrap(false)
        Window.headers[index] = header
    end
    return header
end

--- The `index`th row in the window, made the first time it is needed.
local function rowAt(index)
    local row = Window.rows[index]
    if not row then
        row = makeRow()
        Window.rows[index] = row
    end
    return row
end

local function classColor(classFile)
    local colors = RAID_CLASS_COLORS
    return (classFile and colors and colors[classFile]) or PLAIN
end

-- Words for where the number cannot be written: on a boss, when the game
-- will not format its secret.
local function stateWord(data)
    if data.tanking then
        return "Tanking"
    elseif data.status == 1 then
        return "Over tank"
    end
    return ""
end

local function drawRow(row, data)
    local color = classColor(data.classFile)
    row.bar:SetStatusBarColor(color.r, color.g, color.b, 0.85)
    if not pcall(row.name.SetText, row.name, data.name) then
        row.name:SetText("?")
    end

    -- A secret number is handed straight on: a status bar draws one, and the
    -- game may format one into text. Where it will not, the state stands in.
    if not pcall(row.bar.SetValue, row.bar, data.scaled) then
        row.bar:SetValue(0)
    end
    if not pcall(row.amount.SetFormattedText, row.amount, "%.0f%%", data.scaled) then
        row.amount:SetText(stateWord(data))
    end
    row:Show()
end

local function drawMob(header, list)
    if not list.mob then
        header:SetText("No enemy targeted")
        return
    end
    -- A mob's name can come secret too; the game writes one where it can.
    if not pcall(header.SetText, header, list.name) then
        header:SetText(list.mob == "target" and "Your target" or "An enemy")
    end
end

--- Whether the window should be up: turned on, and in combat unless it is
-- told to stay up.
function Window.Wanted()
    if ns.Threat.InDemo() then
        return true
    end
    return ns.settings.shown and (not ns.settings.combatOnly or ns.Threat.InCombat())
end

function Window.Refresh()
    if not frame then
        return
    end
    if not Window.Wanted() then
        frame:Hide()
        return
    end

    -- Each mob's part, top to bottom: its heading, then its rows. One mob
    -- has all the rows; with more, each has a share.
    local lists = ns.Threat.All()
    local perMob = #lists > 1 and SPLIT_ROWS or MAX_ROWS
    local y, used, secret = -HEADER_Y, 0, false
    for index, list in ipairs(lists) do
        local header = headerAt(index)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, y)
        header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, y)
        drawMob(header, list)
        header:Show()
        y = y - (TOP - HEADER_Y)

        local count = math.min(#list.rows, perMob)
        for position = 1, count do
            used = used + 1
            local row = rowAt(used)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, y)
            drawRow(row, list.rows[position])
            y = y - (ROW_HEIGHT + ROW_GAP)
        end
        if count == 0 then
            y = y - (ROW_HEIGHT + ROW_GAP)
        end
        y = y - PART_GAP
        secret = secret or list.secret
    end
    for index = #lists + 1, #Window.headers do
        Window.headers[index]:Hide()
    end
    for index = used + 1, #Window.rows do
        Window.rows[index]:Hide()
    end

    if ns.Threat.InDemo() then
        frame.footer:SetText("Made-up numbers. /threat demo ends it.")
    else
        frame.footer:SetText(secret and "The game hides the numbers on this one." or "")
    end
    -- BOTTOM has room for one line; a line that wraps gets the rest.
    local extra = 0
    if frame.footer:GetText() ~= "" then
        extra = math.max(0, (frame.footer:GetStringHeight() or 0) - FOOTER_LINE)
    end
    frame:SetHeight(-y + PART_GAP + BOTTOM + extra)
    frame:Show()
end

--- /threat: turn the window on or off.
local function toggle()
    ns.settings.shown = not ns.settings.shown
    Window.Refresh()
    ns.Refresh()
    if not ns.settings.shown then
        ns.Print("Threat window off.")
    elseif ns.settings.combatOnly and not ns.Threat.InCombat() then
        ns.Print("Threat window on. It shows when you are in combat.")
    else
        ns.Print("Threat window on.")
    end
end

ns.DefaultCommand = toggle

ns.Threat.OnUpdate(Window.Refresh)
ns.OnRefresh(Window.Refresh)

ns.OnLogin(function()
    create()
    Window.Refresh()
end)
