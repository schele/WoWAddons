local addonName, ns = ...

-- The checkboxes and buttons, laid on the game's own inbox: a box left of
-- each mail's icon, Select all under the title, and Open (N) beside the
-- game's Open All, which is moved over, not changed.

local Buttons = {}
ns.Buttons = Buttons

local BUTTON_WIDTH, BUTTON_HEIGHT = 80, 22
-- How far Open and Open All sit either side of where Open All was.
local SHIFT = 42
-- How far each mail's icon, and the text hung off it, moves right so its
-- box is clear of the frame's border.
local ROOM = 20

local created = false
local boxes = {}
local selectAll, openButton, ownOpenAll

local function rowsPerPage()
    return INBOXITEMS_TO_DISPLAY or 7
end

local function pageOffset()
    local page = InboxFrame and InboxFrame.pageNum
    return ((type(page) == "number" and page or 1) - 1) * rowsPerPage()
end

local function leftAnchored(point)
    return point == "TOPLEFT" or point == "LEFT" or point == "BOTTOMLEFT"
end

local function shiftRight(region)
    local point, relative, relativePoint, x, y = region:GetPoint(1)
    region:ClearAllPoints()
    region:SetPoint(point, relative, relativePoint, (x or 0) + ROOM, y or 0)
end

-- Moves the icon right by ROOM, and with it the row's text, which hangs off
-- the row rather than the icon. The text is narrowed as far, so it still
-- ends short of the days left on the right. Text hung off moved text moves
-- with it and is only narrowed.
local function makeRoom(rowFrame, icon)
    if icon:GetPoint(1) then
        shiftRight(icon)
    end
    if not rowFrame.GetRegions then
        return
    end

    local texts = {}
    for _, region in ipairs({ rowFrame:GetRegions() }) do
        if region:GetObjectType() == "FontString" and region:GetNumPoints() == 1 then
            table.insert(texts, region)
        end
    end

    local moved = {}
    local changed = true
    while changed do
        changed = false
        for _, text in ipairs(texts) do
            local point, relative = text:GetPoint(1)
            if not moved[text] and leftAnchored(point)
                and (relative == rowFrame or moved[relative]) then
                if relative == rowFrame then
                    shiftRight(text)
                end
                local width = text:GetWidth()
                if width > ROOM then
                    text:SetWidth(width - ROOM)
                end
                moved[text] = true
                changed = true
            end
        end
    end
end

local function makeBox(row)
    local rowFrame = _G["MailItem" .. row]
    if not rowFrame then
        return nil
    end
    local box = CreateFrame("CheckButton", nil, rowFrame, "UICheckButtonTemplate")
    box:SetSize(22, 22)
    local icon = _G["MailItem" .. row .. "Button"]
    if icon then
        makeRoom(rowFrame, icon)
    end
    box:SetPoint("RIGHT", icon or rowFrame, "LEFT", -2, 0)
    box:SetScript("OnClick", function(self)
        ns.Ticks.Set(self.key, self:GetChecked())
    end)
    return box
end

-- The small font, so the text of two buttons that fit where one did clears
-- Prev and Next.
local function smallText(button)
    if GameFontNormalSmall and button.SetNormalFontObject then
        button:SetNormalFontObject(GameFontNormalSmall)
        button:SetHighlightFontObject(GameFontHighlightSmall)
        button:SetDisabledFontObject(GameFontDisableSmall)
    end
end

local function panelButton(name, text, onClick)
    local made = CreateFrame("Button", name, InboxFrame, "UIPanelButtonTemplate")
    smallText(made)
    made:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    made:SetText(text)
    made:SetScript("OnClick", onClick)
    return made
end

local function openAll()
    ns.Ticks.SetAll(true)
    ns.Opener.Start()
end

function Buttons.Create()
    if created or not InboxFrame then
        return
    end
    created = true

    for row = 1, rowsPerPage() do
        boxes[row] = makeBox(row)
    end

    selectAll = CreateFrame("CheckButton", "MailHandlerSelectAll", InboxFrame, "UICheckButtonTemplate")
    selectAll:SetSize(22, 22)
    selectAll:SetPoint("TOPLEFT", InboxFrame, "TOPLEFT", 64, -36)
    selectAll.label = selectAll:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectAll.label:SetPoint("LEFT", selectAll, "RIGHT", 2, 0)
    selectAll.label:SetText("Select all")
    selectAll:SetScript("OnClick", function(self)
        ns.Ticks.SetAll(self:GetChecked())
    end)

    openButton = panelButton("MailHandlerOpenButton", "Open (0)", function()
        ns.Opener.Start()
    end)

    local native = OpenAllMail
    if native then
        local point, relative, relativePoint, x, y = native:GetPoint(1)
        point = point or "BOTTOM"
        relative = relative or InboxFrame
        relativePoint = relativePoint or point
        x, y = x or 0, y or 0
        native:ClearAllPoints()
        native:SetWidth(BUTTON_WIDTH)
        smallText(native)
        native:SetPoint(point, relative, relativePoint, x + SHIFT, y)
        openButton:SetPoint(point, relative, relativePoint, x - SHIFT, y)
    else
        -- This client has no Open All: one of ours, beside Open.
        openButton:SetPoint("LEFT", InboxPrevPageButton or InboxFrame, "RIGHT", 40, 0)
        ownOpenAll = panelButton("MailHandlerOpenAllButton", "Open All", openAll)
        ownOpenAll:SetPoint("LEFT", openButton, "RIGHT", 6, 0)
    end

    -- Classic Era redraws its inbox with InboxFrame_Update; Forever's mail
    -- frame is the mainline one, which redraws with InboxFrame:Update() on
    -- Prev, Next and the mouse wheel, with no event to follow.
    if hooksecurefunc and InboxFrame_Update then
        hooksecurefunc("InboxFrame_Update", Buttons.Refresh)
    elseif hooksecurefunc and InboxFrame.Update then
        hooksecurefunc(InboxFrame, "Update", Buttons.Refresh)
    end
end

function Buttons.Refresh()
    if not created then
        return
    end

    local mails = ns.Inbox.Mails()
    local byIndex = {}
    for _, mail in ipairs(mails) do
        byIndex[mail.index] = mail
    end

    local offset = pageOffset()
    for row, box in pairs(boxes) do
        local mail = byIndex[offset + row]
        box.key = mail and mail.key or nil
        box:SetShown(mail ~= nil)
        box:SetChecked(mail ~= nil and ns.Ticks.Is(mail.key))
    end

    local running = ns.Opener.Running()
    local count = ns.Ticks.Count(mails)
    selectAll:SetChecked(ns.Ticks.AllTicked(mails))
    openButton:SetText(string.format("Open (%d)", count))
    openButton:SetEnabled(count > 0 and not running)
    if ownOpenAll then
        ownOpenAll:SetEnabled(#mails > 0 and not running)
    end
end

function Buttons.Parts()
    return { boxes = boxes, selectAll = selectAll, open = openButton, openAll = ownOpenAll }
end

local events = CreateFrame("Frame")
events:RegisterEvent("MAIL_SHOW")
events:RegisterEvent("MAIL_INBOX_UPDATE")
events:RegisterEvent("MAIL_CLOSED")
events:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SHOW" then
        Buttons.Create()
        Buttons.Refresh()
    elseif event == "MAIL_INBOX_UPDATE" then
        Buttons.Refresh()
    else
        ns.Opener.Stop()
        ns.Ticks.Clear()
        Buttons.Refresh()
    end
end)
