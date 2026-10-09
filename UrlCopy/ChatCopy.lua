local addonName, ns = ...

-- Copying from chat. A chat window cannot be selected with the mouse, so
-- this puts a window's lines, as plain text, in a box that can be: mark any
-- of it, then Ctrl+C. As with a link, that is as near to copying as an addon
-- can come.

ns.AddDefaults({
    chatCopy = {
        -- The button in a chat window's corner. /url chat works either way.
        button = true,
    },
})

local ChatCopy = {}
ns.ChatCopy = ChatCopy

local WIDTH, HEIGHT = 600, 420
local BUTTON_SIZE = 18
-- How far in from the chat window's right edge the button sits.
local BUTTON_INSET = 24
-- Seconds between looks at where the mouse is, for the buttons.
local HOVER_POLL = 0.1
local ICON = "Interface\\AddOns\\UrlCopy\\logo"
local HINT = "Mark text with the mouse, then Ctrl+C to copy."

-- An escaped pipe, kept out of the way while the markup comes off.
local PIPE = "\1"

--- A chat line as it reads: colours, icons and link markup gone, a link
-- kept as the [Name] it shows, and an escaped pipe a pipe again.
function ChatCopy.Plain(message)
    local text = tostring(message):gsub("||", PIPE)
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|cn[^:]*:", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    -- A Battle.net name, which the client fills in for the eye alone.
    text = text:gsub("|K.-|k", "")
    text = text:gsub("|n", "\n")
    text = text:gsub(PIPE, "|")
    return text
end

--- A chat window's lines, oldest first, as plain text, and how many could
-- not be read. This client can hand an addon a line it may not read (a
-- secret value); that one is left out rather than failing the rest.
function ChatCopy.Lines(chatFrame)
    local lines, skipped = {}, 0
    if not (chatFrame and chatFrame.GetNumMessages and chatFrame.GetMessageInfo) then
        return lines, skipped
    end

    local ok, count = pcall(chatFrame.GetNumMessages, chatFrame)
    for index = 1, ok and tonumber(count) or 0 do
        local read, text = pcall(function()
            local message = chatFrame:GetMessageInfo(index)
            return message ~= nil and ChatCopy.Plain(message) or nil
        end)
        if not read then
            skipped = skipped + 1
        elseif text then
            table.insert(lines, text)
        end
    end
    return lines, skipped
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local frame
-- What the box holds. Typing into it puts this back.
local current = ""
-- Armed while the box's text is being set here, so the put-back does not
-- answer its own SetText.
local restoring = false

--- CreateFrame with a template, or without it on a client that lacks it.
local function createFrame(kind, name, parent, template)
    local ok, created = pcall(CreateFrame, kind, name, parent, template)
    if ok and created then
        return created
    end
    return CreateFrame(kind, name, parent)
end

-- The window's frame, as LFGBoard's: the options window's own, with its
-- title bar and red X, or on a client without it the dialog border, a title
-- and a close button of our own. Solid either way, for reading.
local function createWindowFrame()
    local ok, made = pcall(CreateFrame, "Frame", "UrlCopyChatWindow", UIParent, "SettingsFrameTemplate")
    if not (ok and made) then
        made = createFrame("Frame", "UrlCopyChatWindow", UIParent, "BackdropTemplate")
    end
    local native = made.NineSlice and made.NineSlice.Text and made.ClosePanelButton and made.Bg

    if native then
        made.background = made.Bg:CreateTexture(nil, "BACKGROUND", nil, 7)
        made.background:SetAllPoints(made.Bg)
        made.title = made.NineSlice.Text
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
        made.title:SetPoint("TOP", made, "TOP", 0, -14)
        made.close = createFrame("Button", nil, made, "UIPanelCloseButton")
        made.close:SetPoint("TOPRIGHT", made, "TOPRIGHT", -4, -4)
    end
    made.background:SetColorTexture(0.06, 0.045, 0.03, 1)

    -- Our own, not the game's: that asks the window manager, which an addon
    -- may not do in combat.
    made.close:SetScript("OnClick", function()
        made:Hide()
    end)
    return made
end

local function scrollToBottom()
    local scroll = frame and frame.scroll
    if not scroll then
        return
    end
    if scroll.UpdateScrollChildRect then
        scroll:UpdateScrollChildRect()
    end
    scroll:SetVerticalScroll(scroll:GetVerticalScrollRange() or 0)
end

