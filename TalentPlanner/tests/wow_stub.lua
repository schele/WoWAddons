-- A minimal stand-in for the WoW API, enough to load TalentPlanner outside
-- the game: frames, edit boxes, menus, the options window, timers, combat,
-- a made-up three-tree druid, the talent window and LearnTalent. It records
-- what was done so tests can assert on it.

local stub = {}

local function makeWidget(env, kind, parent, template)
    local widget = {
        kind = kind,
        parent = parent,
        template = template,
        scripts = {},
        registeredEvents = {},
        points = {},
        children = {},
        shown = true,
        enabled = true,
        checked = false,
    }
    if parent and parent.children then
        table.insert(parent.children, widget)
    end

    function widget:SetScript(name, fn) self.scripts[name] = fn end
    function widget:GetScript(name) return self.scripts[name] end
    function widget:HookScript(name, fn)
        local existing = self.scripts[name]
        self.scripts[name] = function(...)
            if existing then existing(...) end
            fn(...)
        end
    end
    -- The client raises on an event name it does not have.
    function widget:RegisterEvent(event)
        if env.__unknownEvents[event] then
            error("Attempt to register unknown event \"" .. event .. "\"", 2)
        end
        self.registeredEvents[event] = true
    end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end
    function widget:SetPoint(...) table.insert(self.points, { ... }) end
    function widget:ClearAllPoints() self.points = {} end
    function widget:GetPoint(index)
        local point = self.points[index or 1]
        if point then return table.unpack(point) end
    end
    function widget:SetAllPoints() end
    function widget:SetSize(w, h) self.width, self.height = w, h end
    function widget:SetWidth(value) self.width = value end
    function widget:SetHeight(value) self.height = value end
    function widget:GetWidth() return self.width or 0 end
    function widget:GetHeight() return self.height or 0 end
    function widget:GetParent() return self.parent end
    function widget:GetName() return self.frameName end
    function widget:GetID() return self.id or 0 end
    function widget:SetID(value) self.id = value end
    function widget:GetCenter() return self.centerX or 0, self.centerY or 0 end
    function widget:GetEffectiveScale() return 1 end
    function widget:SetFrameStrata(value) self.strata = value end
    function widget:SetFrameLevel(value) self.frameLevel = value end
    function widget:GetFrameLevel() return self.frameLevel or 1 end
    function widget:SetClampedToScreen() end
    function widget:SetMovable() end
    function widget:EnableMouse(value) self.mouseEnabled = value end
    function widget:RegisterForDrag(...) self.drag = { ... } end
    function widget:RegisterForClicks(...) self.clicks = { ... } end
    function widget:StartMoving() self.moving = true end
    function widget:StopMovingOrSizing() self.moving = false end
    function widget:SetBackdrop(value) self.backdrop = value end
    function widget:SetBackdropColor() end
    function widget:SetBackdropBorderColor() end
    function widget:SetHighlightTexture(value) self.highlightTexture = value end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text end
    function widget:SetFormattedText(format, ...) self.text = string.format(format, ...) end
    function widget:SetTextColor(...) self.textColor = { ... } end
    function widget:SetVertexColor(...) self.vertexColor = { ... } end
    function widget:SetDesaturated(value) self.desaturated = value and true or false end
    function widget:SetBlendMode(value) self.blendMode = value end
    function widget:SetJustifyH(value) self.justifyH = value end
    function widget:SetJustifyV(value) self.justifyV = value end
    function widget:SetWordWrap(value) self.wordWrap = value end
    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
    function widget:SetTexCoord(...) self.texCoord = { ... } end
    function widget:SetColorTexture(...) self.color = { ... } end
    function widget:SetAlpha(value) self.alpha = value end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end
    function widget:SetEnabled(value) self.enabled = value and true or false end
    function widget:Enable() self.enabled = true end
    function widget:Disable() self.enabled = false end
    function widget:IsEnabled() return self.enabled end
    function widget:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor; self.lines = {} end
    function widget:GetOwner() return self.owner end
    function widget:AddLine(value) self.lines = self.lines or {}; table.insert(self.lines, value) end
    function widget:SetTalent(tab, index)
        if env.__noSetTalent then error("no SetTalent") end
        self.talent = { tab, index }
    end
    -- Edit boxes.
    function widget:SetAutoFocus(value) self.autoFocus = value end
    function widget:SetMaxLetters(value) self.maxLetters = value end
    function widget:SetMultiLine(value) self.multiLine = value end
    function widget:SetFontObject(value) self.fontObject = value end
    function widget:SetTextInsets() end
    function widget:HighlightText() self.highlighted = true end
    function widget:SetFocus() self.focused = true end
    function widget:ClearFocus() self.focused = false end
    function widget:CreateTexture()
        local texture = makeWidget(env, "Texture", self)
        self.textures = self.textures or {}
        table.insert(self.textures, texture)
        return texture
    end
    -- Remembered on the parent, so a test can find a label by its text.
    function widget:CreateFontString()
        local fontString = makeWidget(env, "FontString", self)
        self.fontStrings = self.fontStrings or {}
        table.insert(self.fontStrings, fontString)
        return fontString
    end
    -- Showing and hiding fire their scripts, and only on a real transition.
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
    function widget:IsShown() return self.shown end
    -- Visible only when it and every parent is shown, as in the client.
    function widget:IsVisible()
        local node = self
        while node do
            if not node.shown then return false end
            node = node.parent
        end
        return true
    end

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

