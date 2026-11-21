-- A minimal stand-in for the WoW API, enough to load the addon outside the
-- game. Widgets record what was done to them so tests can assert on it.

local stub = {}

local function makeWidget(kind, parent)
    local widget = {
        kind = kind,
        parent = parent,
        points = {},
        scripts = {},
        registeredEvents = {},
        children = {},
        width = 0,
        height = 0,
        shown = true,
        text = "",
        alpha = 1,
        metricsReady = false,
        left = 0,
        scale = 1,
    }

    function widget:SetPoint(...)
        table.insert(self.points, { ... })
    end

    function widget:ClearAllPoints()
        self.points = {}
    end

    function widget:SetAllPoints() end

    function widget:GetPoint(index)
        local point = self.points[index or 1]
        if point then
            return table.unpack(point)
        end
    end

    function widget:SetWidth(value)
        self.width = value
    end

    function widget:GetWidth()
        return self.width
    end

    function widget:SetHeight(value)
        self.height = value
    end

    function widget:GetHeight()
        return self.height
    end

    function widget:SetSize(w, h)
        self.width, self.height = w, h
    end

    -- Showing and hiding fire their scripts, and only on a real transition,
    -- the way the client does.
    function widget:Show()
        if self.shown then
            return
        end
        self.shown = true
        local handler = self.scripts.OnShow
        if handler then
            handler(self)
        end
    end

    function widget:Hide()
        if not self.shown then
            return
        end
        self.shown = false
        local handler = self.scripts.OnHide
        if handler then
            handler(self)
        end
    end

    function widget:SetShown(value)
        if value then
            self:Show()
        else
            self:Hide()
        end
    end

    function widget:IsShown()
        return self.shown
    end

    function widget:SetScript(name, fn)
        self.scripts[name] = fn
    end

    function widget:GetScript(name)
        return self.scripts[name]
    end

    -- A scroll frame: its child, and how far it can scroll, which a test
    -- sets to stand for laid-out content.
    function widget:SetScrollChild(child) self.scrollChild = child end
    function widget:GetVerticalScrollRange() return self.verticalScrollRange or 0 end
    function widget:SetVerticalScroll(value) self.verticalScroll = value end

    function widget:HookScript(name, fn)
        local existing = self.scripts[name]
        self.scripts[name] = function(...)
            if existing then
                existing(...)
            end
            fn(...)
        end
    end

    function widget:GetName()
        return self.frameName
    end

    function widget:RegisterEvent(event)
        self.registeredEvents[event] = true
    end

    function widget:UnregisterEvent(event)
        self.registeredEvents[event] = nil
    end

    function widget:UnregisterAllEvents()
        self.registeredEvents = {}
    end

    function widget:RegisterForClicks() end
    function widget:RegisterForDrag() end
    -- For a minimap button.
    function widget:SetHighlightTexture(value) self.highlightTexture = value end
    function widget:GetCenter() return self.centerX or 0, self.centerY or 0 end
    function widget:EnableMouse() end
    function widget:SetFrameStrata() end
    function widget:SetFrameLevel() end

    function widget:SetAlpha(value)
        self.alpha = value
    end

    function widget:GetAlpha()
        return self.alpha
    end

    function widget:GetLeft()
        return self.left
    end

    function widget:GetRight()
        return self.right
    end

    function widget:GetEffectiveScale()
        return self.scale
    end

    -- Edges in the widget's own scale, as the client gives them. Nil until a
    -- test says where the widget is, as for a frame not yet laid out.
    function widget:GetTop()
        return self.top
    end

    function widget:GetBottom()
        return self.bottom
    end
    function widget:SetChecked(value)
        self.checked = value and true or false
    end

    function widget:GetChecked()
        return self.checked
    end

    function widget:SetValue(value)
        self.value = value
    end

    function widget:GetValue()
        return self.value
    end

    function widget:SetMinMaxValues(low, high)
        self.minValue, self.maxValue = low, high
    end

    function widget:SetValueStep() end
    function widget:SetObeyStepOnDrag() end

    function widget:SetTextColor(r, g, b, a)
        self.textColor = { r, g, b, a or 1 }
    end

    function widget:GetTextColor()
        local color = self.textColor
        if not color then
            return nil
        end
        return color[1], color[2], color[3], color[4]
    end

    function widget:SetAutoFocus(value)
        self.autoFocus = value and true or false
    end

    function widget:ClearFocus()
        self.focusCleared = true
    end
    function widget:EnableKeyboard(value)
        self.keyboardEnabled = value and true or false
    end

    function widget:SetPropagateKeyboardInput(value)
        self.propagateKeys = value and true or false
    end

    function widget:SetJustifyH() end
    function widget:SetWordWrap() end
    function widget:SetColorTexture(r, g, b, a)
        self.colorTexture = { r, g, b, a }
        self.gradient = nil
    end

    function widget:SetGradient(orientation, from, to)
        self.gradient = { orientation = orientation, from = from, to = to }
    end
    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
    function widget:SetAtlas(atlas, useAtlasSize)
        self.atlas = atlas
        self.useAtlasSize = useAtlasSize
    end
    function widget:GetAtlas() return self.atlas end
    function widget:SetBlendMode(value) self.blendMode = value end
    function widget:SetHitRectInsets(...) self.hitRectInsets = { ... } end
    function widget:SetFont(file, size, flags)
        self.font = { file = file, size = size, flags = flags or "" }
    end

    function widget:SetParent(value)
        self.parent = value
    end

    function widget:GetParent()
        return self.parent
    end

    function widget:SetText(value)
        value = value or ""
        if value ~= self.text then
            self.text = value
            -- The real client cannot measure text until it has been laid out,
            -- which happens on the next frame, not in this call.
            self.metricsReady = false
        end
    end

    function widget:GetText()
        return self.text
    end

    function widget:GetFont()
        local font = self.font
        if font then
            return font.file, font.size, font.flags
        end
        return "Fonts\\FRIZQT__.TTF", 12, ""
    end

    -- Deterministic fake metrics: 6 units per rendered character, and each
    -- inline texture escape counts as one icon rather than its markup length.
    -- Returns 0 until the text has been through a render pass, like the client.
    function widget:GetStringWidth()
        if not self.metricsReady then
            return 0
        end

        local text = tostring(self.text)

        local icons = 0
        for _ in text:gmatch("|T.-|t") do
            icons = icons + 1
        end

        local rendered = text:gsub("|T.-|t", "")
        return #rendered * 6 + icons * 12
    end

    function widget:CreateTexture()
        local texture = makeWidget("Texture", self)
        table.insert(self.children, texture)
        return texture
    end

    function widget:CreateFontString()
        local fontString = makeWidget("FontString", self)
        table.insert(self.children, fontString)
        return fontString
    end

    -- Test helper: drive this widget's OnEvent handler.
    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then
            handler(self, event, ...)
        end
    end

    return widget