local function create()
    frame = createWindowFrame()
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -34)
    frame.hint:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    frame.hint:SetJustifyH("LEFT")

    local scroll = createFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -54)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 16)
    -- Without the template there is no scroll bar, so the wheel does it.
    if not scroll.ScrollBar then
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local range = self:GetVerticalScrollRange() or 0
            local target = (self:GetVerticalScroll() or 0) - delta * 40
            self:SetVerticalScroll(math.max(0, math.min(range, target)))
        end)
    end
    frame.scroll = scroll

    -- A multi-line box grows with its text; the scroll frame shows a window
    -- onto it.
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    box:SetWidth(WIDTH - 58)
    -- At least the window's height, so a click below short text still
    -- lands in the box.
    box:SetHeight(HEIGHT - 70)
    box:EnableMouse(true)
    scroll:SetScrollChild(box)
    frame.box = box

    box:SetScript("OnTextChanged", function(self)
        if restoring or self:GetText() == current then
            return
        end
        -- A copy box, not an editor: marking and copying change nothing,
        -- and anything typed is put back.
        restoring = true
        self:SetText(current)
        restoring = false
    end)
    box:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    frame:SetScript("OnHide", function()
        box:ClearFocus()
    end)

    -- Escape closes it from anywhere, as it does the game's own windows.
    table.insert(UISpecialFrames, "UrlCopyChatWindow")
    frame:Hide()
end

local function hintFor(lines, skipped)
    if skipped > 0 then
        return string.format("%s %d %s could not be read and %s left out.", HINT, skipped,
            skipped == 1 and "line" or "lines", skipped == 1 and "is" or "are")
    end
    if #lines == 0 then
        return "There is nothing in this chat window to copy yet."
    end
    return HINT
end

--- Open a chat window's text in the copy window: newest at the bottom, the
-- box focused so Ctrl+C copies what is marked.
function ChatCopy.Open(chatFrame)
    if not frame then
        create()
    end

    local lines, skipped = ChatCopy.Lines(chatFrame)
    current = table.concat(lines, "\n")
    restoring = true
    frame.box:SetText(current)
    restoring = false

    local name = chatFrame and type(chatFrame.name) == "string" and chatFrame.name or nil
    frame.title:SetText(name and ("Copy chat: " .. name) or "Copy chat")
    frame.hint:SetText(hintFor(lines, skipped))
    frame:Show()
    frame.box:SetFocus()
    frame.box:SetCursorPosition(#current)
    -- The box lays its text out on the next frame; only then does the
    -- scroll frame know how far down the bottom is.
    C_Timer.After(0, scrollToBottom)
    return frame
end

function ChatCopy.Frame()
    return frame
end

--------------------------------------------------------------------------------
-- The buttons on the chat windows
--------------------------------------------------------------------------------

-- chat frame -> its copy button
local buttons = {}

local function isCombatLog(chatFrame)
    return chatFrame == COMBATLOG
end

--- Every chat window, the ones opened later for whispers too.
local function chatFrames()
    local list = {}
    if type(CHAT_FRAMES) == "table" then
        for _, name in ipairs(CHAT_FRAMES) do
            local chatFrame = _G[name]
            if chatFrame then
                table.insert(list, chatFrame)
            end
        end
    end
    if #list == 0 then
        for index = 1, NUM_CHAT_WINDOWS or 10 do
            local chatFrame = _G["ChatFrame" .. index]
            if chatFrame then
                table.insert(list, chatFrame)
            end
        end
    end
    return list
end

local function buttonFor(chatFrame)
    local button = buttons[chatFrame]
    if button then
        return button
    end

    button = CreateFrame("Button", nil, chatFrame)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    -- Left of the chat's scroll bar, whose arrow takes the corner itself.
    button:SetPoint("TOPRIGHT", chatFrame, "TOPRIGHT", -BUTTON_INSET, 0)
    -- Over the chat's own lines, which would otherwise take the click.
    button:SetFrameLevel((chatFrame:GetFrameLevel() or 1) + 5)
    button:SetNormalTexture(ICON)
    button:SetPushedTexture(ICON)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    button:SetScript("OnClick", function()
        ChatCopy.Open(chatFrame)
    end)
    button:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Copy chat")
            GameTooltip:AddLine("Open this window's text to mark and copy.", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    button:Hide()
    buttons[chatFrame] = button
    return button
end

function ChatCopy.Button(chatFrame)
    return buttons[chatFrame]
end

--- Show each chat window's button while the mouse is over that window, as
-- the game shows its own chat buttons; none at all with the setting off.
function ChatCopy.Update()
    local enabled = ns.db and ns.db.chatCopy and ns.db.chatCopy.button
    if not enabled then
        for _, button in pairs(buttons) do
            button:Hide()
        end
        return
    end

    for _, chatFrame in ipairs(chatFrames()) do
        if not isCombatLog(chatFrame) then
            local over = chatFrame:IsShown() and chatFrame:IsMouseOver()
            buttonFor(chatFrame):SetShown(over and true or false)
        end
    end
end

local driver = CreateFrame("Frame")
local waited = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    waited = waited + (elapsed or 0)
    if waited < HOVER_POLL or not ns.db then
        return
    end
    waited = 0
    ChatCopy.Update()
end)

ns.RegisterSetting({
    store = "chatCopy",
    key = "button",
    type = "checkbox",
    name = "Copy button on chat windows",
    tooltip = "A button in the corner of a chat window, while the mouse is over it, opens the window's text to mark and copy. /url chat does the same.",
    onChange = function()
        ChatCopy.Update()
    end,
})

ns.RegisterCommand("chat", "Open the chat tab you are looking at, to mark and copy its text", function()
    ChatCopy.Open(SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME or ChatFrame1)
end)
