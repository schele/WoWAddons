-- A stand-in for the parts of the WoW client LinkTranslate touches: the
-- names it gives quests, items and spells, loading the ones it does not have
-- yet, chat filters, chat windows' history, the pointed-at-link event, the
-- tooltip and the options window. Widgets record what was done to them so
-- tests can assert on it.
--
-- Shaped after the Forever client's own interface code (Gethe/wow-ui-source,
-- branch "forever", 1.60.1): ChatFrameFilters.lua runs each filter as
-- (chatFrame, event, message, ...) and takes "false, changed line, ..." back;
-- ScrollingMessageFrame.lua's TransformMessages rewrites lines already shown;
-- ChatFrame.lua announces a pointed-at link on EventRegistry.

local stub = {}

local function makeWidget(kind, parent)
    local widget = {
        kind = kind,
        parent = parent,
        scripts = {},
        registeredEvents = {},
        points = {},
        shown = true,
    }

    function widget:SetScript(name, fn) self.scripts[name] = fn end
    function widget:GetScript(name) return self.scripts[name] end
    function widget:HookScript(name, fn)
        local existing = self.scripts[name]
        self.scripts[name] = function(...)
            if existing then existing(...) end
            fn(...)
        end
    end
    function widget:SetPoint(...) table.insert(self.points, { ... }) end
    function widget:ClearAllPoints() self.points = {} end
    function widget:SetSize(w, h) self.width, self.height = w, h end
    function widget:SetWidth(value) self.width = value end
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
    function widget:IsShown() return self.shown end
    function widget:CreateTexture() return makeWidget("Texture", self) end
    function widget:CreateFontString() return makeWidget("FontString", self) end
    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text end
    function widget:SetJustifyH(value) self.justifyH = value end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end

    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end
    function widget:Hears(event) return self.registeredEvents[event] == true end

    -- Test helper: drive this widget's OnEvent handler.
    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then handler(self, event, ...) end
    end

    return widget
end

stub.makeWidget = makeWidget

--- A chat window: the lines it holds, oldest first, as the client keeps them
-- (message, r, g, b, extra data).
local function makeChatFrame(name)
    local frame = makeWidget("ScrollingMessageFrame")
    frame.frameName = name
    frame.lines = {}

    function frame:AddMessage(message, r, g, b, ...)
        table.insert(self.lines, table.pack(message, r, g, b, ...))
    end

    function frame:LineText(index)
        local line = self.lines[index]
        return line and line[1]
    end

    -- As ScrollingMessageFrameMixin:TransformMessages: each line the
    -- predicate picks is replaced by what the transform returns for it.
    function frame:TransformMessages(predicate, transform)
        for index, line in ipairs(self.lines) do
            if predicate(table.unpack(line, 1, line.n)) then
                self.lines[index] = table.pack(transform(table.unpack(line, 1, line.n)))
            end
        end
    end

    return frame
end

stub.makeChatFrame = makeChatFrame

