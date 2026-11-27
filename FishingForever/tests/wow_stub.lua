-- A minimal stand-in for the WoW API, enough to load the addon outside the
-- game. Widgets record what was done to them so tests can assert on it.

local stub = {}

local function makeWidget(kind, parent, template)
    local widget = {
        kind = kind,
        parent = parent,
        template = template,
        scripts = {},
        registeredEvents = {},
        attributes = {},
        shown = true,
    }

    function widget:SetScript(name, fn) self.scripts[name] = fn end
    -- For a minimap button.
    widget.points = {}
    function widget:SetPoint(...) table.insert(self.points, { ... }) end
    function widget:ClearAllPoints() self.points = {} end
    function widget:GetPoint(index)
        local point = self.points[index or 1]
        if point then return table.unpack(point) end
    end
    function widget:GetWidth() return self.width or 0 end
    function widget:GetParent() return self.parent end
    function widget:SetFrameStrata(value) self.strata = value end
    function widget:SetFrameLevel(value) self.frameLevel = value end
    function widget:GetFrameLevel() return self.frameLevel or 1 end
    function widget:RegisterForDrag(...) self.drag = { ... } end
    function widget:SetHighlightTexture(value) self.highlightTexture = value end
    function widget:SetNormalTexture(value) self.normalTexture = value end
    function widget:SetPushedTexture(value) self.pushedTexture = value end
    function widget:SetDisabledTexture(value) self.disabledTexture = value end
    function widget:SetItemByID(id) self.itemID = id end
    function widget:SetVertexColor(...) self.vertexColor = { ... } end
    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
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
    function widget:IsShown() return self.shown end
    function widget:GetCenter() return self.centerX or 0, self.centerY or 0 end
    function widget:GetEffectiveScale() return 1 end
    function widget:CreateTexture() return makeWidget("Texture", self) end
    -- A tooltip starts over when it is given an owner.
    function widget:SetOwner(owner, anchor)
        self.owner, self.anchor = owner, anchor
        self.text, self.lines = nil, nil
    end
    function widget:GetOwner() return self.owner end
    function widget:SetText(value) self.text = value end
    -- For the settings page.
    function widget:GetText() return self.text end
    function widget:GetScript(name) return self.scripts[name] end
    function widget:HookScript(name, fn)
        local existing = self.scripts[name]
        self.scripts[name] = function(...)
            if existing then existing(...) end
            fn(...)
        end
    end
    -- Remembered on the parent, so a test can find a label by its text.
    function widget:CreateFontString()
        local fontString = makeWidget("FontString", self)
        self.fontStrings = self.fontStrings or {}
        table.insert(self.fontStrings, fontString)
        return fontString
    end
    -- A change of size runs the widget's OnSizeChanged, as the client does.
    local function resized(self)
        local handler = self.scripts.OnSizeChanged
        if handler then handler(self, self.width, self.height) end
    end
    function widget:SetWidth(value)
        self.width = value
        resized(self)
    end
    function widget:SetHeight(value) self.height = value end
    function widget:GetHeight() return self.height or 0 end
    function widget:GetBottom() return self.bottom end
    function widget:GetTop() return self.top end
    function widget:SetParent(parent) self.parent = parent end
    function widget:SetWordWrap(value) self.wordWrap = value end
    function widget:EnableMouseWheel(value) self.mouseWheel = value end
    function widget:SetEnabled(value) self.enabled = value and true or false end
    function widget:IsEnabled() return self.enabled ~= false end
    function widget:SetJustifyH(value) self.justifyH = value end
    function widget:SetAllPoints() end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end
    function widget:EnableKeyboard(value) self.keyboard = value and true or false end
    function widget:SetPropagateKeyboardInput(value) self.propagate = value and true or false end
    function widget:AddLine(value) self.lines = self.lines or {}; table.insert(self.lines, value) end
    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end
    function widget:SetSize(w, h)
        self.width, self.height = w, h
        resized(self)
    end
    function widget:SetAlpha(value) self.alpha = value end
    function widget:EnableMouse(value) self.mouseEnabled = value end
    function widget:RegisterForClicks(...) self.clicks = { ... } end
    function widget:GetName() return self.frameName end
    -- For a status bar.
    function widget:SetMinMaxValues(low, high) self.minValue, self.maxValue = low, high end
    function widget:SetValue(value) self.value = value end
    function widget:GetValue() return self.value end
    function widget:SetStatusBarTexture(value) self.statusBarTexture = value end
    function widget:SetStatusBarColor(r, g, b) self.barColor = { r, g, b } end
    function widget:SetColorTexture(...) self.color = { ... } end
    function widget:SetTextColor(...) self.textColor = { ... } end
    function widget:ClearLines() self.lines = {} end
    -- For a frame dragged about: StartMoving holds it to the cursor, and the
    -- test moves it by setting a new point before StopMovingOrSizing.
    function widget:SetMovable(value) self.movable = value end
    function widget:SetClampedToScreen(value) self.clamped = value end
    function widget:StartMoving() self.moving = true end
    function widget:StopMovingOrSizing() self.moving = false end
    function widget:SetAttribute(name, value) self.attributes[name] = value end
    function widget:GetAttribute(name) return self.attributes[name] end

    -- Test helper: drive this widget's OnEvent handler.
    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then handler(self, event, ...) end
    end

    return widget
