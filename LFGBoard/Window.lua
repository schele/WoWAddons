local addonName, ns = ...

-- The board: tabs, the role and level switches, the rows, and Refresh.
-- Drawn again from Posts whenever anything changes while it is open.

local Window = {}
ns.Window = Window

ns.AddDefaults({
    window = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    nearLevel = true,
    -- Quest groups for quests already handed in are no use to the player.
    hideCompleted = true,
})

local WIDTH, HEIGHT = 820, 460
local ROW_HEIGHT = 28
local LOGO = 16 -- the glyph before the name, sized to the title bar
local LOGO_GAP = 6
Window.ROWS = 12

local TABS = {
    { key = "all", label = "All" },
    { key = "dungeon", label = "Dungeons" },
    { key = "quest", label = "Quests" },
    { key = "raid", label = "Raids" },
}
local ROLE_SWITCHES = {
    { key = "tank", label = "Tank" },
    { key = "healer", label = "Healer" },
    { key = "dps", label = "Damage" },
}
local ROLE_LETTERS = { tank = "T", healer = "H", dps = "D" }
local SOURCES = { chat = "chat only", finder = "group finder", both = "group finder + chat" }

-- Where the columns start, from a row's left edge.
local AGE_X, WHO_X, WHAT_X, SAID_X, PARTY_X = 8, 50, 172, 300, 516
-- The party column ends where the Whisper button begins, beside the squares
-- or not, so "room for T H D" keeps its last letter.
local PARTY_WIDTH, SQUARES_WIDTH = 194, 96

local frame
local tab = "all"

function Window.Filter()
    return {
        tab = tab,
        roles = ns.Roles(),
        nearLevel = ns.db.nearLevel,
        hideCompleted = ns.db.hideCompleted,
        level = UnitLevel("player"),
    }
end

