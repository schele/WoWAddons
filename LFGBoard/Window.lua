local addonName, ns = ...

-- The board: tabs, the dungeon picker, the role and level switches, the
-- rows, and Refresh. Drawn again from Posts whenever anything changes while
-- it is open.

local Window = {}
ns.Window = Window

ns.AddDefaults({
    window = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    nearLevel = true,
})

local WIDTH, HEIGHT = 820, 460
local ROW_HEIGHT = 28
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
local picked

function Window.Filter()
    return {
        tab = tab,
        activity = picked,
        roles = ns.Roles(),
        nearLevel = ns.db.nearLevel,
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
        parts[#parts + 1] = "?/5"
    end
    if wants ~= "" then
        parts[#parts + 1] = "needs " .. wants
    end
    return table.concat(parts, ", ")
end

local function makeRow(index)
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(WIDTH - 32, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -96 - (index - 1) * ROW_HEIGHT)

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

    row.party:ClearAllPoints()
    row.party:SetPoint("LEFT", row, "LEFT", squares and (PARTY_X + SQUARES_WIDTH) or PARTY_X, 0)
    row.party:SetWidth(squares and (PARTY_WIDTH - SQUARES_WIDTH) or PARTY_WIDTH)
    row.party:SetText(Window.Party(view))
    row:Show()
end

local function savePosition(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    local saved = ns.db.window
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
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

local function create()
    frame = CreateFrame("Frame", "LFGBoardFrame", UIParent, "BackdropTemplate")
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
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -14)
    frame.title:SetText("LFG Board")

    -- Our own, not the game's: that asks the window manager, which an addon
    -- may not do in combat.
    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    frame.close:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame.tabs = {}
    for index, info in ipairs(TABS) do
        frame.tabs[info.key] = button(info.label, 104, 16 + (index - 1) * 108, -36, function()
            tab = info.key
            Window.Refresh()
        end)
    end

    frame.picker = button("Dungeon: Any", 200, 460, -36, function(_, mouseButton)
        Window.StepPicker(mouseButton == "RightButton" and -1 or 1)
    end)
    frame.picker:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    frame.roles = {}
    for index, info in ipairs(ROLE_SWITCHES) do
        frame.roles[info.key] = checkbox(info.label, 16 + (index - 1) * 84, -64, function(checked)
            ns.Roles()[info.key] = checked
            Window.Refresh()
        end)
    end
    frame.near = checkbox("Near my level", 280, -64, function(checked)
        ns.db.nearLevel = checked
        Window.Refresh()
    end)
    frame.alerts = checkbox("Alerts", 420, -64, function(checked)
        ns.db.alerts = checked
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

--- Step the dungeon picker through Any and the activities on the board.
function Window.StepPicker(step)
    local choices = ns.Posts.Activities()
    local at = 0
    for index, activity in ipairs(choices) do
        if activity == picked then
            at = index
        end
    end
    at = (at + step) % (#choices + 1)
    picked = at > 0 and choices[at] or nil
    Window.Refresh()
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

    frame.picker:SetText("Dungeon: " .. (picked and ns.Activities.Display(picked) or "Any"))
    for key, box in pairs(frame.roles) do
        box:SetChecked(filter.roles[key])
    end
    frame.near:SetChecked(ns.db.nearLevel)
    frame.alerts:SetChecked(ns.db.alerts)
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

function Window.Frame()
    return frame
end