stub.makeWidget = makeWidget

-- The druid's trees: name, tier, column, maxRank, and the index of the
-- talent it needs, in the same tree.
stub.TREES = {
    {
        name = "Balance",
        talents = {
            { "Starlight Wrath", 1, 2, 5 },
            { "Nature's Grasp", 1, 3, 1 },
            { "Improved Nature's Grasp", 1, 4, 4, 2 },
            { "Moonglow", 2, 1, 5 },
            { "Natural Weapons", 2, 2, 5 },
            { "Moonfury", 3, 2, 5 },
            { "Omen of Clarity", 3, 3, 5 },
            { "Moonkin Form", 4, 2, 1, 6 },
        },
    },
    {
        name = "Feral Combat",
        talents = {
            { "Ferocity", 1, 2, 5 },
            { "Feral Instinct", 1, 3, 5 },
            { "Thick Hide", 2, 2, 5 },
            { "Feral Swiftness", 2, 3, 5 },
            { "Sharpened Claws", 3, 2, 5 },
            { "Feral Charge", 3, 3, 1 },
            { "Savage Fury", 3, 1, 5 },
            { "Blood Frenzy", 4, 1, 5 },
            { "Primal Fury", 4, 2, 5, 5 },
            { "Heart of the Wild", 5, 2, 5, 9 },
        },
    },
    {
        name = "Restoration",
        talents = {
            { "Improved Mark", 1, 2, 5 },
            { "Furor", 1, 3, 5 },
            { "Nature's Focus", 2, 2, 5 },
            { "Swiftmend", 2, 3, 1 },
        },
    },
}