local function age(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function classHex(class)
    local colour = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    local hex = colour and colour.colorStr
    return type(hex) == "string" and #hex == 8 and hex or nil
end

local function classRGB(class)
    local hex = classHex(class)
    if not hex then
        return 0.5, 0.5, 0.5
    end
    return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

local function letters(roles)
    if not roles then
        return ""
    end
    local parts = {}
    for _, info in ipairs(ROLE_SWITCHES) do
        if roles[info.key] then
            parts[#parts + 1] = ROLE_LETTERS[info.key]
        end
    end
    return table.concat(parts, " ")
end

function Window.What(view)
    if view.activity then
        return ns.Activities.Display(view.activity)
    end
    return view.kind == "quest" and "Quest" or "Other"
end

-- Squares for a listed group of five: one per member, and the open places.
local function squared(view)
    return view.members ~= nil and view.size ~= nil and view.size.of == 5
end

--- The party column's words. Beside a listed group's squares, the roles it
-- has room for; for one from chat, its size and the roles it asks for.
function Window.Party(view)
    local wants = letters(view.roles)
    if squared(view) then
        return wants ~= "" and ("room for " .. wants) or ""
    end

    local parts = {}
    if view.size then
        parts[#parts + 1] = view.size.have .. "/" .. view.size.of
    elseif view.kind == "dungeon" or view.kind == "quest" then
        -- The poster, at least: one who is looking is one in the group.
        parts[#parts + 1] = "1/5"
    end
    if wants ~= "" then
        parts[#parts + 1] = "needs " .. wants
    end
    return table.concat(parts, ", ")
end

-- Classes in the order the game lists them, and the English names for a
-- client that does not give its own.
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_NAMES = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
local REFUSED_HEX = "ff808080"

local function className(class)
    local names = LOCALIZED_CLASS_NAMES_MALE
    local name = names and names[class]
    return type(name) == "string" and name or CLASS_NAMES[class]
end

--- The classes a row asks for, each in its colour, then the ones it turns
-- away, dimmed after "no". Empty when it names none.
function Window.Classes(view)
    local parts = {}
    for _, class in ipairs(CLASS_ORDER) do
        if view.wantClasses and view.wantClasses[class] then
            local hex = classHex(class)
            parts[#parts + 1] = hex and ("|c" .. hex .. className(class) .. "|r") or className(class)
        end
    end
    for _, class in ipairs(CLASS_ORDER) do
        if view.refuseClasses and view.refuseClasses[class] then
            parts[#parts + 1] = "|c" .. REFUSED_HEX .. "no " .. className(class) .. "|r"
        end
    end
    return table.concat(parts, " ")
end

local function savePosition(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    local saved = ns.db.window
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

--- A link in what was said, hovered: its tooltip, as chat shows one.
-- Guarded: the tooltip raises on a link type it does not know.
local function showLink(row, link)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
    if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
end

--- A link in what was said, clicked: what chat does. Shift puts it in an
-- open chat box; otherwise, or with no box open, the game opens it.
local function clickLink(row, link, text, mouseButton)
    if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink and ChatEdit_InsertLink(text) then
        return
    end
    if SetItemRef then
        SetItemRef(link, text, mouseButton, row)
    elseif ChatFrame_OnHyperlinkShow then
        ChatFrame_OnHyperlinkShow(row, link, text, mouseButton)
    end
end

--- Make the links in a row's text work as they do in chat. The row then
-- takes the mouse, so a drag on it is handed on to the window.
local function enableLinks(row)
    if not row.SetHyperlinksEnabled then
        return
    end
    row:SetHyperlinksEnabled(true)
    row:EnableMouse(true)
    row:SetScript("OnHyperlinkEnter", showLink)
    row:SetScript("OnHyperlinkLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    row:SetScript("OnHyperlinkClick", clickLink)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    row:SetScript("OnDragStop", function()
        savePosition(frame)
    end)
end

local function makeRow(index)
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(WIDTH - 32, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -96 - (index - 1) * ROW_HEIGHT)
    enableLinks(row)

    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetSize(3, ROW_HEIGHT - 4)
    row.edge:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.edge:SetColorTexture(0.2, 0.8, 0.2, 1)

    local function text(x, y, width, font)
        local made = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        made:SetPoint("LEFT", row, "LEFT", x, y)
        made:SetWidth(width)
        made:SetJustifyH("LEFT")
        made:SetWordWrap(false)
        return made
    end
    row.age = text(AGE_X, 0, 40)
    row.who = text(WHO_X, 5, 118)
    row.source = text(WHO_X, -7, 118, "GameFontDisableSmall")
    row.what = text(WHAT_X, 0, 124)
    row.said = text(SAID_X, 0, 210)
    row.party = text(PARTY_X, 0, PARTY_WIDTH)
    -- Under the count and roles, as the source is under the name.
    row.classes = text(PARTY_X, -7, PARTY_WIDTH)

    row.slots = {}
    for slot = 1, 5 do
        local texture = row:CreateTexture(nil, "ARTWORK")
        texture:SetSize(16, 16)
        texture:SetPoint("LEFT", row, "LEFT", PARTY_X + (slot - 1) * 18, 0)
        local letter = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        letter:SetPoint("CENTER", texture, "CENTER", 0, 0)
        row.slots[slot] = { texture = texture, letter = letter }
    end

    row.whisper = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.whisper:SetSize(70, 20)
    row.whisper:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.whisper:SetText("Whisper")
    row.whisper:SetScript("OnClick", function()
        if row.view then
            ns.Whisper.Open(row.view)
        end
    end)
    return row
end

local function fill(row, view, now, mine)
    row.view = view
    row.age:SetText(age(now - view.time))
    local hex = classHex(view.class)
    local name = hex and ("|c" .. hex .. view.name .. "|r") or view.name
    row.who:SetText(view.level and (name .. " " .. view.level) or name)
    row.source:SetText(SOURCES[view.source])
    row.what:SetText(Window.What(view))
    row.said:SetText(view.text or "")
    row.edge:SetShown(ns.Posts.WantsMe(view, mine))

    local squares = squared(view)
    for index, slot in ipairs(row.slots) do
        slot.texture:SetShown(squares)
        slot.letter:SetShown(squares)
        if squares then
            local member = view.members[index]
            if member then
                local r, g, b = classRGB(member.class)
                slot.texture:SetColorTexture(r, g, b, 1)
                slot.letter:SetText(member.role and ROLE_LETTERS[member.role] or "")
            else
                slot.texture:SetColorTexture(0.1, 0.08, 0.05, 1)
                slot.letter:SetText("+")
            end
        end
    end

    -- With classes to name, the count and roles move up a line's half to
    -- make room for them below, both beside the squares when there are any.
    local classes = Window.Classes(view)
    local x = squares and (PARTY_X + SQUARES_WIDTH) or PARTY_X
    local width = squares and (PARTY_WIDTH - SQUARES_WIDTH) or PARTY_WIDTH
    row.party:ClearAllPoints()
    row.party:SetPoint("LEFT", row, "LEFT", x, classes ~= "" and 5 or 0)
    row.party:SetWidth(width)
    row.party:SetText(Window.Party(view))
    row.classes:ClearAllPoints()
    row.classes:SetPoint("LEFT", row, "LEFT", x, -7)
    row.classes:SetWidth(width)
    row.classes:SetText(classes)
    row.classes:SetShown(classes ~= "")
    row:Show()
end

local function button(label, width, x, y, onClick)
    local made = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    made:SetSize(width, 22)
    made:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    made:SetText(label)
    made:SetScript("OnClick", onClick)
    return made
end

local function checkbox(label, x, y, onClick)
    local box = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    box:SetSize(22, 22)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.label:SetPoint("LEFT", box, "RIGHT", 2, 0)
    box.label:SetText(label)
    box:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    return box
end

--- CreateFrame with a template, or without it on a client that lacks it.
local function createFrame(kind, name, parent, template)
    local ok, created = pcall(CreateFrame, kind, name, parent, template)
    if ok and created then
        return created
    end
    return CreateFrame(kind, name, parent)
end

-- The window's frame, as BossLoot's and BankBags': the options window's own,
-- the name in its title bar and its red X, so this reads as one of the
-- game's windows. On a client without it, the dialog border, a name and a
-- close button of our own. Solid either way: the options window and the
-- dialog background let the world show through, which the rows of chat
-- cannot bear.
local function createWindowFrame()
    local ok, made = pcall(CreateFrame, "Frame", "LFGBoardFrame", UIParent, "SettingsFrameTemplate")
    if not (ok and made) then
        made = createFrame("Frame", "LFGBoardFrame", UIParent, "BackdropTemplate")
    end
    local native = made.NineSlice and made.NineSlice.Text and made.ClosePanelButton and made.Bg

    if native then
        -- On the game's background, so under its border and title bar too.
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
        if not (made.close.GetNormalTexture and made.close:GetNormalTexture()) then
            made.close:SetText("X")
        end
    end
    made.background:SetColorTexture(0.06, 0.045, 0.03, 1)
    made.title:SetText("LFG Board")

    -- The glyph alone, as the minimap button shows it, before the name: the
    -- AddOns list icon carries a square tile that reads as a sticker here.
    -- Drawn with the name, so over the title bar.
    made.logo = (native and made.NineSlice or made):CreateTexture(nil, "OVERLAY")
    made.logo:SetSize(LOGO, LOGO)
    made.logo:SetPoint("RIGHT", made.title, "LEFT", -LOGO_GAP, 0)
    made.logo:SetTexture("Interface\\AddOns\\LFGBoard\\minimap")

    -- Our own, not the game's: that asks the window manager, which an addon
    -- may not do in combat.
    made.close:SetScript("OnClick", function()
        made:Hide()
    end)
    return made
end

local function create()
    frame = createWindowFrame()
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", savePosition)
    local saved = ns.db.window
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)

    frame.tabs = {}
    for index, info in ipairs(TABS) do
        frame.tabs[info.key] = button(info.label, 104, 16 + (index - 1) * 108, -36, function()
            tab = info.key
            Window.Refresh()
        end)
    end

    -- Seven switches between the left edge and Refresh: each placed just past
    -- the last one's label, which leaves little to spare.
    frame.roles = {}
    for index, info in ipairs(ROLE_SWITCHES) do
        frame.roles[info.key] = checkbox(info.label, 16 + (index - 1) * 70, -64, function(checked)
            ns.SetRole(info.key, checked)
        end)
    end
    frame.near = checkbox("Near my level", 232, -64, function(checked)
        Window.SetNearLevel(checked)
    end)
    frame.alerts = checkbox("Alerts", 350, -64, function(checked)
        ns.Alerts.SetEnabled(checked)
    end)
    frame.completed = checkbox("Hide done quests", 426, -64, function(checked)
        Window.SetHideCompleted(checked)
    end)
    -- Ticked while the button shows. The settings page has the same box.
    frame.minimap = checkbox("Minimap button", 562, -64, function(checked)
        ns.MinimapButton.SetHidden(not checked)
    end)
    frame.refresh = button("Refresh", 96, WIDTH - 116, -62, function()
        local ok, why = ns.Finder.Search(tab)
        if not ok then
            ns.Print("The group finder could not be searched: " .. why .. ".")
        end
    end)

    frame.rows = {}
    for index = 1, Window.ROWS do
        frame.rows[index] = makeRow(index)
    end

    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 14)

    frame:SetScript("OnShow", function()
        Window.Refresh()
    end)
    table.insert(UISpecialFrames, "LFGBoardFrame")
    frame:Hide()
end

--- Hide dungeons and raids far from the player's level, or show them;
-- remembered. The board's switch and the settings page both write here.
function Window.SetNearLevel(on)
    ns.db.nearLevel = on and true or false
    ns.Changed()
end

--- Hide quest groups for quests the player has handed in, or show them;
-- remembered. The board's switch and the settings page both write here.
function Window.SetHideCompleted(on)
    ns.db.hideCompleted = on and true or false
    ns.Changed()
end

function Window.Refresh()
    if not (frame and frame:IsShown()) then
        return
    end

    local filter = Window.Filter()
    local counts = ns.Posts.Counts(filter)
    for _, info in ipairs(TABS) do
        local tabButton = frame.tabs[info.key]
        tabButton:SetText(string.format("%s (%d)", info.label, counts[info.key]))
        -- The tab shown reads as pressed.
        tabButton:SetEnabled(info.key ~= tab)
    end

    for key, box in pairs(frame.roles) do
        box:SetChecked(filter.roles[key])
    end
    frame.near:SetChecked(ns.db.nearLevel)
    frame.alerts:SetChecked(ns.db.alerts)
    frame.completed:SetChecked(ns.db.hideCompleted)
    frame.minimap:SetChecked(not ns.db.minimap.hide)
    frame.refresh:SetEnabled(ns.Finder.Available())

    local views = ns.Posts.Visible(filter)
    local now = GetTime()
    for index, row in ipairs(frame.rows) do
        local view = views[index]
        if view then
            fill(row, view, now, filter.roles)
        else
            row.view = nil
            row:Hide()
        end
    end

    local reading = ns.Finder.Available() and "Reading chat and the group finder." or "Reading chat."
    local more = #views - Window.ROWS
    frame.footer:SetText(more > 0 and string.format("%s %d more not shown.", reading, more) or reading)
end

function Window.Toggle()
    if not frame then
        create()
    end
    frame:SetShown(not frame:IsShown())
end

--- Show the board; left open if it is open already.
function Window.Open()
    if not frame then
        create()
    end
    frame:Show()
end

function Window.Frame()
    return frame
end
