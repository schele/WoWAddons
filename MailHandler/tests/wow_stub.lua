-- A minimal stand-in for the WoW API, enough to load MailHandler outside
-- the game: frames, the inbox and its rows, a server that answers takes,
-- bags, money and timers. It records what was done so tests can assert on it.

local stub = {}

local function makeWidget(env, kind, parent, template)
    local widget = {
        kind = kind,
        parent = parent,
        template = template,
        scripts = {},
        registeredEvents = {},
        points = {},
        shown = true,
        enabled = true,
        checked = false,
    }

    function widget:SetScript(name, fn) self.scripts[name] = fn end
    function widget:GetScript(name) return self.scripts[name] end
    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end
    function widget:SetPoint(...) table.insert(self.points, { ... }) end
    function widget:ClearAllPoints() self.points = {} end
    function widget:GetPoint(index)
        local point = self.points[index or 1]
        if point then return table.unpack(point) end
    end
    function widget:SetSize(w, h) self.width, self.height = w, h end
    function widget:SetWidth(value) self.width = value end
    function widget:GetWidth() return self.width or 0 end
    function widget:GetParent() return self.parent end
    -- An edit box hears its text change, from code as from typing, as the
    -- client's does.
    function widget:SetText(value)
        self.text = value
        if self.kind == "EditBox" and self.scripts.OnTextChanged then
            self.scripts.OnTextChanged(self, false)
        end
    end
    function widget:GetText() return self.text end
    function widget:HookScript(name, fn)
        local original = self.scripts[name]
        self.scripts[name] = function(...)
            if original then original(...) end
            fn(...)
        end
    end
    function widget:CreateFontString()
        local text = makeWidget(env, "FontString", self)
        self.regions = self.regions or {}
        table.insert(self.regions, text)
        return text
    end
    function widget:GetRegions() return table.unpack(self.regions or {}) end
    function widget:GetObjectType() return self.kind end
    function widget:SetNormalFontObject(font) self.fonts = self.fonts or {}; self.fonts.normal = font end
    function widget:SetHighlightFontObject(font) self.fonts = self.fonts or {}; self.fonts.highlight = font end
    function widget:SetDisabledFontObject(font) self.fonts = self.fonts or {}; self.fonts.disabled = font end
    function widget:GetNumPoints() return #self.points end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end
    function widget:SetEnabled(value) self.enabled = value and true or false end
    function widget:IsEnabled() return self.enabled end
    -- Showing and hiding fire their scripts, and only on a real transition,
    -- the way the client does.
    function widget:Show()
        if self.shown then return end
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function widget:Hide()
        if not self.shown then return end
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function widget:SetShown(value)
        if value then self:Show() else self:Hide() end
    end
    -- For the settings page.
    function widget:CreateTexture() return makeWidget(env, "Texture", self) end
    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
    function widget:SetJustifyH(value) self.justifyH = value end
    function widget:IsShown() return self.shown end
    -- For edit boxes: Classic Era's mail text box is a scrolling one, read
    -- with GetInputText.
    function widget:SetFocus() env.__focus = self end
    function widget:ClearFocus() if env.__focus == self then env.__focus = nil end end
    function widget:GetInputText() return self.text or "" end
    function widget:GetHeight() return self.height or 0 end
    function widget:SetHeight(value) self.height = value end
    function widget:HighlightText() self.highlighted = true end
    function widget:SetNormalTexture(value) self.normalTexture = value end
    function widget:SetPushedTexture(value) self.pushedTexture = value end
    function widget:SetHighlightTexture(value) self.highlightTexture = value end
    function widget:SetTextColor(r, g, b) self.textColor = { r, g, b } end

    -- Test helper: drive this widget's OnEvent handler.
    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then handler(self, event, ...) end
    end
    -- Test helper: a click, which a disabled button ignores. A check button
    -- flips before its script runs, as the client's does.
    function widget:Click(mouseButton)
        if not self.enabled then return end
        if self.template == "UICheckButtonTemplate" then
            self.checked = not self.checked
        end
        if self.scripts.OnClick then
            self.scripts.OnClick(self, mouseButton or "LeftButton")
        end
    end

    return widget
