local addonName, ns = ...

-- Who new mail goes to by default: usually a bank character. Chosen from an
-- arrow at the right end of the To box (or the settings page), which lists
-- your other characters on this realm and side, and put in To whenever the
-- Send Mail tab opens or empties after a send, unless a name is there.
--
-- Shared by your characters on the realm and side: they all send to the
-- same bank character. The game has no list of an account's characters, so
-- MailHandler notes each one as it logs in.

local Recipient = {}
ns.Recipient = Recipient

local TITLE = "Send new mail to"
local NOBODY = "Nobody"

--- MailHandlerDB, saved for the whole account: { characters = { [realm] =
-- { [name] = { faction, class } } }, defaults = { [realm|faction] = name } }.
local function saved()
    if type(MailHandlerDB) ~= "table" then
        MailHandlerDB = {}
    end
    MailHandlerDB.characters = type(MailHandlerDB.characters) == "table" and MailHandlerDB.characters or {}
    MailHandlerDB.defaults = type(MailHandlerDB.defaults) == "table" and MailHandlerDB.defaults or {}
    return MailHandlerDB
end

local function realm()
    return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
end

--- The first name alone. The first word: with the game's regional unique
-- names, UnitName can hand back first name and surname together.
local function firstName()
    local name = UnitName("player")
    return type(name) == "string" and (name:match("^(%S+)") or name) or name
end

--- The name a mail to this character takes. On WoW Forever that is the
-- first name and the surname ("Bankwoman Alyssa"), as the game's own
-- NameUtil joins them; elsewhere the name alone.
local function me()
    local full = NameUtil and NameUtil.GetUnmodifiedUnitFullName
        and ns.Guarded(function() return NameUtil.GetUnmodifiedUnitFullName("player") end)
    if type(full) == "string" and full ~= "" then
        return full
    end
    return firstName()
end

local function isMe(name)
    return name == me() or name == firstName()
end

local function side()
    return (UnitFactionGroup("player")) or ""
end

local function key()
    return realm() .. "|" .. side()
end

local function textOf(box)
    local text = box and box.GetText and box:GetText()
    return type(text) == "string" and text or ""
end