--- A fresh client. `saved` is TalentPlannerDB as the client would load it.
function stub.newEnv(saved)
    local env = setmetatable({}, { __index = _G })

    env._G = env
    env.__frames = {}
    env.__printed = {}
    env.__unknownEvents = {}
    env.TalentPlannerDB = saved
    env.SlashCmdList = {}
    env.UISpecialFrames = {}
    env.UIParent = makeWidget(env, "Frame")
    env.Minimap = makeWidget(env, "Frame", env.UIParent)
    env.Minimap.width = 140
    env.GameTooltip = makeWidget(env, "GameTooltip", env.UIParent)
    env.GameTooltip.shown = false

    -- The game's options window and the game menu, both closed to begin with.
    env.SettingsPanel = makeWidget(env, "Frame", env.UIParent)
    env.SettingsPanel.shown = false
    env.GameMenuFrame = makeWidget(env, "Frame", env.UIParent)
    env.GameMenuFrame.shown = false
    function env.HideUIPanel(frame)
        if frame and frame.Hide then frame:Hide() end
    end
    env.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            return { name = name, frame = frame, GetID = function() return "category-id" end }
        end,
        RegisterAddOnCategory = function(category) env.__settingsCategory = category end,
        OpenToCategory = function(id) env.__openedCategory = id end,
    }

    -- Addons the client has loaded, by name.
    env.__loaded = {}
    env.C_AddOns = {
        GetAddOnMetadata = function(_, field)
            return field == "Version" and "9.9.9" or nil
        end,
        IsAddOnLoaded = function(name) return env.__loaded[name] == true end,
    }

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do
            pieces[index] = tostring((select(index, ...)))
        end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    -- Templates this client does not have: asking for one raises, as the
    -- client's CreateFrame does.
    env.__missingTemplates = {}
    function env.CreateFrame(kind, name, parent, template)
        if template and env.__missingTemplates[template] then
            error(string.format("Couldn't find inherited node '%s'", template), 2)
        end
        local frame = makeWidget(env, kind or "Frame", parent, template)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        -- The options window's frame, as far as a test needs it: the border
        -- with the title in its bar, the background, and the red X.
        if template == "SettingsFrameTemplate" then
            frame.Bg = makeWidget(env, "Frame", frame)
            frame.NineSlice = makeWidget(env, "Frame", frame)
            frame.NineSlice.Text = frame.NineSlice:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            frame.ClosePanelButton = makeWidget(env, "Button", frame, "UIPanelCloseButtonDefaultAnchors")
        end
        return frame
    end

    function env.hooksecurefunc(name, fn)
        local original = env[name]
        env[name] = function(...)
            local results = { original(...) }
            fn(...)
            return table.unpack(results)
        end
    end

    -- Timers that run when a test says so.
    env.__now = 1000
    function env.GetTime() return env.__now end
    env.__timers = {}
    env.C_Timer = {
        After = function(_, fn) table.insert(env.__timers, fn) end,
    }
    function env.__runTimers()
        local pending = env.__timers
        env.__timers = {}
        for _, fn in ipairs(pending) do fn() end
    end
    function env.GetCursorPosition() return 0, 0 end

    env.__inCombat = false
    function env.InCombatLockdown() return env.__inCombat end

    -- The player: a level 30 druid.
    env.__player = { name = "Skyler", realm = "Aldira", level = 30, class = "Druid", classFile = "DRUID" }
    function env.UnitName(unit)
        if unit == "player" then return env.__player.name end
    end
    function env.GetRealmName() return env.__player.realm end
    function env.UnitLevel(unit)
        if unit == "player" then return env.__player.level end
    end
    function env.UnitClass(unit)
        if unit == "player" then return env.__player.class, env.__player.classFile end
    end

    -- Talents: the trees above, the player's rank in each, and the points
    -- left to spend. A tab's info gives the name first, as Classic does;
    -- __tabInfoIdFirst puts an ID before it, as newer clients do.
    env.__ranks = {}
    for tab, tree in ipairs(stub.TREES) do
        env.__ranks[tab] = {}
        for index in ipairs(tree.talents) do
            env.__ranks[tab][index] = 0
        end
    end
    env.__unspent = 0
    env.__tabInfoIdFirst = false

    local function spentIn(tab)
        local total = 0
        for _, rank in ipairs(env.__ranks[tab]) do total = total + rank end
        return total
    end

    function env.GetNumTalentTabs() return #stub.TREES end
    function env.GetTalentTabInfo(tab)
        local tree = stub.TREES[tab]
        if not tree then return nil end
        if env.__tabInfoIdFirst then
            return 100 + tab, tree.name, "description", "icon-tab" .. tab, spentIn(tab), "background"
        end
        return tree.name, "icon-tab" .. tab, spentIn(tab), "file"
    end
    function env.GetNumTalents(tab)
        local tree = stub.TREES[tab]
        return tree and #tree.talents or 0
    end
    function env.GetTalentInfo(tab, index)
        local talent = stub.TREES[tab] and stub.TREES[tab].talents[index]
        if not talent then return nil end
        return talent[1], "icon-" .. tab .. "-" .. index, talent[2], talent[3], env.__ranks[tab][index], talent[4], false, true
    end
    function env.GetTalentPrereqs(tab, index)
        local talent = stub.TREES[tab].talents[index]
        local needed = talent[5] and stub.TREES[tab].talents[talent[5]]
        if needed then
            return needed[2], needed[3], true
        end
    end
    function env.UnitCharacterPoints(unit)
        if unit == "player" then return env.__unspent, 0 end
    end

    -- LearnTalent spends a point, unless the client is told to refuse.
    env.__learned = {}
    env.__refuseLearn = false
    function env.LearnTalent(tab, index)
        table.insert(env.__learned, { tab, index })
        if env.__refuseLearn or env.__unspent < 1 then return end
        env.__ranks[tab][index] = env.__ranks[tab][index] + 1
        env.__unspent = env.__unspent - 1
    end

    --- The talent window, as Blizzard_TalentUI makes it: a frame with a
    -- selected tab and twenty buttons whose IDs are their talent index. With
    -- `player` true it is the later clients' PlayerTalentFrame.
    function env.__makeTalentUI(player)
        local name = player and "PlayerTalentFrame" or "TalentFrame"
        local frame = env.CreateFrame("Frame", name, env.UIParent)
        frame.selectedTab = 1
        for index = 1, 20 do
            local button = env.CreateFrame("Button", name .. "Talent" .. index, frame)
            button:SetID(index)
        end
        env[player and "PlayerTalentFrame_Update" or "TalentFrame_Update"] = function() end
        env.__loaded.Blizzard_TalentUI = true
        return frame
    end

    -- Menus: the modern MenuUtil, which builds its entries through the
    -- generator, recorded so a test can pick one.
    local function menuRoot()
        local root = { entries = {} }
        function root:CreateTitle(text) table.insert(self.entries, { text = text, title = true }) end
        function root:CreateDivider() table.insert(self.entries, { divider = true }) end
        function root:CreateButton(text, onClick)
            local entry = { text = text, onClick = onClick }
            table.insert(self.entries, entry)
            return entry
        end
        function root:CreateRadio(text, isSelected, setSelected, data)
            local entry = { text = text, onClick = function() setSelected(data) end, selected = isSelected(data) }
            table.insert(self.entries, entry)
            return entry
        end
        function root:Find(text)
            for _, entry in ipairs(self.entries) do
                if entry.text == text then return entry end
            end
        end
        return root
    end
    env.MenuUtil = {
        CreateContextMenu = function(owner, generator)
            local root = menuRoot()
            generator(owner, root)
            env.__menu = root
            return root
        end,
    }

    return env
end

--- The older menu: EasyMenu with a list of entries instead of MenuUtil.
function stub.useEasyMenu(env)
    env.MenuUtil = nil
    function env.EasyMenu(list, frame, anchor)
        env.__easyMenu = list
        env.__easyMenuFrame = frame
    end
end

--- No menu at all.
function stub.useNoMenu(env)
    env.MenuUtil = nil
    env.EasyMenu = nil
end

return stub