end

function stub.newEnv()
    local env = setmetatable({}, { __index = _G })

    env._G = env
    env.__frames = {}
    env.__printed = {}

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do
            pieces[index] = tostring((select(index, ...)))
        end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    function env.CreateFrame(kind, name, parent, template)
        local frame = makeWidget(env, kind or "Frame", parent, template)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        return frame
    end

    -- Who is logged in: name, realm, faction and class file. A test logs in
    -- another character by changing these before login.
    env.__player = { name = "Skyler", realm = "Forever", faction = "Alliance", class = "WARRIOR" }
    -- On WoW Forever a character has a first name and a surname: UnitName
    -- hands back both, and the game's NameUtil joins them with a space
    -- (Camelot/NameUtil.lua). Without a surname, the first name alone.
    function env.UnitName(unit)
        if unit == "player" then return env.__player.name, env.__player.surname end
    end
    env.UnitNameUnmodified = env.UnitName
    env.NameUtil = {
        GetUnmodifiedUnitFullName = function(unit)
            local name, surname = env.UnitNameUnmodified(unit)
            if surname then return name .. " " .. surname end
            return name
        end,
    }
    function env.GetNormalizedRealmName() return env.__player.realm end
    function env.GetRealmName() return env.__player.realm end
    function env.UnitFactionGroup(unit)
        if unit == "player" then return env.__player.faction, env.__player.faction end
    end
    function env.UnitClass(unit)
        if unit == "player" then return env.__player.class, env.__player.class end
    end
    env.RAID_CLASS_COLORS = {
        WARRIOR = { colorStr = "ffc69b6d" },
        PRIEST = { colorStr = "ffffffff" },
        DRUID = { colorStr = "ffff7c0a" },
        MAGE = { colorStr = "ff3fc7eb" },
    }

    -- The game's menus (MenuUtil): what one was built from, so a test can
    -- read the entries back and pick one the way a click would.
    local function makeMenuRoot()
        local root = { entries = {} }
        local function add(entry)
            table.insert(root.entries, entry)
            return entry
        end
        function root:CreateTitle(text) return add({ kind = "title", text = text }) end
        function root:CreateButton(text, callback) return add({ kind = "button", text = text, callback = callback }) end
        function root:CreateRadio(text, isSelected, setSelected, data)
            return add({
                kind = "radio", text = text, data = data,
                selected = function() return isSelected(data) end,
                pick = function() setSelected(data) end,
            })
        end
        function root:CreateDivider() return add({ kind = "divider" }) end
        --- An entry by its text, colour codes and all stripped.
        function root:Find(text)
            for _, entry in ipairs(self.entries) do
                local plain = entry.text and entry.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                if plain == text then return entry end
            end
        end
        return root
    end
    env.MenuUtil = {
        CreateContextMenu = function(owner, generator)
            local root = makeMenuRoot()
            generator(owner, root)
            env.__menu, env.__menuOwner = root, owner
            return root
        end,
    }

    -- The tooltip: whose it is and its lines.
    env.GameTooltip = makeWidget(env, "GameTooltip", nil)
    env.GameTooltip.shown = false
    env.GameTooltip.lines = {}
    function env.GameTooltip:SetOwner(owner) self.owner, self.lines = owner, {} end
    function env.GameTooltip:SetText(text) self.lines = { text } end
    function env.GameTooltip:AddLine(text) table.insert(self.lines, text) end

    -- Hooks a global function, or a method when given a table first.
    function env.hooksecurefunc(owner, name, fn)
        if type(owner) ~= "table" then
            owner, name, fn = env, owner, name
        end
        local original = owner[name]
        owner[name] = function(...)
            local results = { original(...) }
            fn(...)
            return table.unpack(results)
        end
    end

    -- The game's options window, and the addon's own .toc.
    env.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            return { name = name, frame = frame, GetID = function() return "category-id" end }
        end,
        RegisterAddOnCategory = function(category) env.__settingsCategory = category end,
    }
    env.C_AddOns = {
        GetAddOnMetadata = function(_, field)
            return field == "Version" and "9.9.9" or nil
        end,
    }

    -- The game's inbox: seven rows a page, each with its icon button, the
    -- page buttons and Open All at the bottom.
    env.INBOXITEMS_TO_DISPLAY = 7
    env.ATTACHMENTS_MAX_RECEIVE = 12
    env.UIParent = makeWidget(env, "Frame")
    env.GameFontNormalSmall = { name = "GameFontNormalSmall" }
    env.GameFontHighlightSmall = { name = "GameFontHighlightSmall" }
    env.GameFontDisableSmall = { name = "GameFontDisableSmall" }
    -- The mail window, and the inbox inside it. On Classic Era the inbox
    -- is wider than the window, so only the window's right edge is the
    -- one players see.
    env.MailFrame = makeWidget(env, "Frame", env.UIParent)
    env.InboxFrame = makeWidget(env, "Frame", env.MailFrame)
    env.InboxFrame.pageNum = 1
    for row = 1, 7 do
        env["MailItem" .. row] = makeWidget(env, "Frame", env.InboxFrame)
        env["MailItem" .. row .. "Button"] = makeWidget(env, "Button", env["MailItem" .. row])
        env["MailItem" .. row .. "Button"]:SetPoint("TOPLEFT", env["MailItem" .. row], "TOPLEFT", 0, 0)
        -- The text hangs off the row, not the icon, as the game's does.
        local sender = env["MailItem" .. row]:CreateFontString()
        sender:SetPoint("TOPLEFT", env["MailItem" .. row], "TOPLEFT", 44, -2)
        sender:SetWidth(225)
        env["MailItem" .. row .. "Sender"] = sender
        local subject = env["MailItem" .. row]:CreateFontString()
        subject:SetPoint("TOPLEFT", sender, "BOTTOMLEFT", 0, -1)
        subject:SetWidth(240)
        env["MailItem" .. row .. "Subject"] = subject
        local expires = env["MailItem" .. row]:CreateFontString()
        expires:SetPoint("TOPRIGHT", env["MailItem" .. row], "TOPRIGHT", -4, -2)
        env["MailItem" .. row .. "ExpireTime"] = expires
    end
    env.InboxPrevPageButton = makeWidget(env, "Button", env.InboxFrame)
    env.OpenAllMail = makeWidget(env, "Button", env.InboxFrame, "UIPanelButtonTemplate")
    env.OpenAllMail.width = 120
    env.OpenAllMail:SetPoint("BOTTOM", env.InboxFrame, "BOTTOM", 0, 101)
    env.__redraws = 0
    function env.InboxFrame_Update() env.__redraws = env.__redraws + 1 end

    -- Timers run when a test says so. The server's answers to takes made
    -- before a round land after its timers, so a look always comes first.
    env.__timers = {}
    env.__timerDelays = {}
    env.__replies = {}
    env.C_Timer = {
        After = function(delay, fn)
            table.insert(env.__timerDelays, delay)
            table.insert(env.__timers, fn)
        end,
    }
    function env.__runTimers()
        local pending, replies = env.__timers, env.__replies
        env.__timers, env.__replies = {}, {}
        for _, fn in ipairs(pending) do fn() end
        for _, fn in ipairs(replies) do fn() end
    end
    function env.__runAllTimers()
        for _ = 1, 1000 do
            if #env.__timers == 0 and #env.__replies == 0 then return end
            env.__runTimers()
        end
        error("timers never stopped queuing")
    end

    -- The mailbox, top to bottom, and the server behind it.
    env.__mails = {}
    env.__money = 0
    env.__freeSlots = 10
    env.__log = {}
    -- A server that answers late, and one that removes a mail once it is
    -- empty, as the game may do with auction mail.
    env.__slowServer = false
    env.__autoRemove = false

    local function itemCount(mail)
        local count = 0
        for _ in pairs(mail.items) do count = count + 1 end
        return count
    end

    local function emptied(mail)
        if env.__autoRemove and mail.money == 0 and itemCount(mail) == 0 then
            for index, other in ipairs(env.__mails) do
                if other == mail then
                    table.remove(env.__mails, index)
                    return
                end
            end
        end
    end

    local function answer(mail, fn)
        if mail.lost then return end
        if env.__slowServer then
            table.insert(env.__replies, fn)
        else
            fn()
        end
    end

    function env.GetInboxNumItems() return #env.__mails, #env.__mails end
    function env.GetInboxHeaderInfo(index)
        local mail = env.__mails[index]
        if not mail then return nil end
        if mail.raises then error("attempt to compare a secret value") end
        return "icon", nil, mail.sender, mail.subject, mail.money, mail.cod, 29.5,
            itemCount(mail), false, false, false, true, false
    end
    -- An item's ID, the same for every item of that name. One not loaded
    -- yet has no name, but has an ID all the same.
    env.__ids = {}
    function env.__itemID(name)
        name = name or "(not loaded)"
        if not env.__ids[name] then
            local count = 0
            for _ in pairs(env.__ids) do count = count + 1 end
            env.__ids[name] = 2000 + count
        end
        return env.__ids[name]
    end

    -- An item the client has not loaded yet has no name, but its ID and
    -- HasInboxItem still say it is there.
    function env.GetInboxItem(index, slot)
        local mail = env.__mails[index]
        local item = mail and mail.items[slot]
        if item then return item.name, env.__itemID(item.name), "icon", item.count, 1, true end
    end
    -- A mail's text, and for an auction house invoice, what it was for.
    function env.GetInboxText(index)
        local mail = env.__mails[index]
        if not mail then return nil end
        mail.read = true
        return mail.text, nil, nil, true, mail.invoice ~= nil
    end
    function env.GetInboxInvoiceInfo(index)
        local mail = env.__mails[index]
        local invoice = mail and mail.invoice
        if invoice then
            return invoice.type, invoice.item, invoice.player, invoice.bid or 0, 0, 0, 0, 0, 0, 0, invoice.count or 1
        end
    end
    function env.HasInboxItem(index, slot)
        local mail = env.__mails[index]
        return mail ~= nil and mail.items[slot] ~= nil
    end
    function env.TakeInboxMoney(index)
        table.insert(env.__log, "money " .. index)
        local mail = env.__mails[index]
        if not mail then return end
        answer(mail, function()
            -- With __moneyLags, the mail shows its gold gone at once but the
            -- purse catches up only later, as the client's can.
            if env.__moneyLags then
                env.__moneyOwed = (env.__moneyOwed or 0) + mail.money
            else
                env.__money = env.__money + mail.money
            end
            mail.money = 0
            emptied(mail)
        end)
    end
    -- With real bags (stub.useBags), the item goes into them; otherwise
    -- only the count of free slots goes down.
    function env.TakeInboxItem(index, slot)
        table.insert(env.__log, "item " .. index .. ":" .. slot)
        local mail = env.__mails[index]
        local item = mail and mail.items[slot]
        if not item then return end
        if env.__bags then
            if not env.__fits(item) then return end
        elseif env.__freeSlots <= 0 then
            return
        end
        answer(mail, function()
            mail.items[slot] = nil
            if env.__bags and env.__bagsLag then
                -- The mail shows the item gone a moment before the bags
                -- show it come.
                table.insert(env.__replies, function() env.__store(item) end)
            elseif env.__bags then
                env.__store(item)
            else
                env.__freeSlots = env.__freeSlots - 1
            end
            emptied(mail)
        end)
    end
    function env.DeleteInboxItem(index) table.insert(env.__log, "delete " .. index) end
    function env.GetMoney() return env.__money end

    -- Bags: the free slots for anything are in the backpack; bag 1 is a
    -- quiver, whose free slots take only ammunition.
    env.__quiverFree = 0
    env.C_Container = {
        GetContainerNumFreeSlots = function(bag)
            if bag == 0 then return env.__freeSlots, 0 end
            if bag == 1 then return env.__quiverFree, 1 end
            return 0, 0
        end,
    }

    function env.__fire(event, ...)
        local frames = {}
        for index, frame in ipairs(env.__frames) do frames[index] = frame end
        for _, frame in ipairs(frames) do
            if frame.registeredEvents[event] then frame:Fire(event, ...) end
        end
    end

    -- The open mail, beside the inbox: Reply, Delete and Close along its
    -- bottom, Reply 82 wide.
    env.OpenMailFrame = makeWidget(env, "Frame", env.UIParent)
    env.OpenMailFrame.shown = false
    env.OpenMailDeleteButton = makeWidget(env, "Button", env.OpenMailFrame, "UIPanelButtonTemplate")
    env.OpenMailReplyButton = makeWidget(env, "Button", env.OpenMailFrame, "UIPanelButtonTemplate")
    env.OpenMailReplyButton:SetSize(82, 22)
    env.OpenMailReplyButton:SetPoint("RIGHT", env.OpenMailDeleteButton, "LEFT", 0, 0)
    function env.OpenMail_Update() env.__openMailRedraws = (env.__openMailRedraws or 0) + 1 end

    -- The Send Mail tab: To, Subject, the text, the gold with its Send
    -- Money and C.O.D. choice, and Send, as Classic Era's (its text box is
    -- MailEditBox; Forever's is SendMailBodyEditBox, see useForeverInbox).
    env.ATTACHMENTS_MAX_SEND = 12
    env.__tab = 1
    env.SendMailFrame = makeWidget(env, "Frame", env.UIParent)
    env.SendMailNameEditBox = makeWidget(env, "EditBox", env.SendMailFrame)
    env.SendMailSubjectEditBox = makeWidget(env, "EditBox", env.SendMailFrame)
    env.MailEditBox = makeWidget(env, "EditBox", env.SendMailFrame)
    env.SendMailMoney = makeWidget(env, "Frame", env.SendMailFrame)
    env.SendMailSendMoneyButton = makeWidget(env, "CheckButton", env.SendMailFrame)
    env.SendMailCODButton = makeWidget(env, "CheckButton", env.SendMailFrame)
    env.SendMailSendMoneyButton.checked = true
    env.SendMailMailButton = makeWidget(env, "Button", env.SendMailFrame, "UIPanelButtonTemplate")
    -- The postage, top right of the tab, its "Postage:" label hanging off its
    -- left and so moving with the amount.
    env.SEND_MAIL_COST = "Postage:"
    env.SendMailCostMoneyFrame = makeWidget(env, "Frame", env.SendMailFrame)
    env.__postageLabel = env.SendMailCostMoneyFrame:CreateFontString()
    env.__postageLabel:SetText(env.SEND_MAIL_COST)
    env.__postageLabel:SetPoint("RIGHT", env.SendMailCostMoneyFrame, "LEFT", -3, 0)
    env.SendMailNameEditBox.text = ""
    env.SendMailSubjectEditBox.text = ""
    env.MailEditBox.text = ""

    local function bodyBox()
        return env.SendMailBodyEditBox or env.MailEditBox
    end
    function env.__body() return bodyBox():GetText() or "" end

    -- Cash on delivery: Classic Era has it; Forever turns it off (see
    -- useForeverInbox).
    env.__codEnabled = true
    env.C_Mail = { IsCODEnabled = function() return env.__codEnabled end }

    -- Send is enabled once there is a name and a subject.
    function env.SendMailFrame_CanSend()
        local name = env.SendMailNameEditBox:GetText() or ""
        local subject = env.SendMailSubjectEditBox:GetText() or ""
        env.SendMailMailButton:SetEnabled(name ~= "" and subject ~= "")
    end
    -- Bound when the boxes were made, as the game's XML binds it: a hook
    -- on the global does not run from these.
    local canSend = env.SendMailFrame_CanSend
    env.SendMailNameEditBox:SetScript("OnTextChanged", function() canSend() end)
    env.SendMailSubjectEditBox:SetScript("OnTextChanged", function() canSend() end)

    -- The gold to send, in a box each for gold, silver and copper. Setting
    -- it writes each box, and each says it changed.
    env.SendMailMoney.boxes = {}
    for _, coin in ipairs({ "Gold", "Silver", "Copper" }) do
        local box = makeWidget(env, "EditBox", env.SendMailMoney)
        box.text = ""
        box:SetScript("OnTextChanged", function() canSend() end)
        env["SendMailMoney" .. coin] = box
        table.insert(env.SendMailMoney.boxes, box)
    end
    function env.MoneyInputFrame_SetCopper(frame, copper)
        frame.copper = copper
        if frame.boxes then
            local parts = { math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100 }
            for index, box in ipairs(frame.boxes) do
                box:SetText(parts[index] > 0 and tostring(parts[index]) or "")
            end
        end
    end
    function env.MoneyInputFrame_GetCopper(frame) return frame.copper or 0 end
    function env.MoneyInputFrame_ResetMoney(frame) env.MoneyInputFrame_SetCopper(frame, 0) end

    function env.MailFrameTab_OnClick(_, tab)
        env.__tab = tab
        if tab == 2 then env.SendMailFrame.sendMode = "send" end
    end
    function env.SendMailRadioButton_OnClick(index)
        env.SendMailSendMoneyButton:SetChecked(index == 1)
        env.SendMailCODButton:SetChecked(index ~= 1)
    end

    -- The game's redraw of the tab, on MAIL_SEND_INFO_UPDATE: with items
    -- on it, and only where cash on delivery is allowed, an empty subject,
    -- or the one it last wrote, becomes the first stack's name and count.
    -- Without, its own subject is cleared. Then Send is enabled, or not.
    env.SendMailFrame.previousItem = ""
    function env.SendMailFrame_Update()
        local count, title = 0, nil
        for index = 1, env.ATTACHMENTS_MAX_SEND do
            if env.HasSendMailItem(index) then
                count = count + 1
                local name, _, _, stack = env.GetSendMailItem(index)
                if not title and name then
                    title = stack <= 1 and name or (name .. " (" .. stack .. ")")
                end
            end
        end
        local frame, subject = env.SendMailFrame, env.SendMailSubjectEditBox
        if count > 0 and env.C_Mail.IsCODEnabled() then
            if subject:GetText() == "" or subject:GetText() == frame.previousItem then
                title = title or ""
                subject:SetText(title)
                frame.previousItem = title
            end
        else
            if subject:GetText() == frame.previousItem then subject:SetText("") end
            frame.previousItem = ""
            env.SendMailRadioButton_OnClick(1)
        end
        env.SendMailFrame_CanSend()
    end
    env.SendMailFrame_CanSend()

    -- What the game's Send does: the gold box becomes the gold sent, or the
    -- C.O.D. asked, then the mail goes.
    env.SendMailMailButton:SetScript("OnClick", function()
        local copper = env.MoneyInputFrame_GetCopper(env.SendMailMoney)
        env.SetSendMailCOD(0)
        env.SetSendMailMoney(0)
        if env.SendMailSendMoneyButton:GetChecked() then
            if copper > 0 then env.SetSendMailMoney(copper) end
        elseif copper > 0 then
            env.SetSendMailCOD(copper)
        end
        local body = env.SendMailBodyEditBox and env.SendMailBodyEditBox:GetText() or env.MailEditBox:GetInputText()
        env.SendMail(env.SendMailNameEditBox:GetText() or "", env.SendMailSubjectEditBox:GetText() or "", body)
    end)

    -- The game's own mail frame: it redraws the Send Mail tab when an item
    -- goes on or comes off, and once a mail has gone, empties the tab in
    -- its order, the gold last. Made before the addon loads, so it hears
    -- each event first.
    -- Emptying the tab once a mail has gone, as Forever's SendMailFrame_Reset
    -- does: the name first, with the cursor put in it.
    function env.SendMailFrame_Reset()
        env.SendMailNameEditBox:SetText("")
        env.SendMailNameEditBox:SetFocus()
        env.SendMailSubjectEditBox:SetText("")
        bodyBox():SetText("")
        env.SendMailFrame_Update()
        env.MoneyInputFrame_ResetMoney(env.SendMailMoney)
        env.SendMailRadioButton_OnClick(1)
    end

    local blizzard = env.CreateFrame("Frame")
    blizzard:RegisterEvent("MAIL_SEND_INFO_UPDATE")
    blizzard:RegisterEvent("MAIL_SEND_SUCCESS")
    blizzard:SetScript("OnEvent", function(_, event)
        if event == "MAIL_SEND_INFO_UPDATE" then
            env.SendMailFrame_Update()
            return
        end
        -- By name, as the game calls it, so a hook on it runs.
        env.SendMailFrame_Reset()
        if env.SendMailFrame.sendMode == "reply" then env.MailFrameTab_OnClick(nil, 1) end
    end)

    -- The items on the Send Mail tab, by attachment slot, and the mails
    -- sent. Attaching needs real bags (stub.useBags).
    env.__send = {}
    env.__sent = {}
    env.__sendMoney, env.__sendCOD = 0, 0
    function env.SetSendMailMoney(copper) env.__sendMoney = copper end
    function env.SetSendMailCOD(copper) env.__sendCOD = copper end
    function env.HasSendMailItem(index) return env.__send[index] ~= nil end
    function env.GetSendMailItem(index)
        local held = env.__send[index] and env.__bags[0].slots[env.__send[index]]
        if held then return held.name, held.id, "icon", held.count, 1 end
    end
    function env.ClickSendMailItemButton() end
    function env.CursorHasItem() return env.__cursor ~= nil end
    function env.ClearCursor() end

    --- A mail sent: its gold leaves the purse and its items the bags. The
    -- server says it has gone a moment later.
    function env.SendMail(to, subject, body)
        local mail = { to = to, subject = subject, body = body, money = env.__sendMoney, cod = env.__sendCOD, items = {} }
        for index = 1, env.ATTACHMENTS_MAX_SEND do
            local slot = env.__send[index]
            if slot then
                local held = env.__bags[0].slots[slot]
                table.insert(mail.items, { name = held.name, count = held.count })
                env.__bags[0].slots[slot] = nil
            end
        end
        env.__send = {}
        env.__money = env.__money - mail.money
        table.insert(env.__sent, mail)
        table.insert(env.__replies, function() env.__fire("MAIL_SEND_SUCCESS") end)
    end

    return env
