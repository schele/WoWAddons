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
    function widget:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
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
    function widget:CreateFontString() return makeWidget("FontString", self) end
    function widget:SetWidth(value) self.width = value end
    function widget:SetJustifyH(value) self.justifyH = value end
    function widget:SetAllPoints() end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end
    function widget:EnableKeyboard(value) self.keyboard = value and true or false end
    function widget:SetPropagateKeyboardInput(value) self.propagate = value and true or false end
    function widget:AddLine(value) self.lines = self.lines or {}; table.insert(self.lines, value) end
    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end
    function widget:SetSize(w, h) self.width, self.height = w, h end
    function widget:SetAlpha(value) self.alpha = value end
    function widget:EnableMouse(value) self.mouseEnabled = value end
    function widget:RegisterForClicks(...) self.clicks = { ... } end
    function widget:GetName() return self.frameName end
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
    }

    return env
end

return stub
