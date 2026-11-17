local addonName, ns = ...

-- The whisper a row's button opens: who you are and what you can do, typed
-- out, so Enter is all that is left.
--
-- It is written in a line at the foot of the board, not in the game's chat
-- box. Opening that box or typing into it from an addon marks it as the
-- addon's until a reload, and the game then blocks its own code that reads
-- it: shift-clicking a map pin into chat copies a /mappin line to the
-- clipboard, which only the game may do, so it was blocked and blamed on
-- LFGBoard. The board's own box sends the whisper itself.

local Whisper = {}
ns.Whisper = Whisper

local WHISPER_COLOR = { 1, 0.5, 1 }

local composer

-- The words players use for a talent tree, where it is not its first word.
Whisper.SHORT = {
    ["restoration"] = "resto",
    ["protection"] = "prot",
    ["beast mastery"] = "bm",
    ["discipline"] = "disc",
    ["elemental"] = "ele",
    ["enhancement"] = "enh",
    ["demonology"] = "demo",
    ["destruction"] = "destro",
    ["affliction"] = "affli",
}

local ROLE_ORDER = { "tank", "healer", "dps" }

--- The talent tree with the most points, or nil with none spent. Points are
-- counted talent by talent: where the tab's own count sits differs between
-- clients, and the name may come before or after an ID.
local function talentTree()
    return ns.Guarded(function()
        if not (GetNumTalentTabs and GetTalentTabInfo and GetNumTalents and GetTalentInfo) then
            return nil
        end
        local best, bestPoints = nil, 0
        for tab = 1, GetNumTalentTabs() do
            local first, second = GetTalentTabInfo(tab)
            local name = type(first) == "string" and first or second
            local points = 0
            for index = 1, GetNumTalents(tab) do
                local rank = select(5, GetTalentInfo(tab, index))
                points = points + (type(rank) == "number" and rank or 0)
            end
            if type(name) == "string" and points > bestPoints then
                best, bestPoints = name, points
            end
        end
        return best
    end, nil)
end

function Whisper.SpecWord(treeName)
    if type(treeName) ~= "string" then
        return nil
    end
    local lower = treeName:lower()
    return Whisper.SHORT[lower] or lower:match("^(%S+)")
end

--- Your roles that a group wants, "tank or dps"; all your roles when it
-- does not say, or wants none of them.
function Whisper.Roles(wanted, mine)
    local parts = {}
    for _, role in ipairs(ROLE_ORDER) do
        if mine[role] and (wanted == nil or wanted[role]) then
            parts[#parts + 1] = role
        end
    end
    if #parts == 0 then
        for _, role in ipairs(ROLE_ORDER) do
            if mine[role] then
                parts[#parts + 1] = role
            end
        end
    end
    return table.concat(parts, " or ")
end

local function forWhat(view)
    if view.activity then
        return ns.Activities.Display(view.activity)
    end
    return view.kind == "quest" and "your quest group" or "your group"
end

function Whisper.Message(view)
    local level = UnitLevel("player") or 0
    local class = (UnitClass("player") or ""):lower()
    local spec = Whisper.SpecWord(talentTree())
    local who = spec and (spec .. " " .. class) or class

    local text = string.format("Hi! Level %d %s", level, who)
    local roles = Whisper.Roles(view.roles, ns.Roles())
    if roles ~= "" then
        text = text .. ", " .. roles
    end
    return text .. ". Room for me in " .. forWhat(view) .. "?"
end

--- CreateFrame with a template, or without it on a client that lacks it.
local function createFrame(kind, parent, template)
    local ok, created = pcall(CreateFrame, kind, nil, parent, template)
    if ok and created then
        return created
    end
    return CreateFrame(kind, nil, parent)
end

local function close()
    if composer then
        composer:Hide()
    end
end

--- In some fights the game holds back chat that addons send.
local function heldBack()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() or false
end

local function send()
    local text = composer.box:GetText() or ""
    if text:match("^%s*$") then
        close()
        return
    end
    -- Kept rather than lost, to send when the fight is over.
    if heldBack() then
        ns.Print("The game holds back chat from addons during this fight. Press Enter again once it is over.")
        return
    end
    local sendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if sendChat then
        sendChat(text, "WHISPER", nil, composer.target)
    end
    close()
end

local function button(label, onClick)
    local made = createFrame("Button", composer, "UIPanelButtonTemplate")
    made:SetSize(64, 22)
    made:SetText(label)
    made:SetScript("OnClick", onClick)
    return made
end

--- The line the whisper is written in, in the footer's place: "To Garrok:",
-- the message, Send and Cancel.
local function create(board)
    composer = CreateFrame("Frame", nil, board)
    composer:SetHeight(22)
    composer:SetPoint("BOTTOMLEFT", board, "BOTTOMLEFT", 16, 10)
    composer:SetPoint("BOTTOMRIGHT", board, "BOTTOMRIGHT", -16, 10)

    composer.label = composer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    composer.label:SetPoint("LEFT", composer, "LEFT", 2, 0)
    composer.label:SetTextColor(WHISPER_COLOR[1], WHISPER_COLOR[2], WHISPER_COLOR[3])

    composer.cancel = button(CANCEL or "Cancel", close)
    composer.cancel:SetPoint("RIGHT", composer, "RIGHT", 0, 0)
    composer.send = button(SEND_LABEL or "Send", send)
    composer.send:SetPoint("RIGHT", composer.cancel, "LEFT", -4, 0)

    composer.box = createFrame("EditBox", composer, "InputBoxTemplate")
    composer.box:SetHeight(20)
    composer.box:SetAutoFocus(false)
    composer.box:SetMaxLetters(255)
    -- Clear of the label, and of the template's left edge drawn outside it.
    composer.box:SetPoint("LEFT", composer.label, "RIGHT", 12, 0)
    composer.box:SetPoint("RIGHT", composer.send, "LEFT", -8, 0)
    composer.box:SetScript("OnEnterPressed", send)
    -- Escape drops the whisper and leaves the board open.
    composer.box:SetScript("OnEscapePressed", close)

    composer:SetScript("OnShow", function()
        if board.footer then
            board.footer:Hide()
        end
    end)
    composer:SetScript("OnHide", function()
        composer.box:ClearFocus()
        composer.target = nil
        if board.footer then
            board.footer:Show()
        end
    end)
    board:HookScript("OnHide", close)
    composer:Hide()
end

--- Open the board with a whisper to the view's poster written at its foot,
-- so Enter sends it.
function Whisper.Open(view)
    ns.Window.Open()
    if not composer then
        create(ns.Window.Frame())
    end

    local text = Whisper.Message(view)
    composer.target = view.whisperName or view.name
    composer.label:SetText("To " .. composer.target .. ":")
    composer:Show()
    composer.box:SetText(text)
    composer.box:SetFocus()
    composer.box:SetCursorPosition(#text)
end

--- Put a link into the whisper being written. False with none open.
function Whisper.Insert(text)
    if not (composer and composer:IsShown() and text) then
        return false
    end
    composer.box:Insert(text)
    composer.box:SetFocus()
    return true
end

--- The whisper line, once a whisper has been opened; nil before.
function Whisper.Composer()
    return composer
end