end

--- Real bags: a backpack of `size` slots, each { id, name, count, stack,
-- bound, locked }, and the cursor. A take tops up the player's own stacks
-- of the item first, then fills empty slots, as the game does. Picking up
-- or splitting a stack locks it; an item put on the Send Mail tab stays
-- in its slot, locked, until the mail goes.
function stub.useBags(env, size)
    local bag = { size = size or 16, slots = {} }
    env.__bags = { [0] = bag }
    env.__cursor = nil
    env.__uiErrors = {}

    local function free()
        local count = 0
        for slot = 1, bag.size do
            if not bag.slots[slot] then count = count + 1 end
        end
        return count
    end

    function env.__fits(item)
        local id, stack, space = env.__itemID(item.name), item.stack or 20, 0
        for slot = 1, bag.size do
            local held = bag.slots[slot]
            if not held then
                space = space + stack
            elseif held.id == id and not held.locked then
                space = space + stack - held.count
            end
        end
        return space >= item.count
    end

    function env.__store(item)
        local id, stack, left = env.__itemID(item.name), item.stack or 20, item.count
        for slot = 1, bag.size do
            local held = bag.slots[slot]
            if left > 0 and held and held.id == id and not held.locked and held.count < stack then
                local add = math.min(stack - held.count, left)
                held.count = held.count + add
                left = left - add
            end
        end
        for slot = 1, bag.size do
            if left > 0 and not bag.slots[slot] then
                local put = math.min(stack, left)
                bag.slots[slot] = { id = id, name = item.name, count = put, stack = stack, bound = item.bound }
                left = left - put
            end
        end
    end

    --- Test helper: the player's own items, in a slot.
    function env.__give(slot, name, count, stack)
        bag.slots[slot] = { id = env.__itemID(name), name = name, count = count, stack = stack or 20 }
    end

    --- Test helper: how many of an item are in the bags, sent or not.
    function env.__held(name)
        local total = 0
        for slot = 1, bag.size do
            local held = bag.slots[slot]
            if held and held.name == name then total = total + held.count end
        end
        return total
    end

    env.C_Container = {
        GetContainerNumSlots = function(which) return which == 0 and bag.size or 0 end,
        GetContainerNumFreeSlots = function(which)
            if which == 0 then return free(), 0 end
            return 0, 0
        end,
        GetContainerItemInfo = function(which, slot)
            local held = which == 0 and bag.slots[slot]
            if not held then return nil end
            return {
                iconFileID = 1, stackCount = held.count, isLocked = held.locked or false, quality = 1,
                isReadable = false, hasLoot = false, isFiltered = false, hasNoValue = false,
                itemID = held.id, isBound = held.bound or false,
                hyperlink = "|cffffffff|Hitem:" .. held.id .. "::::::::60:::::|h[" .. held.name .. "]|h|r",
            }
        end,
        PickupContainerItem = function(which, slot)
            if which ~= 0 then return end
            local held, cursor = bag.slots[slot], env.__cursor
            if not cursor then
                if held and not held.locked then
                    env.__cursor = { slot = slot, count = held.count }
                    held.locked = true
                end
                return
            end
            if cursor.slot == slot then
                held.locked = false
                env.__cursor = nil
                return
            end
            if held then return end
            -- Put down in an empty slot: the server moves it a moment later.
            local source = bag.slots[cursor.slot]
            env.__cursor = nil
            local function place()
                if cursor.count >= source.count then
                    bag.slots[cursor.slot] = nil
                    source.locked = false
                    bag.slots[slot] = source
                else
                    source.count = source.count - cursor.count
                    source.locked = false
                    bag.slots[slot] = { id = source.id, name = source.name, count = cursor.count, stack = source.stack, bound = source.bound }
                end
            end
            if env.__slowServer then
                table.insert(env.__replies, place)
            else
                place()
            end
        end,
        SplitContainerItem = function(which, slot, count)
            local held = which == 0 and bag.slots[slot]
            if env.__cursor or not held or held.locked or count >= held.count then return end
            env.__cursor = { slot = slot, count = count, split = true }
            held.locked = true
        end,
    }

    function env.ClearCursor()
        if env.__cursor then
            bag.slots[env.__cursor.slot].locked = false
            env.__cursor = nil
        end
    end

    -- A soulbound item will not go, and stays on the cursor. Nor will part
    -- of a stack straight off a split: MailHandler must not count on it.
    function env.ClickSendMailItemButton(index)
        local cursor = env.__cursor
        if not cursor or env.__send[index] then return end
        local held = bag.slots[cursor.slot]
        if held.bound then
            table.insert(env.__uiErrors, "You can't mail soulbound items.")
            return
        end
        if cursor.split then
            table.insert(env.__uiErrors, "split stack")
            return
        end
        env.__send[index] = cursor.slot
        env.__cursor = nil
        env.__fire("MAIL_SEND_INFO_UPDATE")
    end

    --- Test helper: the player taking the item at `index` off the Send
    -- Mail tab, back into its slot.
    function env.__detach(index)
        local slot = env.__send[index]
        if not slot then return end
        env.__send[index] = nil
        bag.slots[slot].locked = false
        env.__fire("MAIL_SEND_INFO_UPDATE")
    end
end

--- Forever's inbox: the mainline mail frame, which redraws with
-- InboxFrame:Update() and has no global InboxFrame_Update.
function stub.useForeverInbox(env)
    env.InboxFrame_Update = nil
    function env.InboxFrame:Update()
        env.__redraws = env.__redraws + 1
    end
    -- Its open mail redraws with OpenMailFrame:Update(), and its mail text
    -- box is a plain one.
    env.OpenMail_Update = nil
    function env.OpenMailFrame:Update()
        env.__openMailRedraws = (env.__openMailRedraws or 0) + 1
    end
    env.SendMailBodyEditBox = env.MailEditBox
    env.MailEditBox = nil
    -- No cash on delivery, so the game never writes a subject itself.
    env.__codEnabled = false
end

return stub
