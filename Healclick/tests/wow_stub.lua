-- A minimal stand-in for the WoW API, enough to load the addon outside the
-- game. Widgets record what was done to them so tests can assert on it.
--
-- The point of interest is SetAttribute. We can never test that Blizzard casts
-- the right spell; we can test that we asked it to.

local stub = {}

-- env is threaded through explicitly at every top-level creation site
-- (UIParent, CreateFrame, SettingsPanel, GameMenuFrame below); a child
-- widget (CreateTexture/CreateFontString further down) inherits its
-- parent's rather than needing every call site updated. SetAttribute is
-- the one thing here that needs it, to refuse the way the real client does
-- when __inCombat is true.
local function makeWidget(kind, parent, template, env)
    env = env or (parent and parent.__env)

    local widget = {
        kind = kind,
        parent = parent,
        template = template,
        __env = env,
        points = {},
        scripts = {},
        registeredEvents = {},
        children = {},
        attributes = {},
        width = 0,
        height = 0,
        shown = true,
        text = "",
        alpha = 1,
        value = 0,
        minValue = 0,
        maxValue = 1,
        -- An EditBox grabs focus as it comes into existence in the real
        -- client, same as ForeverPanel's stub documents; that starting state
        -- is what lets ClearFocus() fire OnEditFocusLost on the first call.
        focused = (kind == "EditBox"),
    }

    function widget:SetPoint(...) table.insert(self.points, { ... }) end
    function widget:ClearAllPoints() self.points = {} end
    function widget:SetAllPoints() end
    function widget:GetPoint(index)
        local point = self.points[index or 1]
        if point then return table.unpack(point) end
    end

    function widget:SetWidth(value) self.width = value end
    function widget:GetWidth() return self.width end
    function widget:SetHeight(value) self.height = value end
    function widget:GetHeight() return self.height end
    function widget:SetSize(w, h) self.width, self.height = w, h end

    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:SetShown(value) self.shown = value and true or false end
    function widget:IsShown() return self.shown end

    function widget:SetScript(name, fn) self.scripts[name] = fn end
    function widget:GetScript(name) return self.scripts[name] end
    function widget:HookScript(name, fn)
        local existing = self.scripts[name]
        self.scripts[name] = function(...)
            if existing then existing(...) end
            fn(...)
        end
    end

    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end
    function widget:RegisterForClicks() end
    -- Recorded, not ignored: row_spec asserts a button never calls this,
    -- since RegisterForDrag is for STARTING a drag and this addon only ever
    -- receives one (see Row.Create's OnReceiveDrag).
    function widget:RegisterForDrag(...) self.dragRegistered = { ... } end
    function widget:EnableMouse() end
    function widget:SetMovable() end
    function widget:StartMoving() self.moving = true end
    function widget:StopMovingOrSizing() self.moving = false end
    function widget:SetFrameStrata() end
    function widget:SetJustifyH() end
    function widget:SetNormalTexture() end
    function widget:SetAutoFocus(value) self.autoFocus = value and true or false end

    -- Only a real focused -> unfocused transition fires the script, the way
    -- the client does. Without that check, a handler that calls ClearFocus
    -- on itself (as OnEditFocusLost's store logic must not) would recurse
    -- forever instead of running exactly once.
    function widget:ClearFocus()
        if not self.focused then
            return
        end
        self.focused = false
        local handler = self.scripts.OnEditFocusLost
        if handler then handler(self) end
    end

    function widget:SetFocus() self.focused = true end
    function widget:HighlightText() end
    function widget:SetMaxLetters() end

    -- The whole point. Secure attributes are what the client acts on, so the
    -- tests assert on these rather than on anything happening.
    --
    -- Raises, rather than silently no-op-ing or recording a flag: the real
    -- client refuses this outright in combat, loudly enough that an addon
    -- calling it anyway finds out immediately. A stub that instead just
    -- accepted the write quietly would let exactly this class of bug back
    -- in -- a secure write reachable from a path the addon believed was
    -- combat-safe -- the same way a too-permissive stub already has, more
    -- than once, on this branch.
    function widget:SetAttribute(name, value)
        if self.__env and self.__env.__inCombat then
            error("Interface action failed because of an AddOn (SetAttribute blocked during combat lockdown)", 2)
        end
        self.attributes[name] = value
    end
    function widget:GetAttribute(name) return self.attributes[name] end

    function widget:SetAlpha(value) self.alpha = value end
    function widget:GetAlpha() return self.alpha end

    function widget:SetMinMaxValues(low, high) self.minValue, self.maxValue = low, high end
    function widget:GetMinMaxValues() return self.minValue, self.maxValue end
    function widget:SetValue(value)
        self.value = value
        local handler = self.scripts.OnValueChanged
        if handler then handler(self, value) end
    end
    function widget:GetValue() return self.value end
    function widget:SetValueStep() end
    function widget:SetObeyStepOnDrag() end
    function widget:SetStatusBarColor(r, g, b) self.barColor = { r, g, b } end

    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end

    function widget:SetText(value)
        self.text = value or ""
        local handler = self.scripts.OnTextChanged
        if handler then handler(self) end
    end
    function widget:GetText() return self.text end
    function widget:GetName() return self.frameName end
    function widget:SetTextColor(r, g, b) self.textColor = { r, g, b } end
    function widget:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
    function widget:SetTexCoord(...) self.texCoord = { ... } end

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

    function widget:GetParent() return self.parent end
    function widget:SetParent(value) self.parent = value end

    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then handler(self, event, ...) end
    end

    return widget
end

stub.makeWidget = makeWidget

function stub.newEnv()
    local env = setmetatable({}, { __index = _G })

    env.__frames = {}
    env.__printed = {}
    env.__watched = {}
    env.__inCombat = false
    env._G = env

    env.UIParent = makeWidget("Frame", nil, nil, env)
    env.SlashCmdList = {}
    env.OKAY = "Okay"

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do
            pieces[index] = tostring((select(index, ...)))
        end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    function env.CreateFrame(kind, name, parent, template)
        local frame = makeWidget(kind or "Frame", parent, template, env)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        return frame
    end

    -- Combat ------------------------------------------------------------
    function env.InCombatLockdown() return env.__inCombat end

    --- Test helper: enter or leave combat, firing the event the client fires.
    function env.__setCombat(inCombat)
        env.__inCombat = inCombat and true or false
        local event = inCombat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED"
        for _, frame in ipairs(env.__frames) do
            if frame.registeredEvents[event] then
                frame:Fire(event)
            end
        end
    end

    -- Units --------------------------------------------------------------
    -- Tests edit this table directly: env.units.party2.health = 30
    -- checkedRange defaults to true (a normal party member); set it false to
    -- model a unit the client cannot range-check at all, such as "player"
    -- when solo -- a real case UnitInRange signals by returning false, false.
    env.units = {
        player = { name = "Skyler", class = "DRUID", health = 100, healthMax = 100, connected = true, dead = false, inRange = true },
        party1 = { name = "Borgir", class = "WARRIOR", health = 80, healthMax = 100, connected = true, dead = false, inRange = true },
        party2 = { name = "Nimue", class = "MAGE", health = 50, healthMax = 100, connected = true, dead = false, inRange = true },
    }

    local function unit(id) return env.units[id] end

    function env.UnitExists(id) return unit(id) ~= nil end
    function env.UnitName(id) local u = unit(id) return u and u.name end
    function env.UnitClass(id)
        local u = unit(id)
        if not u then return nil end
        return u.class, u.class
    end
    function env.UnitHealth(id) local u = unit(id) return u and u.health or 0 end
    function env.UnitHealthMax(id) local u = unit(id) return u and u.healthMax or 0 end
    function env.UnitIsDeadOrGhost(id) local u = unit(id) return u and u.dead or false end
    function env.UnitIsConnected(id) local u = unit(id) return u and u.connected or false end
    function env.UnitInRange(id)
        local u = unit(id)
        if not u then return false, false end
        if u.checkedRange == false then
            return false, false
        end
        return u.inRange and true or false, true
    end

    env.RAID_CLASS_COLORS = {
        DRUID   = { r = 1.00, g = 0.49, b = 0.04 },
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
        MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
        PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
    }

    -- Spells --------------------------------------------------------------
    -- Everything the client "knows". A name outside this list is unknown,
    -- which is a warning rather than a refusal: a player may be configuring
    -- a spell they have not learned yet.
    env.__spells = {
        ["Regrowth"] = true,
        ["Rejuvenation"] = true,
        ["Remove Curse"] = true,
        ["Mark of the Wild"] = true,
        ["Healing Touch"] = true,
    }

    -- Arbitrary stand-ins for the icon file IDs a real client would return.
    env.__spellTextures = {
        ["Regrowth"] = 136085,
        ["Rejuvenation"] = 136081,
        ["Remove Curse"] = 135921,
        ["Mark of the Wild"] = 136078,
    }

    -- A numeric spellID -> name lookup, standing in for the shape some
    -- clients hand GetCursorInfo back with for a spellbook drag.
    env.__spellIDs = {
        [8936] = "Rejuvenation",
    }

    -- A spellbook (index, bookType) -> name lookup, standing in for the shape
    -- other clients hand GetCursorInfo back with instead.
    env.__spellbook = {
        ["spell:5"] = "Regrowth",
        -- Known by ID/index but not by name, the way a spell a player has
        -- learned but never typed into the settings panel would look.
        ["spell:7"] = "Tranquility",
    }

    -- This env models the target client the spike found: namespaced APIs
    -- only, with GetSpellInfo, GetSpellTexture and GetSpellBookItemName gone
    -- entirely (not merely shadowed by the same data, which could never tell
    -- a test "the namespaced branch ran" from "the legacy one did, and
    -- happened to agree"). A fallback test removes the namespaced piece it
    -- means to test and adds the legacy global back itself, from the same
    -- __spellTextures/__spellIDs/__spellbook tables above, e.g.:
    --   env.C_Spell.GetSpellTexture = nil
    --   env.GetSpellTexture = function(name) return env.__spellTextures[name] end
    env.C_Spell = {
        GetSpellTexture = function(name) return env.__spellTextures[name] end,
        -- The real call accepts a spellID or a name; both __spellIDs and
        -- __spells are checked so this one stub serves CursorSpell's ID
        -- route and Spells.IsKnown's by-name check alike.
        GetSpellInfo = function(identifier)
            local name = env.__spellIDs[identifier]
            if not name and env.__spells[identifier] then
                name = identifier
            end
            if not name then return nil end
            return { name = name, spellID = identifier }
        end,
    }

    env.C_SpellBook = {
        GetSpellBookItemName = function(index, bookType)
            return env.__spellbook[tostring(bookType) .. ":" .. tostring(index)]
        end,
    }

    -- Cursor ----------------------------------------------------------------
    -- Tests drive this directly: env.__cursor = { "spell", 5, "spell" } for a
    -- spellbook-index drag, or { "spell", nil, nil, 8936, n = 4 } for one that
    -- carries a spellID instead (the explicit n covers the hole a plain #
    -- would trip over). GetCursorInfo reports it positionally, the way the
    -- real API does; ClearCursor empties it the way a completed drop does.
    env.__cursor = nil

    function env.GetCursorInfo()
        if not env.__cursor then
            return nil
        end
        local cursor = env.__cursor
        return table.unpack(cursor, 1, cursor.n or #cursor)
    end

    function env.ClearCursor()
        env.__cursor = nil
    end

    -- Secure visibility ----------------------------------------------------
    function env.RegisterUnitWatch(frame)
        env.__watched[#env.__watched + 1] = frame
        frame.unitWatched = true
    end

    function env.UnregisterUnitWatch(frame)
        frame.unitWatched = false
    end

    -- Settings -------------------------------------------------------------
    env.SettingsPanel = makeWidget("Frame", nil, nil, env)
    env.GameMenuFrame = makeWidget("Frame", nil, nil, env)
    function env.HideUIPanel(frame) if frame and frame.Hide then frame:Hide() end end

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

    env.__timers = {}
    env.__tickers = {}

    env.C_Timer = {
        After = function(_, fn) table.insert(env.__timers, fn) end,
        NewTicker = function(interval, fn)
            local ticker = { interval = interval, fn = fn, Cancel = function() end }
            table.insert(env.__tickers, ticker)
            return ticker
        end,
    }

    function env.__runTimers()
        local pending = env.__timers
        env.__timers = {}
        for _, fn in ipairs(pending) do fn() end
    end

    --- Test helper: run every ticker once, the way a few seconds would.
    function env.__tick()
        for _, ticker in ipairs(env.__tickers) do ticker.fn() end
    end

    function env.hooksecurefunc(target, name, post)
        if type(target) == "string" then
            target, name, post = env, target, name
        end
        local original = target[name]
        target[name] = function(...)
            local result = original(...)
            post(...)
            return result
        end
    end

    return env
end

return stub
