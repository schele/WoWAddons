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
        points = {},
        children = {},
        shown = true,
        text = "",
    }

    -- A widget built from a template arrives mouse-enabled; one built bare
    -- does not, and looks entirely correct while taking no clicks at all.
    -- This repo has lost rounds to exactly that, so the stub models it
    -- rather than letting every widget take a click.
    if template then
        widget.mouseEnabled = true
    end

    function widget:SetScript(name, fn) self.scripts[name] = fn end
    function widget:GetScript(name) return self.scripts[name] end
    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end
    function widget:SetSize(w, h) self.width, self.height = w, h end
    function widget:SetWidth(value) self.width = value end
    function widget:SetAlpha(value) self.alpha = value end
    function widget:EnableMouse(value) self.mouseEnabled = value end
    function widget:RegisterForClicks(...) self.clicks = { ... } end
    function widget:GetName() return self.frameName end
    function widget:SetAttribute(name, value) self.attributes[name] = value end
    function widget:GetAttribute(name) return self.attributes[name] end

    function widget:SetPoint(...) table.insert(self.points, { ... }) end
    function widget:ClearAllPoints() self.points = {} end
    function widget:SetJustifyH(value) self.justifyH = value end

    function widget:HookScript(name, fn)
        local existing = self.scripts[name]
        self.scripts[name] = function(...)
            if existing then existing(...) end
            fn(...)
        end
    end

    function widget:Show()
        if self.shown then return end
        self.shown = true
        local handler = self.scripts.OnShow
        if handler then handler(self) end
    end

    function widget:Hide()
        if not self.shown then return end
        self.shown = false
        local handler = self.scripts.OnHide
        if handler then handler(self) end
    end

    function widget:IsShown() return self.shown end

    function widget:SetText(value) self.text = value or "" end
    function widget:GetText() return self.text end

    -- SetChecked deliberately fires no script, which is what the real client
    -- does: a checkbox set in code does not report itself clicked. A stub
    -- that fired OnClick here would make a refresh look like a player's
    -- click and hide a genuine recursion.
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end

    -- SetValue does fire, which is equally what the client does, and is why
    -- a slider's Refresh has to be safe against re-entry.
    function widget:SetValue(value)
        self.value = value
        local handler = self.scripts.OnValueChanged
        if handler then handler(self, value) end
    end

    function widget:GetValue() return self.value end
    function widget:SetMinMaxValues(low, high) self.minValue, self.maxValue = low, high end
    function widget:SetValueStep(value) self.valueStep = value end
    function widget:SetObeyStepOnDrag(value) self.obeyStep = value end

    -- Recorded, because a capture left running holds every key press away
    -- from the game and looks exactly like the client having frozen. A test
    -- has to be able to prove the keyboard was given back.
    function widget:EnableKeyboard(value) self.keyboardEnabled = value and true or false end
    function widget:SetPropagateKeyboardInput(value)
        self.propagateKeyboard = value and true or false
    end

    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end

    function widget:CreateTexture(_, layer)
        local texture = makeWidget("Texture", self)
        texture.drawLayer = layer
        table.insert(self.children, texture)
        return texture
    end

    function widget:CreateFontString(_, layer)
        local fontString = makeWidget("FontString", self)
        fontString.drawLayer = layer
        table.insert(self.children, fontString)
        return fontString
    end

    --- Test helper: a player's click, which is not the same as calling the
    -- handler directly -- a widget that takes no mouse never gets one.
    function widget:Click(button)
        assert(self.mouseEnabled ~= false,
            "clicked a widget that does not take the mouse")
        local handler = self.scripts.OnClick
        if handler then handler(self, button or "LeftButton") end
    end

    --- Test helper: a key pressed while this widget is listening. A widget
    -- that has not enabled the keyboard never receives one, the same way.
    function widget:PressKey(key)
        assert(self.keyboardEnabled,
            "pressed a key at a widget that is not listening for one")
        local handler = self.scripts.OnKeyDown
        if handler then handler(self, key) end
    end

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
    env.SlashCmdList = {}

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

    --- A value this client refuses to disclose to tainted code.
    --
    -- Three behaviours, and the third is the one that cost a live crash.
    -- Truthiness passes it through untouched. Comparison and arithmetic
    -- raise. And tostring() does *neither*: it returns a secret string, so
    -- the raise lands later, in whatever first concatenates or formats it --
    -- which is nowhere near the line that looked unsafe.
    function env.__secret()
        local function raise()
            error("invalid value (secret) in FishScale", 0)
        end

        -- tostring returns another secret rather than raising, which is what
        -- makes this shape so easy to let through.
        local secretText
        secretText = setmetatable({}, {
            __concat = raise,
            __lt = raise, __le = raise,
            __add = raise, __sub = raise,
            __tostring = function() return secretText end,
        })

        return secretText
    end

    -- What the interact key is currently aimed at, the client's own
    -- "softinteract" token. nil for nothing; a string names a unit; the
    -- sentinel below stands for a game object, which has no name because it
    -- is not a unit -- and the bobber is one of those.
    env.__softInteract = nil
    stub.GAME_OBJECT = { unnamed = true }

    function env.UnitExists(unit)
        if unit == "softinteract" then
            return env.__softInteract ~= nil
        end
        return unit == "player"
    end

    function env.UnitName(unit)
        if unit ~= "softinteract" then
            return nil
        end
        if type(env.__softInteract) == "string" then
            return env.__softInteract
        end
        return nil
    end

    -- Modifiers held right now. A binding is built from the key plus
    -- whichever of these is down, so a test staging SHIFT-F sets this.
    env.__modifiers = {}
    function env.IsShiftKeyDown() return env.__modifiers.shift or false end
    function env.IsControlKeyDown() return env.__modifiers.ctrl or false end
    function env.IsAltKeyDown() return env.__modifiers.alt or false end

    -- The options panel the client hands an addon a place in.
    env.SettingsPanel = makeWidget("Frame")
    env.SettingsPanel.shown = false
    env.GameMenuFrame = makeWidget("Frame")
    env.GameMenuFrame.shown = false

    function env.HideUIPanel(frame)
        if frame and frame.Hide then frame:Hide() end
    end

    env.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            return {
                name = name,
                frame = frame,
                GetID = function() return "category-id" end,
            }
        end,
        RegisterAddOnCategory = function(category)
            env.__settingsCategory = category
        end,
        OpenToCategory = function(id)
            env.__openedCategory = id
        end,
    }

    env.C_AddOns = {
        GetAddOnMetadata = function(_, field)
            return field == "Version" and "9.9.9" or nil
        end,
    }

    -- The client defers a timer past the current synchronous chain rather
    -- than running it inline, and the game-menu backstop depends on that gap.
    env.__timers = {}
    env.C_Timer = {
        After = function(_, fn) table.insert(env.__timers, fn) end,
    }

    function env.__runTimers()
        local pending = env.__timers
        env.__timers = {}
        for _, fn in ipairs(pending) do fn() end
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
        -- 0 is the client's own default: a cone in front of the player only.
        SoftTargetInteractArc = "0",
        autoLootDefault = "0",
    }
    function env.GetCVar(name) return env.__cvars[name] end
    function env.SetCVar(name, value) env.__cvars[name] = tostring(value) end

    -- What the player is channelling right now, which is the client's own
    -- truth rather than a memory built from events. A test sets
    --   env.__channelling = "Fishing"
    -- to put the line out and nil to bring it in, and can do so *without*
    -- firing an event -- which is the whole point, since a missed event is
    -- the case this models.
    env.__channelling = nil
    function env.UnitChannelInfo(unit)
        if unit ~= "player" or env.__channelling == nil then
            return nil
        end
        -- name, text, texture, startTime, endTime, ... -- only the first is
        -- read, but returning one value where the client returns many would
        -- let a caller that unpacks the rest pass here and fail in the game.
        return env.__channelling, env.__channelling, nil, 0, 0
    end

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