end

stub.makeWidget = makeWidget

--- The quest log's top row, as WoW Forever's Blizzard_UIPanels_Game builds it
-- (Gethe/wow-ui-source, branch "forever", 1.60.1), put into `env` as the
-- client's globals: the search box, the quest count beside it and the
-- settings gear at the top right. Camelot's QuestLogQuests_ShowQuestCount
-- sizes the search box (200 wide, or 190 with the gamepad interface) every
-- time the log redraws.
function stub.buildQuestLog(env)
    local scroll = makeWidget("ScrollFrame", env.UIParent)
    scroll.SearchBox = makeWidget("EditBox", scroll)
    scroll.SearchBox:SetSize(301, 20)
    scroll.SettingsDropdown = makeWidget("DropdownButton", scroll)
    env.QuestScrollFrame = scroll
    env.QuestLogCount = makeWidget("Frame", scroll)

    function env.QuestLogQuests_ShowQuestCount()
        env.QuestLogCount:Show()
        if env.__gamepad then
            scroll.SearchBox:SetSize(190, 20)
        else
            scroll.SearchBox:SetSize(200, 20)
        end
    end
end

--- WoW Forever's quest watch list, quest log and maps. Classic Era's
-- C_QuestLog has none of the watch list calls, so it gets none of this.
local function addQuests(env, options)
    -- The quest log, in order: { isHeader = true, title } or { questID, title }.
    env.__log = {}
    -- The tracked quests, in tracker order, and how many the tracker holds.
    env.__watched = {}
    env.__maxWatches = 25
    local function watchIndex(questID)
        for index, id in ipairs(env.__watched) do
            if id == questID then
                return index
            end
        end
    end
    env.C_QuestLog = {
        GetNumQuestLogEntries = function()
            local quests = 0
            for _, entry in ipairs(env.__log) do
                if not entry.isHeader then
                    quests = quests + 1
                end
            end
            return #env.__log, quests
        end,
        GetInfo = function(index)
            local entry = env.__log[index]
            if not entry then
                return nil
            end
            return {
                title = entry.title, questLogIndex = index, questID = entry.questID or 0,
                isHeader = entry.isHeader or false, isHidden = false, isTask = false, isBounty = false,
            }
        end,
        GetLogIndexForQuestID = function(questID)
            for index, entry in ipairs(env.__log) do
                if entry.questID == questID then
                    return index
                end
            end
        end,
        GetNumQuestWatches = function() return #env.__watched end,
        GetQuestIDForQuestWatchIndex = function(index) return env.__watched[index] end,
        GetQuestWatchType = function(questID)
            if watchIndex(questID) then
                return 0
            end
        end,
        AddQuestWatch = function(questID)
            if watchIndex(questID) or #env.__watched >= env.__maxWatches then
                return false
            end
            table.insert(env.__watched, questID)
            return true
        end,
        RemoveQuestWatch = function(questID)
            local index = watchIndex(questID)
            if not index then
                return false
            end
            table.remove(env.__watched, index)
            return true
        end,
    }
    -- A player in the new player experience may not untrack quests.
    env.__npeRestricted = false
    env.QuestUtil = {
        CanRemoveQuestWatch = function() return not env.__npeRestricted end,
    }

    -- Where a quest's objectives (or, once done, its turn-in) are: a map ID,
    -- or 0 when the client does not say.
    env.__questMaps = {}
    function env.GetQuestUiMapID(questID) return env.__questMaps[questID] or 0 end

    -- Where the player is: the zone's name and the most detailed map.
    env.__zone = "Hillsbrad Foothills"
    env.__playerMap = 25
    function env.GetRealZoneText() return env.__zone end
    function env.GetZoneText() return env.__zone end
    env.Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
    local types = env.Enum.UIMapType
    env.__maps = {
        [12] = { name = "Kalimdor", mapType = types.Continent, parentMapID = 947 },
        [13] = { name = "Eastern Kingdoms", mapType = types.Continent, parentMapID = 947 },
        [14] = { name = "Arathi Highlands", mapType = types.Zone, parentMapID = 13 },
        [22] = { name = "Alterac Mountains", mapType = types.Zone, parentMapID = 13 },
        [25] = { name = "Hillsbrad Foothills", mapType = types.Zone, parentMapID = 13 },
        [27] = { name = "Dun Morogh", mapType = types.Zone, parentMapID = 13 },
        [226] = { name = "Gnomeregan", mapType = types.Dungeon, parentMapID = 27 },
        -- A cave inside a zone: a map of its own, under the zone's.
        [1500] = { name = "Alterac Mountains Cave", mapType = types.Micro, parentMapID = 22 },
    }
    env.C_Map = {
        GetBestMapForUnit = function(unit)
            if unit == "player" then
                return env.__playerMap
            end
        end,
        GetMapInfo = function(mapID)
            local map = env.__maps[mapID]
            if not map then
                return nil
            end
            return { mapID = mapID, name = map.name, mapType = map.mapType, parentMapID = map.parentMapID }
        end,
    }

    -- The game's own automatic quest tracking, on by default.
    env.__cvars.autoQuestWatch = "1"

    if options.questLog ~= false then
        stub.buildQuestLog(env)
    end