function stub.newEnv()
    local env = setmetatable({}, { __index = _G })

    env.__frames = {}
    env.__printed = {}
    env._G = env

    env.UIParent = makeWidget("Frame")
    env.SlashCmdList = {}

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do pieces[index] = tostring((select(index, ...))) end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    function env.CreateFrame(kind, name, parent)
        local frame = makeWidget(kind or "Frame", parent)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        return frame
    end

    env.__timers = {}
    env.C_Timer = { After = function(_, fn) table.insert(env.__timers, fn) end }

    -- What this client calls things, in its own language, by id: what it has
    -- loaded (__names) and what it would load if asked (__loadable). An item
    -- is its bare name, or { name, shown } when its link says more ("of the
    -- Bear").
    env.__names = { quest = {}, item = {}, spell = {} }
    env.__loadable = { quest = {}, item = {}, spell = {} }
    -- Every load asked for, as "quest:2945", in order.
    env.__requests = {}
    local function ask(kind, id) table.insert(env.__requests, kind .. ":" .. id) end

    env.C_QuestLog = {
        GetTitleForQuestID = function(id) return env.__names.quest[id] end,
        RequestLoadQuestByID = function(id) ask("quest", id) end,
    }

    env.C_Item = {
        GetItemInfo = function(itemString)
            local id = tonumber(tostring(itemString):match("^item:(%d+)") or itemString)
            local entry = env.__names.item[id]
            if not entry then return nil end
            local name, shown = entry, entry
            if type(entry) == "table" then name, shown = entry[1], entry[2] end
            return name, string.format("|cff1eff00|H%s|h[%s]|h|r", itemString, shown), 2
        end,
        RequestLoadItemDataByID = function(id) ask("item", id) end,
    }

    env.C_Spell = {
        GetSpellName = function(id) return env.__names.spell[id] end,
        RequestLoadSpellData = function(id) ask("spell", id) end,
    }

    -- Chat filters, by event, in the order they were added.
    env.__filters = {}
    env.ChatFrameUtil = {
        AddMessageEventFilter = function(event, fn)
            env.__filters[event] = env.__filters[event] or {}
            table.insert(env.__filters[event], fn)
        end,
    }
    env.ChatFrame_AddMessageEventFilter = env.ChatFrameUtil.AddMessageEventFilter

    -- Two chat windows, as FloatingChatFrame.lua lists them.
    env.ChatFrame1 = makeChatFrame("ChatFrame1")
    env.ChatFrame2 = makeChatFrame("ChatFrame2")
    env.CHAT_FRAMES = { "ChatFrame1", "ChatFrame2" }
    env.NUM_CHAT_WINDOWS = 2

    -- The pointed-at link, Forever's way: ChatFrameMixin hands it to
    -- EventRegistry, which calls each listener with its owner first.
    env.ChatFrameMixin = { OnHyperlinkEnter = function() end }
    env.__callbacks = {}
    env.EventRegistry = {
        RegisterCallback = function(_, event, fn, owner)
            env.__callbacks[event] = { fn = fn, owner = owner }
        end,
    }

    -- The tooltip: who owns it and the lines on it, as { text, r, g, b }.
    local tooltip = makeWidget("GameTooltip", env.UIParent)
    tooltip.shown = false
    tooltip.lines = {}
    function tooltip:SetOwner(owner, anchor) self.owner, self.anchor, self.lines = owner, anchor, {} end
    function tooltip:GetOwner() return self.owner end
    function tooltip:SetText(text, r, g, b) self.lines = { { text, r, g, b } } end
    function tooltip:AddLine(text, r, g, b) table.insert(self.lines, { text, r, g, b }) end
    env.GameTooltip = tooltip

    -- A secret line of chat: the client says it is a string, but reading it
    -- in any way raises.
    local secretMeta = {
        __index = function() error("attempt to index a secret string value") end,
        __tostring = function() return "<secret string>" end,
    }
    function env.__secret() return setmetatable({}, secretMeta) end
    function env.type(value)
        if getmetatable(value) == secretMeta then return "string" end
        return type(value)
    end

    -- The game's options window and the game menu, both closed.
    env.SettingsPanel = makeWidget("Frame", env.UIParent)
    env.SettingsPanel.shown = false
    env.GameMenuFrame = makeWidget("Frame", env.UIParent)
    env.GameMenuFrame.shown = false
    function env.HideUIPanel(frame) if frame and frame.Hide then frame:Hide() end end
    env.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            return { name = name, frame = frame, GetID = function() return "category-id" end }
        end,
        RegisterAddOnCategory = function(category) env.__settingsCategory = category end,
        OpenToCategory = function(id) env.__openedCategory = id end,
    }
    env.C_AddOns = {
        GetAddOnMetadata = function(_, field) return field == "Version" and "9.9.9" or nil end,
    }

    return env
end

return stub