--- Note the character logged in, for the others' lists.
function Recipient.Remember()
    local name = me()
    if type(name) ~= "string" or name == "" then
        return
    end
    local db = saved()
    local here = db.characters[realm()] or {}
    db.characters[realm()] = here
    local _, class = UnitClass("player")
    here[name] = { faction = side(), class = class }

    -- An earlier MailHandler noted Forever characters by their first name
    -- alone, which no mail reaches: the full name takes its place, as the
    -- default too.
    local first = firstName()
    if first and first ~= name then
        here[first] = nil
        local prefix = realm() .. "|"
        for key, value in pairs(db.defaults) do
            if value == first and key:sub(1, #prefix) == prefix then
                db.defaults[key] = name
            end
        end
    end
end

--- Your other characters on this realm and side, by name: { name, class }.
function Recipient.Characters()
    local list = {}
    for name, info in pairs(saved().characters[realm()] or {}) do
        if not isMe(name) and type(info) == "table" and info.faction == side() then
            list[#list + 1] = { name = name, class = info.class }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

--- The default recipient, or nil: never yourself, since nobody mails
-- themselves.
function Recipient.Default()
    local name = saved().defaults[key()]
    if type(name) ~= "string" or name == "" or isMe(name) then
        return nil
    end
    return name
end

function Recipient.SetDefault(name)
    if type(name) == "string" then
        name = name:match("^%s*(.-)%s*$")
    end
    name = (type(name) == "string" and name ~= "") and name or nil
    -- A full name picked for a character noted by its first name alone
    -- takes that one's place on the list.
    local first = name and name:match("^(%S+)%s+%S")
    local here = saved().characters[realm()]
    if first and here and type(here[first]) == "table" and not here[name] then
        here[name], here[first] = here[first], nil
    end
    saved().defaults[key()] = name
    if ns.SettingsPanel and ns.SettingsPanel.Refresh then
        ns.SettingsPanel.Refresh()
    end
end

--- Put the default in To, if To is empty: not while a forward fills the
-- tab with its own name. Selected, so typing another name replaces it.
function Recipient.Fill()
    local box = SendMailNameEditBox
    local name = Recipient.Default()
    if not (box and name) or textOf(box) ~= "" then
        return
    end
    if ns.Forwarder and ns.Forwarder.Running() then
        return
    end
    box:SetText(name)
    if box.HighlightText then
        box:HighlightText()
    end
end

local function colored(character)
    local color = RAID_CLASS_COLORS and character.class and RAID_CLASS_COLORS[character.class]
    if color and color.colorStr then
        return string.format("|c%s%s|r", color.colorStr, character.name)
    end
    return character.name
end

--- A name picked from the list: the default from now on, and in To now.
-- Nobody takes the old default out of To as well.
local function pick(name)
    local old = Recipient.Default()
    Recipient.SetDefault(name)
    local box = SendMailNameEditBox
    if not box then
        return
    end
    if name then
        if textOf(box) ~= name then
            box:SetText(name)
        end
    elseif old and textOf(box) == old then
        box:SetText("")
    end
end

--- The list, under `owner`: your characters, the default if it is someone
-- else, the name typed in To when `withTyped`, and Nobody.
function Recipient.OpenMenu(owner, withTyped)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(TITLE)
        local function isSelected(name) return Recipient.Default() == name end
        local function setSelected(name) pick(name) end

        local listed = {}
        local function add(name, text)
            if listed[name] or isMe(name) then
                return
            end
            listed[name] = true
            root:CreateRadio(text or name, isSelected, setSelected, name)
        end
        for _, character in ipairs(Recipient.Characters()) do
            add(character.name, colored(character))
        end
        local default = Recipient.Default()
        if default then
            add(default)
        end
        local typed = withTyped and textOf(SendMailNameEditBox):match("^%s*(.-)%s*$") or ""
        if typed ~= "" then
            add(typed)
        end
        if next(listed) == nil then
            root:CreateTitle("Log in on your other characters once, or type a name in To.")
        end

        root:CreateDivider()
        root:CreateRadio(NOBODY, function() return Recipient.Default() == nil end, function() pick(nil) end)
    end)
end

local function showTooltip(button)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(TITLE)
    local default = Recipient.Default()
    GameTooltip:AddLine(default and ("New mail goes to " .. default .. ".") or "New mail starts with no name.", 1, 1, 1)
    GameTooltip:AddLine("Click to choose.", 1, 1, 1)
    GameTooltip:Show()
end

--- The "Postage:" label: a nameless text hanging off the left of the postage
-- amount, top right of the Send Mail tab, so it moves as the amount grows.
local function postageLabel()
    local frame = SendMailCostMoneyFrame
    if not (frame and frame.GetRegions) then
        return nil
    end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString"
            and region.GetText and region:GetText() == SEND_MAIL_COST then
            return region
        end
    end
    return nil
end

local function makeButton()
    if Recipient.button or not (SendMailFrame and SendMailNameEditBox) then
        return
    end
    local button = CreateFrame("Button", "MailHandlerRecipientButton", SendMailFrame)
    -- Between the To box and "Postage:", which on Forever are only about
    -- twenty apart: hung off the label, it ends just before it, whatever the
    -- postage, where hung off the box it ran over the label's first letters.
    local label = postageLabel()
    if label then
        button:SetSize(18, 18)
        button:SetPoint("RIGHT", label, "LEFT", -2, 0)
    else
        button:SetSize(24, 24)
        button:SetPoint("LEFT", SendMailNameEditBox, "RIGHT", 2, 0)
    end
    button:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    button:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", function(self)
        Recipient.OpenMenu(self, true)
    end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    Recipient.button = button
end

-- The game opens the tab through MailFrameTab_OnClick and empties it after
-- a send through SendMailFrame_Reset, both by name, so hooks on them run.
local hooked = false

local function hook()
    if hooked or not hooksecurefunc or not (MailFrameTab_OnClick and SendMailFrame_Reset) then
        return
    end
    hooked = true
    hooksecurefunc("MailFrameTab_OnClick", function(self, tabID)
        local tab = tabID or (self and self.GetID and self:GetID())
        if tab == 2 then
            Recipient.Fill()
        end
    end)
    hooksecurefunc("SendMailFrame_Reset", Recipient.Fill)
    makeButton()
end

-- The mail frame is in place before addons load; should it not be, it is
-- by the time the mailbox opens.
hook()
local events = CreateFrame("Frame")
events:RegisterEvent("MAIL_SHOW")
events:SetScript("OnEvent", hook)

ns.OnLogin(Recipient.Remember)
