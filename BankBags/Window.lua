local addonName, ns = ...

-- The window: a character's saved bank, the main bank first and then each
-- bank bag under its name, twelve slots to a row, scrolling when long. A
-- search dims what does not match; the footer says when it was saved; the
-- button under the title steps through every character saved.

local Window = {}
ns.Window = Window

ns.AddDefaults({
    window = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
})

local SLOT = 37
local GAP = 4
local PER_ROW = 12
local PADDING = 14
local TITLE_HEIGHT = 30
local BAR_HEIGHT = 26 -- the picker and search under the title
local TOP = PADDING + TITLE_HEIGHT + BAR_HEIGHT
local HEADER = 24 -- a section's heading
local SECTION_GAP = 6
local FOOTER = 24
local WIDTH = PADDING * 2 + PER_ROW * SLOT + (PER_ROW - 1) * GAP
local HEIGHT = 520
local VIEW_WIDTH = WIDTH - PADDING * 2
local VIEW_HEIGHT = HEIGHT - TOP - FOOTER - PADDING
local DIM = 0.25
local EMPTY_ICON = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local BANK_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local HINT = "Visit a banker to save your bank"

-- Quality colours for an item's edge, when the client has none of its own.
local QUALITY = {
    [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 },
    [4] = { r = 0.64, g = 0.21, b = 0.93 }, [5] = { r = 1, g = 0.5, b = 0 },
}

local frame
local shownKey
local search = ""

--- How long ago a save was, in words.
function Window.SavedText(seconds)
    if seconds < 60 then
        return "Saved just now"
    end
    local function ago(count, unit)
        return string.format("Saved %d %s%s ago", count, unit, count == 1 and "" or "s")
    end
    if seconds < 3600 then
        return ago(math.floor(seconds / 60), "minute")
    end
    if seconds < 86400 then
        return ago(math.floor(seconds / 3600), "hour")
    end
    return ago(math.floor(seconds / 86400), "day")
end

--- Whether the name in an item's link holds the search text, ignoring case;
-- an empty search matches everything.
function Window.Matches(link, text)
    if not text or text == "" then
        return true
    end
    local name = link and link:match("%[(.-)%]")
    return name ~= nil and name:lower():find(text:lower(), 1, true) ~= nil
end

local function qualityColour(quality)
    if not quality or quality < 2 then
        return nil
    end
    local colours = ITEM_QUALITY_COLORS
    return (colours and colours[quality]) or QUALITY[quality]
end

-- A character's name in their class colour, and their realm in grey.
local function characterLabel(key, character)
    local name = character and character.name or key:match("%-(.-)$") or key
    local realm = character and character.realm or key:match("^(.-)%-") or ""
    local colour = character and character.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[character.class]
    if colour then
        name = string.format("|cff%02x%02x%02x%s|r", colour.r * 255, colour.g * 255, colour.b * 255, name)
    end
    return name .. " |cff808080" .. realm .. "|r"
end

-- A frame with a template, or without when this client lacks the template.
local function createFrame(kind, name, parent, template)
    local ok, created = pcall(CreateFrame, kind, name, parent, template)
    if ok and created then
        return created
    end
    return CreateFrame(kind, name, parent)
end

local function scrollTo(offset)
    local most = math.max(0, frame.content:GetHeight() - VIEW_HEIGHT)
    frame.scroll:SetVerticalScroll(math.max(0, math.min(most, offset)))
end

local function header(index)
    local made = frame.headers[index]
    if made then
        return made
    end
    made = CreateFrame("Frame", nil, frame.content)
    made:SetSize(VIEW_WIDTH, HEADER)
    made.icon = made:CreateTexture(nil, "ARTWORK")
    made.icon:SetSize(18, 18)
    made.icon:SetPoint("LEFT", made, "LEFT", 0, 0)
    made.text = made:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    made.text:SetPoint("LEFT", made.icon, "RIGHT", 6, 0)
    frame.headers[index] = made
    return made
end

local function showTooltip(self)
    if not (self.item and GameTooltip) then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.item.link)
    GameTooltip:Show()
end

local function hideTooltip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

local function slotButton(index)
    local made = frame.slots[index]
    if made then
        return made
    end
    made = CreateFrame("Button", nil, frame.content)
    made:SetSize(SLOT, SLOT)
    made:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    made.edge = made:CreateTexture(nil, "BACKGROUND")
    made.edge:SetAllPoints()
    made.icon = made:CreateTexture(nil, "ARTWORK")
    made.icon:SetPoint("TOPLEFT", made, "TOPLEFT", 2, -2)
    made.icon:SetPoint("BOTTOMRIGHT", made, "BOTTOMRIGHT", -2, 2)
    made.count = made:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    made.count:SetPoint("BOTTOMRIGHT", made, "BOTTOMRIGHT", -3, 3)
    made:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    made:SetScript("OnEnter", showTooltip)
    made:SetScript("OnLeave", hideTooltip)
    -- Shift-click links in chat, ctrl-click previews: the game's own handler.
    made:SetScript("OnClick", function(self)
        if self.item and HandleModifiedItemClick then
            HandleModifiedItemClick(self.item.link)
        end
    end)
    frame.slots[index] = made
    return made
end

