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
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text end
    function widget:CreateFontString() return makeWidget(env, "FontString", self) end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end
    function widget:SetEnabled(value) self.enabled = value and true or false end
    function widget:IsEnabled() return self.enabled end
    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:SetShown(value) self.shown = value and true or false end
    function widget:IsShown() return self.shown end

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

    -- The game's inbox: seven rows a page, each with its icon button, the
    -- page buttons and Open All at the bottom.
    env.INBOXITEMS_TO_DISPLAY = 7
    env.ATTACHMENTS_MAX_RECEIVE = 12
    env.UIParent = makeWidget(env, "Frame")
    env.InboxFrame = makeWidget(env, "Frame", env.UIParent)
    env.InboxFrame.pageNum = 1
    for row = 1, 7 do
        env["MailItem" .. row] = makeWidget(env, "Frame", env.InboxFrame)
        env["MailItem" .. row .. "Button"] = makeWidget(env, "Button", env["MailItem" .. row])
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
    -- An item the client has not loaded yet has no name, but its ID and
    -- HasInboxItem still say it is there.
    function env.GetInboxItem(index, slot)
        local mail = env.__mails[index]
        local item = mail and mail.items[slot]
        if item then return item.name, 1000 + slot, "icon", item.count, 1, true end
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
            env.__money = env.__money + mail.money
            mail.money = 0
            emptied(mail)
        end)
    end
    function env.TakeInboxItem(index, slot)
        table.insert(env.__log, "item " .. index .. ":" .. slot)
        local mail = env.__mails[index]
        if not (mail and mail.items[slot]) or env.__freeSlots <= 0 then return end
        answer(mail, function()
            mail.items[slot] = nil
            env.__freeSlots = env.__freeSlots - 1
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

    return env
end

--- Forever's inbox: the mainline mail frame, which redraws with
-- InboxFrame:Update() and has no global InboxFrame_Update.
function stub.useForeverInbox(env)
    env.InboxFrame_Update = nil
    function env.InboxFrame:Update()
        env.__redraws = env.__redraws + 1
    end
end

return stub
