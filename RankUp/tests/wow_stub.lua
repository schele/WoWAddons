-- A minimal stand-in for the WoW API, enough to load RankUp outside the
-- game: frames, action slots, spells by rank, the cursor and combat.
-- Widgets record what was done to them so tests can assert on it.

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
    }

    function widget:SetScript(name, fn) self.scripts[name] = fn end
    function widget:GetScript(name) return self.scripts[name] end
    function widget:SetPoint(...) table.insert(self.points, { ... }) end
    function widget:ClearAllPoints() self.points = {} end
    function widget:SetAllPoints() end
    function widget:SetSize(w, h) self.width, self.height = w, h end
    function widget:SetWidth(value) self.width = value end
    function widget:SetHeight(value) self.height = value end
    function widget:GetWidth() return self.width or 0 end
    function widget:GetHeight() return self.height or 0 end
    function widget:GetParent() return self.parent end
    function widget:GetName() return self.frameName end
    function widget:SetFrameStrata(value) self.strata = value end
    function widget:SetClampedToScreen() end
    function widget:SetMovable() end
    function widget:EnableMouse(value) self.mouseEnabled = value end
    function widget:RegisterForDrag(...) self.drag = { ... } end
    function widget:StartMoving() self.moving = true end
    function widget:StopMovingOrSizing() self.moving = false end
    function widget:SetBackdrop(value) self.backdrop = value end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text end
    function widget:SetJustifyH(value) self.justifyH = value end
    function widget:SetWordWrap(value) self.wordWrap = value end
    function widget:SetTexture(value) self.texture = value end
    function widget:CreateFontString() return makeWidget(env, "FontString", self) end
    function widget:CreateTexture() return makeWidget(env, "Texture", self) end
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
    function widget:IsShown() return self.shown end
    function widget:SetEnabled(value) self.enabled = value and true or false end
    function widget:Enable() self.enabled = true end
    function widget:Disable() self.enabled = false end
    function widget:IsEnabled() return self.enabled end
    -- The client raises on an event name it does not have.
    function widget:RegisterEvent(event)
        if env.__unknownEvents[event] then
            error("Attempt to register unknown event \"" .. event .. "\"", 2)
        end
        self.registeredEvents[event] = true
    end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end

    -- Test helper: drive this widget's OnEvent handler.
    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then handler(self, event, ...) end
    end
    -- Test helper: a mouse click, which a disabled button ignores.
    function widget:Click()
        if self.enabled and self.scripts.OnClick then
            self.scripts.OnClick(self, "LeftButton")
        end
    end

    return widget
end

function stub.newEnv()
    local env = setmetatable({}, { __index = _G })

    env.__frames = {}
    env.__printed = {}
    env.__unknownEvents = {}
    env._G = env

    env.UIParent = makeWidget(env, "Frame")
    env.UISpecialFrames = {}
    env.SlashCmdList = {}

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

    env.__inCombat = false
    function env.InCombatLockdown() return env.__inCombat end

    -- Spells by ID, with a rank number; a spell with one rank has none, and
    -- the client gives it no rank words.
    env.__spells = {
        [5185] = { name = "Healing Touch", rank = 1 },
        [5186] = { name = "Healing Touch", rank = 2 },
        [5187] = { name = "Healing Touch", rank = 3 },
        [5188] = { name = "Healing Touch", rank = 4 },
        [5189] = { name = "Healing Touch", rank = 5 },
        [774] = { name = "Rejuvenation", rank = 1 },
        [1058] = { name = "Rejuvenation", rank = 2 },
        [1430] = { name = "Rejuvenation", rank = 3 },
        [6807] = { name = "Maul", rank = 1 },
        [6808] = { name = "Maul", rank = 2 },
        [5487] = { name = "Bear Form" },
    }
    -- What the character knows: every rank above, to begin with.
    env.__known = {}
    for id in pairs(env.__spells) do
        env.__known[id] = true
    end

    -- Asked by name, the client answers with the highest rank known, and
    -- with nothing for a name the character does not know.
    local function topKnown(name)
        local best, bestRank
        for id, spell in pairs(env.__spells) do
            local rank = spell.rank or 0
            if spell.name == name and env.__known[id] and (not best or rank > bestRank) then
                best, bestRank = id, rank
            end
        end
        return best
    end

    env.C_Spell = {
        GetSpellInfo = function(identifier)
            local id = identifier
            if type(identifier) == "string" then
                id = topKnown(identifier)
            end
            local spell = id and env.__spells[id]
            if not spell then return nil end
            return { name = spell.name, spellID = id, iconID = 136041 }
        end,
        GetSpellSubtext = function(id)
            local spell = env.__spells[id]
            if spell and spell.words then return spell.words end
            if spell and spell.rank then return "Rank " .. spell.rank end
            return ""
        end,
        PickupSpell = function(id)
            if env.__known[id] then
                env.__cursor = { kind = "spell", id = id }
            end
        end,
    }

    -- Action slots: { kind = "spell" | "item" | "macro", id = number }, or
    -- nil for an empty one.
    env.__actions = {}
    -- Slots whose read raises, as the client does on a secret value.
    env.__raisingSlots = {}
    -- Slots that ignore PlaceAction without saying so.
    env.__stuckSlots = {}
    -- Every slot PlaceAction was called for, in order.
    env.__placements = {}
    -- Called after each PlaceAction, for a test that starts a fight there.
    env.__onPlace = nil

    function env.GetActionInfo(slot)
        if env.__raisingSlots[slot] then
            error("attempt to compare a secret value", 2)
        end
        local action = env.__actions[slot]
        if action then return action.kind, action.id end
    end
    function env.HasAction(slot) return env.__actions[slot] ~= nil end

    env.__cursor = nil
    function env.ClearCursor() env.__cursor = nil end
    -- What is on the cursor: a spell's kind, its book index and book type
    -- (unused here), then its ID, as the client gives them.
    function env.GetCursorInfo()
        local held = env.__cursor
        if held then return held.kind, nil, nil, held.id end
    end

    -- Placing swaps the cursor and the slot, as a drag does; refused in
    -- combat, as the client refuses it.
    function env.PlaceAction(slot)
        if env.__inCombat then
            error("PlaceAction is blocked in combat", 2)
        end
        table.insert(env.__placements, slot)
        if not env.__stuckSlots[slot] then
            local old = env.__actions[slot]
            env.__actions[slot] = env.__cursor
            env.__cursor = old
        end
        if env.__onPlace then env.__onPlace(slot) end
    end

    return env
end

--- The older client: no C_Spell, the old globals in its place, answering
-- the same way.
function stub.useLegacySpellAPI(env)
    local modern = env.C_Spell
    env.C_Spell = nil

    function env.GetSpellInfo(identifier)
        local found = modern.GetSpellInfo(identifier)
        if not found then return nil end
        return found.name, nil, found.iconID, 0, 0, 0, found.spellID
    end
    env.GetSpellSubtext = modern.GetSpellSubtext
    env.PickupSpell = modern.PickupSpell
end

return stub