local function renderSlot(button, item)
    button.item = item
    if item then
        button.icon:SetTexture(item.icon)
        button.count:SetText((item.count and item.count > 1) and tostring(item.count) or "")
        local colour = qualityColour(item.quality)
        if colour then
            button.edge:SetColorTexture(colour.r, colour.g, colour.b, 1)
            button.edge:Show()
        else
            button.edge:Hide()
        end
        button:SetAlpha(Window.Matches(item.link, search) and 1 or DIM)
    else
        button.icon:SetTexture(EMPTY_ICON)
        button.count:SetText("")
        button.edge:Hide()
        button:SetAlpha(search == "" and 1 or DIM)
    end
end

--- Draw the character shown: the picker, each section and slot, the footer.
function Window.Refresh()
    if not frame then
        return
    end
    shownKey = shownKey or ns.Bank.CharacterKey()
    local character = ns.Bank.Get(shownKey)
    frame.picker.text:SetText(characterLabel(shownKey, character))

    local y, headers, slots = 0, 0, 0
    for _, container in ipairs(character and character.containers or {}) do
        headers = headers + 1
        local heading = header(headers)
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -y)
        heading.text:SetText(container.name)
        heading.icon:SetTexture(container.icon or BANK_ICON)
        heading:Show()
        y = y + HEADER
        for slot = 1, container.size do
            slots = slots + 1
            local button = slotButton(slots)
            local column = (slot - 1) % PER_ROW
            local row = math.floor((slot - 1) / PER_ROW)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", frame.content, "TOPLEFT", column * (SLOT + GAP), -(y + row * (SLOT + GAP)))
            renderSlot(button, container.slots[slot])
            button:Show()
        end
        y = y + math.ceil(container.size / PER_ROW) * (SLOT + GAP) + SECTION_GAP
    end
    for index = headers + 1, #frame.headers do
        frame.headers[index]:Hide()
    end
    for index = slots + 1, #frame.slots do
        frame.slots[index]:Hide()
    end
    frame.content:SetHeight(math.max(y, 1))
    scrollTo(frame.scroll:GetVerticalScroll())

    if character and character.saved then
        local now = time and time() or character.saved
        frame.footer:SetText(Window.SavedText(now - character.saved))
    else
        frame.footer:SetText(HINT)
    end
end

--- The character shown, "<realm>-<name>".
function Window.Shown()
    return shownKey
end

-- Step through the saved characters, forward or back.
local function cycle(step)
    local keys = ns.Bank.Characters()
    if #keys == 0 then
        return
    end
    local at = 1
    for index, key in ipairs(keys) do
        if key == shownKey then
            at = index
        end
    end
    shownKey = keys[(at - 1 + step) % #keys + 1]
    scrollTo(0)
    Window.Refresh()
end

local function savePosition(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    local saved = ns.db.window
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

local function create()
    frame = createFrame("Frame", "BankBagsFrame", UIParent, "BackdropTemplate")
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
    frame.headers, frame.slots = {}, {}

    -- Opaque, whatever the backdrop does, inside the dialog border.
    frame.background = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.background:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    frame.background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    frame.background:SetColorTexture(0.06, 0.045, 0.03, 1)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    table.insert(UISpecialFrames, "BankBagsFrame")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 4, -PADDING - 4)
    title:SetText("BankBags")

    frame.close = createFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    if not (frame.close.GetNormalTexture and frame.close:GetNormalTexture()) then
        frame.close:SetText("X")
    end
    frame.close:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- The character shown: a click for the next, a right-click for the last.
    frame.picker = CreateFrame("Button", nil, frame)
    frame.picker:SetSize(200, 20)
    frame.picker:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -(PADDING + TITLE_HEIGHT))
    frame.picker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame.picker.text = frame.picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.picker.text:SetPoint("LEFT", frame.picker, "LEFT", 4, 0)
    frame.picker:SetScript("OnClick", function(_, mouseButton)
        cycle(mouseButton == "RightButton" and -1 or 1)
    end)

    frame.search = createFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.search:SetSize(180, 20)
    frame.search:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING - 4, -(PADDING + TITLE_HEIGHT))
    frame.search:SetAutoFocus(false)
    frame.search:SetScript("OnTextChanged", function(self)
        search = self:GetText() or ""
        Window.Refresh()
    end)
    -- Enter or Escape lets go of the keyboard: otherwise the movement keys go
    -- on typing into the box.
    frame.search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    frame.search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame)
    frame.scroll:SetSize(VIEW_WIDTH, VIEW_HEIGHT)
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -TOP)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(VIEW_WIDTH, 1)
    frame.scroll:SetScrollChild(frame.content)
    frame.scroll:EnableMouseWheel(true)
    frame.scroll:SetScript("OnMouseWheel", function(_, delta)
        scrollTo(frame.scroll:GetVerticalScroll() - delta * (SLOT + GAP))
    end)

    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING + 4, PADDING + 4)

    frame:SetScript("OnShow", function()
        Window.Refresh()
    end)
    frame:Hide()
end

function Window.Frame()
    return frame
end

function Window.Open()
    if not frame then
        create()
    end
    frame:Show()
    Window.Refresh()
end

function Window.Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        Window.Open()
    end
end

ns.DefaultCommand = Window.Toggle