end

function stub.newEnv()
    local env = setmetatable({}, { __index = _G })

    env.__frames = {}
    env.__printed = {}
    env._G = env

    env.UIParent = makeWidget("Frame")
    env.GameTooltip = makeWidget("GameTooltip", env.UIParent)
    env.SlashCmdList = {}

    -- The game's options window and the game menu, both closed to begin with.
    env.SettingsPanel = makeWidget("Frame", env.UIParent)
    env.SettingsPanel.shown = false
    env.GameMenuFrame = makeWidget("Frame", env.UIParent)
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
    env.C_AddOns = {
        GetAddOnMetadata = function(_, field)
            return field == "Version" and "9.9.9" or nil
        end,
    }

    -- Modifier keys held down, by name: shift, ctrl, alt.
    env.__modifiers = {}
    function env.IsShiftKeyDown() return env.__modifiers.shift end
    function env.IsControlKeyDown() return env.__modifiers.ctrl end
    function env.IsAltKeyDown() return env.__modifiers.alt end

    -- The client runs a timer after the current chain of calls, not inside
    -- it: queued here, and run by __runTimers.
    env.__timers = {}
    env.C_Timer = {
        After = function(_, fn) table.insert(env.__timers, fn) end,
    }
    function env.__runTimers()
        local pending = env.__timers
        env.__timers = {}
        for _, fn in ipairs(pending) do fn() end
    end

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do
            pieces[index] = tostring((select(index, ...)))
        end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    function env.CreateFrame(kind, name, parent, template)
        local frame = makeWidget(kind or "Frame", parent, template)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if parent then
            parent.children = parent.children or {}
            table.insert(parent.children, frame)
        end
        if name then env[name] = frame end
        return frame
    end

    -- Combat: bindings cannot change inside it, and the stub refuses the
    -- same way the client does, so a test catches a write that would fail.
    env.__inCombat = false
    function env.InCombatLockdown() return env.__inCombat end

    local function refuseInCombat(what)
        if env.__inCombat then
            error(what .. " is blocked in combat", 3)
        end
    end

    -- Override bindings, keyed by the key: { command = ..., button = ... }.
    env.__bindings = {}

    function env.SetOverrideBinding(owner, priority, key, command)
        refuseInCombat("SetOverrideBinding")
        env.__bindings[key] = { command = command }
    end

    function env.SetOverrideBindingClick(owner, priority, key, buttonName, mouseButton)
        refuseInCombat("SetOverrideBindingClick")
        env.__bindings[key] = { button = buttonName, mouseButton = mouseButton }
    end

    function env.ClearOverrideBindings()
        refuseInCombat("ClearOverrideBindings")
        env.__bindings = {}
    end

    -- CVars. Only the ones a client really has read back as a value; any
    -- other name reads nil, which is how the client answers an unknown one.
    env.__cvars = {
        SoftTargetInteract = "0",
        SoftTargetInteractRange = "10",
        autoLootDefault = "0",
    }
    function env.GetCVar(name) return env.__cvars[name] end
    function env.SetCVar(name, value) env.__cvars[name] = tostring(value) end

    -- Spells: Fishing, by the ID the addon asks for, and a second rank.
    env.__spellNames = { [7620] = "Fishing", [7731] = "Fishing", [774] = "Rejuvenation" }
    env.C_Spell = {
        GetSpellName = function(id) return env.__spellNames[id] end,
    }

    -- The Fishing skill, as Forever's C_SkillInfo reads it by its ID, 356.
    -- Nil when the character has not learned it.
    -- `modifier` is what a lure or gear adds.
    env.__fishing = { rank = 231, maxRank = 300 }
    env.C_SkillInfo = {
        GetSkillLineInfoByID = function(id)
            local fishing = env.__fishing
            if id ~= 356 or not fishing then return nil end
            return {
                skillID = 356, name = "Fishing", isHeader = false, isCollapsed = false,
                rank = fishing.rank, maxRank = fishing.maxRank, tempPoints = 0,
                modifier = fishing.modifier or 0,
            }
        end,
    }

    -- Whether the loot window open is a catch.
    env.__fishingLoot = false
    function env.IsFishingLoot() return env.__fishingLoot end
    env.ERR_FISH_ESCAPED = "Your fish got away!"
    env.SPELL_FAILED_LOW_CASTLEVEL = "Skill not high enough"

    -- The client's clock, in seconds; a test moves it on by hand.
    env.__now = 1000
    function env.GetTime() return env.__now end

    -- The zone the player stands in: its level range as the world map shows
    -- it (nil for a map without one), the subzone, and where in it.
    env.__map = { id = 1424, name = "Hillsbrad Foothills", levels = { 20, 30 } }
    env.__subzone = "Southshore"
    env.__position = { 0.5, 0.6 }
    env.C_Map = {
        GetBestMapForUnit = function(unit)
            return unit == "player" and env.__map and env.__map.id or nil
        end,
        GetMapInfo = function(id)
            if env.__map and env.__map.id == id then
                return { mapID = id, name = env.__map.name }
            end
        end,
        GetMapLevels = function(id)
            local map = env.__map
            if map and map.id == id and map.levels then
                return map.levels[1], map.levels[2], 0, 0
            end
        end,
        GetPlayerMapPosition = function(id, unit)
            if unit == "player" and env.__position then
                local x, y = env.__position[1], env.__position[2]
                return { GetXY = function() return x, y end }
            end
        end,
    }
    function env.GetSubZoneText() return env.__subzone end

    -- The character: Forever hands a surname after the name.
    env.__level = 34
    function env.UnitName(unit)
        if unit == "player" then return "Aldira", "Moonclaw" end
    end
    function env.UnitLevel(unit)
        if unit == "player" then return env.__level end
    end

    -- The clock time() reads.
    env.__clock = 1764000000
    function env.time() return env.__clock end

    -- The loot window: { id, name, count } a slot, as the client lists it.
    env.__loot = {}
    function env.GetNumLootItems() return #env.__loot end
    function env.GetLootSlotInfo(slot)
        local item = env.__loot[slot]
        if item then return 133888, item.name, item.count or 1, nil, 1 end
    end
    function env.GetLootSlotLink(slot)
        local item = env.__loot[slot]
        if item then
            return string.format("|cffffffff|Hitem:%d::::::::34:::::|h[%s]|h|r", item.id, item.name)
        end
    end

    env.UISpecialFrames = {}

    -- Equipment: the main hand holds whatever item ID is put here.
    env.__mainHand = nil
    env.__items = {
        [6256] = { classID = 2, subclassID = 20 }, -- Fishing Pole
        [1161] = { classID = 2, subclassID = 10 }, -- a staff
    }
    function env.GetInventoryItemID(_, slot)
        if slot == 16 then return env.__mainHand end
    end
    env.C_Item = {
        GetItemInfoInstant = function(id)
            local item = env.__items[id]
            if not item then return nil end
            return id, "Weapon", "", "INVTYPE_2HWEAPON", 0, item.classID, item.subclassID
        end,
        GetItemIconByID = function(id) return 133888 end,
        GetItemQualityByID = function(id) return 1 end,
    }
    env.ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 } }
    -- The quest log's colours for a level against the player's.
    function env.GetQuestDifficultyColor(level)
        return { r = 1, g = level > env.__level and 0.5 or 1, b = 0 }
    end
    env.QuestDifficultyColors = { difficult = { r = 1, g = 1, b = 0 } }

    return env
end

return stub