end

--- options.client = "classic": Classic Era, without Forever's quest API.
-- options.questLog = false: the quest log is not built yet at login.
function stub.newEnv(options)
    options = options or {}
    local env = setmetatable({}, { __index = _G })

    env.__frames = {}
    env.__timers = {}
    env.__tickers = {}

    env.UIParent = makeWidget("Frame")
    env.WorldFrame = makeWidget("Frame")
    env.TimeManagerClockButton = makeWidget("Button")
    -- The gryphons, nested exactly as the live client reports them:
    -- MainActionBar.EndCaps.LeftEndCap
    env.MainActionBar = makeWidget("Frame")
    env.MainActionBar.EndCaps = makeWidget("Frame")
    env.MainActionBar.EndCaps.LeftEndCap = makeWidget("Frame")
    env.MainActionBar.EndCaps.RightEndCap = makeWidget("Frame")
    -- The player's portrait, where the game's own layout put it.
    env.PlayerFrame = makeWidget("Frame", env.UIParent)
    env.PlayerFrame:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", -19, -4)
    -- The main chat box, and the calls the game makes when the player has
    -- moved or resized it and when it puts the account's saved place back.
    env.ChatFrame1 = makeWidget("ScrollingMessageFrame", env.UIParent)
    env.ChatFrame1:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 32, 95)
    function env.FCF_SavePositionAndDimensions() end
    function env.FCF_RestorePositionAndDimensions() end
    -- The screen the game is drawn on, in pixels.
    env.__screen = { 3840, 2160 }
    function env.GetPhysicalScreenSize()
        return env.__screen[1], env.__screen[2]
    end
    -- Blizzard's registry of named callbacks, through which Edit Mode says it
    -- was entered, saved and left. A callback gets its owner first, a number
    -- the registry makes up when none was given.
    env.EventRegistry = { callbacks = {}, owners = 0 }
    function env.EventRegistry:RegisterCallback(event, fn, owner)
        if owner == nil then
            self.owners = self.owners + 1
            owner = self.owners
        end
        self.callbacks[event] = self.callbacks[event] or {}
        table.insert(self.callbacks[event], { fn = fn, owner = owner })
        return owner
    end
    function env.EventRegistry:TriggerEvent(event, ...)
        for _, callback in ipairs(self.callbacks[event] or {}) do
            callback.fn(callback.owner, ...)
        end
    end
    -- The font object every unit frame's health and mana text inherits from.
    env.TextStatusBarText = makeWidget("FontString")
    -- Both start closed, as they do in game, so Show() is a real transition
    -- and fires OnShow.
    env.SettingsPanel = makeWidget("Frame")
    env.SettingsPanel.shown = false
    env.GameMenuFrame = makeWidget("Frame")
    env.GameMenuFrame.shown = false
    env.SlashCmdList = {}

    env.MenuResponse = { Open = 1, Close = 2, CloseAll = 3, Refresh = 4 }

    function env.HideUIPanel(frame)
        if frame and frame.Hide then
            frame:Hide()
        end
    end

    -- In the client the addon environment *is* the global table, so code that
    -- reaches a frame by name through _G finds the same frames as code that
    -- names them directly.
    env._G = env

    env.__overrideBindings = {}
    env.__chatOpenedWith = nil
    env.__inCombat = false
    env.modifiers = {}

    function env.InCombatLockdown()
        return env.__inCombat
    end

    function env.SetOverrideBindingClick(owner, priority, key, buttonName)
        env.__overrideBindings[key] = buttonName
    end

    function env.ClearOverrideBindings()
        env.__overrideBindings = {}
    end

    function env.SetOverrideBinding(owner, priority, key, command)
        env.__overrideBindings[key] = command
    end

    -- The chat box, as far as the chat keys touch it. Blizzard keeps the
    -- channel in attributes (chatType, tellTarget, channelTarget), and its
    -- OPENCHAT binding opens the box from its own secure code.
    local editBox = makeWidget("EditBox", env.ChatFrame1)
    editBox.attributes = {}
    function editBox:SetAttribute(name, value)
        self.attributes[name] = value
    end
    function editBox:GetAttribute(name)
        return self.attributes[name]
    end
    function editBox:SetChatType(chatType)
        self:SetAttribute("chatType", chatType)
    end
    function editBox:GetChatType()
        return self:GetAttribute("chatType")
    end
    function editBox:SetTellTarget(target)
        self:SetAttribute("tellTarget", target)
    end
    function editBox:SetChannelTarget(target)
        self:SetAttribute("channelTarget", target)
    end
    function editBox:UpdateHeader()
        self.header = self:GetChatType()
    end
    editBox:SetAttribute("stickyType", "SAY")
    editBox:SetChatType("SAY")
    env.ChatFrame1EditBox = editBox

    -- Every call, so a test can tell the game's binding opening the box from
    -- the addon opening it, which is what taints it.
    env.__openChatCalls = {}
    env.ChatFrameUtil = {}
    function env.ChatFrameUtil.OpenChat(text)
        table.insert(env.__openChatCalls, text == nil and "<nil>" or text)
        env.__activeChatBox = editBox
        editBox:SetChatType(editBox:GetAttribute("stickyType"))
        editBox:UpdateHeader()
        return editBox
    end
    function env.ChatFrameUtil.GetActiveWindow()
        return env.__activeChatBox
    end

    function env.ChatFrame_OpenChat(text)
        env.__chatOpenedWith = text
        return env.ChatFrameUtil.OpenChat(text)
    end

    -- Once the game has hashed the slash commands it moves each chat type
    -- into a proxy behind __index, so most are not in ChatTypeInfo itself.
    env.ChatTypeInfo = setmetatable({ OFFICER = {} }, {
        __index = {
            SAY = {}, PARTY = {}, RAID = {}, GUILD = {}, YELL = {}, EMOTE = {},
            WHISPER = {}, CHANNEL = {}, REPLY = {},
            PING = { ignoreChatTypeProcessing = true },
        },
    })
    env.SLASH_SAY1, env.SLASH_SAY2 = "/s", "/say"
    env.SLASH_PARTY1, env.SLASH_PARTY2 = "/p", "/party"
    env.SLASH_RAID1, env.SLASH_RAID2 = "/ra", "/raid"
    env.SLASH_GUILD1 = "/g"
    env.SLASH_OFFICER1 = "/o"
    env.SLASH_YELL1 = "/y"
    env.SLASH_EMOTE1 = "/e"
    env.SLASH_WHISPER1, env.SLASH_WHISPER2 = "/w", "/whisper"
    env.SLASH_REPLY1 = "/r"
    env.SLASH_PING1 = "/ping"

    -- Channels joined, by number.
    env.__channels = {}
    function env.GetChannelName(id)
        if env.__channels[id] then
            return id, env.__channels[id]
        end
        return 0
    end

    -- Keys held, by name. While a binding runs, Forever hides the modifiers
    -- it used from everything but IsKeyDown(key, true); those go in
    -- __heldByBinding as well.
    env.__keysDown = {}
    env.__heldByBinding = {}
    function env.IsKeyDown(key, excludeBindingState)
        if not excludeBindingState and env.__heldByBinding[key] then
            return false
        end
        return env.__keysDown[key] == true
    end

    function env.IsControlKeyDown()
        return env.modifiers.ctrl and true or false
    end

    function env.IsShiftKeyDown()
        return env.modifiers.shift and true or false
    end

    function env.IsAltKeyDown()
        return env.modifiers.alt and true or false
    end

    env.__cvars = {}

    function env.SetCVar(name, value)
        env.__cvars[name] = tostring(value)
    end

    function env.GetCVar(name)
        return env.__cvars[name]
    end

    function env.CreateFrame(kind, name, parent)
        local frame = makeWidget(kind or "Frame", parent)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then
            env[name] = frame
        end
        return frame
    end

    env.cursorX, env.cursorY = 0, 0
    function env.GetCursorPosition()
        return env.cursorX, env.cursorY
    end

    env.money = 0
    function env.GetMoney()
        return env.money
    end

    env.xp, env.xpMax, env.xpDisabled = 0, 0, false

    function env.UnitXP()
        return env.xp
    end

    function env.UnitXPMax()
        return env.xpMax
    end

    function env.IsXPUserDisabled()
        return env.xpDisabled
    end

    function env.UnitLevel()
        return 60
    end

    function env.BreakUpLargeNumbers(value)
        local digits = tostring(math.floor(value))
        local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
        return (grouped:gsub("^,", ""))
    end

    -- Records what a context menu was built from, so tests can read the entries
    -- back and invoke them the way a click would.
    local function makeMenuRoot()
        local root = { entries = {} }

        local function add(entry)
            table.insert(root.entries, entry)
            return entry
        end

        function root:CreateTitle(text)
            return add({ kind = "title", text = text })
        end

        function root:CreateButton(text, callback)
            return add({ kind = "button", text = text, callback = callback })
        end

        function root:CreateCheckbox(text, isSelected, setSelected)
            return add({
                kind = "checkbox",
                text = text,
                isSelected = isSelected,
                setSelected = setSelected,
            })
        end

        function root:CreateDivider()
            return add({ kind = "divider" })
        end

        --- Find an entry by its label.
        function root:Find(text)
            for _, entry in ipairs(self.entries) do
                if entry.text == text then
                    return entry
                end
            end
        end

        return root
    end

    env.MenuUtil = {
        CreateContextMenu = function(owner, generator)
            local root = makeMenuRoot()
            generator(owner, root)
            env.__menu = root
            env.__menuOwner = owner
            return root
        end,
    }

    env.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            return {
                name = name,
                frame = frame,
                GetID = function()
                    return "category-id"
                end,
            }
        end,
        RegisterAddOnCategory = function(category)
            env.__settingsCategory = category
        end,
        OpenToCategory = function(id)
            env.__openedCategory = id
        end,
    }

    -- Free slots per bag, and the bag's type: 0 is general purpose, anything
    -- else only takes particular items.
    env.NUM_BAG_SLOTS = 4
    env.bagSlots = {
        [0] = { free = 4, total = 16, kind = 0 },
        [1] = { free = 6, total = 16, kind = 0 },
        [2] = { free = 2, total = 8, kind = 0 },
        [3] = { free = 0, total = 0, kind = 0 },
        [4] = { free = 0, total = 0, kind = 0 },
    }

    env.C_Container = {
        GetContainerNumFreeSlots = function(bag)
            local entry = env.bagSlots[bag]
            if not entry then
                return nil
            end
            return entry.free, entry.kind
        end,
        GetContainerNumSlots = function(bag)
            local entry = env.bagSlots[bag]
            return entry and entry.total or 0
        end,
    }

    function env.OpenAllBags()
        env.__bagsOpened = true
    end

    env.C_AddOns = {
        GetAddOnMetadata = function(_, field)
            return field == "Version" and "9.9.9" or nil
        end,
    }

    function env.CreateColor(r, g, b, a)
        return { r = r, g = g, b = b, a = a }
    end

    env.date = os.date

    env.C_Timer = {
        After = function(_, fn)
            table.insert(env.__timers, fn)
        end,
        NewTicker = function(interval, fn)
            local ticker = { interval = interval, fn = fn, Cancel = function() end }
            table.insert(env.__tickers, ticker)
            return ticker
        end,
    }

    -- hooksecurefunc(table, name, fn) on a table, or (name, fn) on a global.
    function env.hooksecurefunc(target, name, post)
        if type(target) == "string" then
            target, name, post = env, target, name
        end
        local original = target[name]
        assert(type(original) == "function", "hooksecurefunc: no function " .. tostring(name))
        target[name] = function(...)
            local result = original(...)
            post(...)
            return result
        end
    end

    -- What was printed, line by line.
    env.__printed = {}
    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do
            pieces[index] = tostring((select(index, ...)))
        end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    -- Tooltips: the owner and every line, as { text, r, g, b, wrap }.
    env.GameTooltip = makeWidget("GameTooltip", env.UIParent)
    env.GameTooltip.shown = false
    env.GameTooltip.lines = {}
    function env.GameTooltip:SetOwner(owner, anchor)
        self.owner, self.anchor = owner, anchor
        self.lines = {}
    end
    function env.GameTooltip:GetOwner() return self.owner end
    function env.GameTooltip:SetText(text, r, g, b)
        self.lines = { { text = text, r = r, g = g, b = b } }
    end
    function env.GameTooltip:AddLine(text, r, g, b, wrap)
        table.insert(self.lines, { text = text, r = r, g = g, b = b, wrap = wrap })
    end

    -- Sounds played: each kit handed to PlaySound.
    env.__sounds = {}
    env.SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 }
    function env.PlaySound(kit) table.insert(env.__sounds, kit) end

    if options.client ~= "classic" then
        addQuests(env, options)
    end

    -- Test helper: simulate the render pass that makes text measurable.
    function env.__render()
        local seen = {}

        local function mark(widget)
            if seen[widget] then
                return
            end
            seen[widget] = true
            widget.metricsReady = true
            for _, child in ipairs(widget.children) do
                mark(child)
            end
        end

        mark(env.UIParent)
        for _, frame in ipairs(env.__frames) do
            mark(frame)
        end
    end

    -- Test helpers.
    -- A timer queued during one frame does not fire until the next one, and the
    -- client draws in between, so anything queued can rely on text being
    -- measurable by the time it runs.
    function env.__runTimers()
        local pending = env.__timers
        env.__timers = {}
        if #pending == 0 then
            return
        end

        env.__render()
        for _, fn in ipairs(pending) do
            fn()
        end
    end

    function env.__tick()
        for _, ticker in ipairs(env.__tickers) do
            ticker.fn()
        end
        env.__runTimers()
    end

    return env
end

return stub
