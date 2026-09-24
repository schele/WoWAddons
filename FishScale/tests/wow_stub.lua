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
