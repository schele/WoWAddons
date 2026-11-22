-- A stand-in for the parts of the WoW client BiteTime touches: the target and
-- its health, the player's form, combo points and energy, the spells and
-- their tooltips, the action bars, status bars, and the options window.
-- Widgets record what was done to them so tests can assert on it.
--
-- Shaped after the Forever client's own interface code (Gethe/wow-ui-source,
-- branch "forever", 1.60.1 build 70888): UnitHealth always answers addons
-- with a secret (SecretReturns), and so does UnitHealthMax for any unit that
-- isn't player-controlled (SecretWhenUnitHealthMaxRestricted): every mob. A
-- secret can be handed to a status bar, but comparing it or doing sums with
-- it raises. newEnv({ era = true }) is Classic Era instead: no secrets.

local stub = {}

local function makeWidget(kind, parent)
    local widget = {
        kind = kind,
        parent = parent,
        scripts = {},
        registeredEvents = {}, -- event -> true for every unit, or a set of unit tokens
        points = {},
        shown = true,
        alpha = 1,
        animations = {},
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
    function widget:SetAllPoints(relativeTo) self.allPoints = relativeTo or true end
    function widget:ClearAllPoints() self.points = {} end
    function widget:SetSize(w, h) self.width, self.height = w, h end
    function widget:SetWidth(value) self.width = value end
    function widget:SetHeight(value) self.height = value end
    function widget:GetWidth() return self.width or 0 end
    function widget:GetHeight() return self.height or 0 end
    function widget:SetFrameStrata(value) self.strata = value end
    function widget:SetFrameLevel(value) self.level = value end
    function widget:GetFrameLevel() return self.level or 1 end
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
    function widget:SetShown(value) if value then self:Show() else self:Hide() end end
    function widget:SetAlpha(value) self.alpha = value end
    function widget:GetAlpha() return self.alpha end
    function widget:CreateTexture(_, layer) local t = makeWidget("Texture", self); t.layer = layer; return t end
    function widget:CreateFontString() return makeWidget("FontString", self) end
    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
    function widget:SetTexCoord(...) self.texCoord = { ... } end
    function widget:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
    function widget:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a } end
    function widget:SetBlendMode(value) self.blendMode = value end
    function widget:SetDrawLayer(value) self.layer = value end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text end
    -- What the client measures a wrapped font string at; zero until a test
    -- says otherwise, as a client that has not laid the text out yet would.
    function widget:GetStringHeight() return self.stringHeight or 0 end
    function widget:SetJustifyH(value) self.justifyH = value end
    function widget:SetTextColor(r, g, b) self.textColor = { r, g, b } end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end

    -- Sliders: setting the value runs OnValueChanged, as the client's does.
    function widget:SetMinMaxValues(low, high) self.minValue, self.maxValue = low, high end
    function widget:GetMinMaxValues() return self.minValue, self.maxValue end
    function widget:SetValueStep(value) self.valueStep = value end
    function widget:SetObeyStepOnDrag(value) self.obeyStep = value end
    function widget:SetValue(value)
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
    function widget:GetValue() return self.value end

    -- Animations: a group of steps that plays, loops and stops.
    function widget:CreateAnimationGroup()
        local group = { animations = {}, playing = false }
        function group:CreateAnimation(animKind)
            local anim = { kind = animKind }
            function anim:SetFromAlpha(value) self.fromAlpha = value end
            function anim:SetToAlpha(value) self.toAlpha = value end
            function anim:SetDuration(value) self.duration = value end
            function anim:SetSmoothing(value) self.smoothing = value end
            function anim:SetOrder(value) self.order = value end
            table.insert(self.animations, anim)
            return anim
        end
        function group:SetLooping(value) self.looping = value end
        function group:Play() self.playing = true end
        function group:Stop() self.playing = false end
        function group:IsPlaying() return self.playing end
        table.insert(self.animations, group)
        table.insert(widget.animations, group)
        return group
    end

    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end
    function widget:UnregisterAllEvents() self.registeredEvents = {} end
    function widget:RegisterUnitEvent(event, ...)
        local units = {}
        for index = 1, select("#", ...) do units[(select(index, ...))] = true end
        self.registeredEvents[event] = units
    end
    --- Whether this frame hears `event` for `unit` (nil: an event with no unit).
    function widget:Hears(event, unit)
        local registration = self.registeredEvents[event]
        if registration == true then return true end
        return type(registration) == "table" and unit ~= nil and registration[unit] == true
    end

    -- Test helper: drive this widget's OnEvent handler.
    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then handler(self, event, ...) end
    end

    return widget
end

stub.makeWidget = makeWidget

-- Ferocious Bite's tooltip on WoW Forever, word for word from the game
-- (rank 1, 2026-11-11), and a made-up second rank worded the same way.
stub.BITE_TEXT = "Finishing move that causes damage per combo point and converts each extra point of energy "
    .. "into 0.7 additional damage.  Damage is increased by your Attack Power.\n"
    .. "   1 point  : 40-54 damage\n   2 points: 70-84 damage\n   3 points: 100-114 damage\n"
    .. "   4 points: 130-144 damage\n   5 points: 160-174 damage"
stub.BITE_TEXT_2 = "Finishing move that causes damage per combo point and converts each extra point of energy "
    .. "into 1.1 additional damage.  Damage is increased by your Attack Power.\n"
    .. "   1 point  : 64-84 damage\n   2 points: 112-132 damage\n   3 points: 160-180 damage\n"
    .. "   4 points: 208-228 damage\n   5 points: 256-276 damage"

-- Spells the client knows of, by id: two ranks of Ferocious Bite and a
-- builder that is not a finisher.
stub.SPELLS = {
    [22568] = { name = "Ferocious Bite", rank = "Rank 1", icon = 132127, description = stub.BITE_TEXT, cost = 35 },
    [22827] = { name = "Ferocious Bite", rank = "Rank 2", icon = 132127, description = stub.BITE_TEXT_2, cost = 35 },
    [5221] = { name = "Shred", rank = "Rank 1", icon = 136231, description = "Shred the target.", cost = 60 },
}

-- The action bars, as the client names their buttons, and the slot each
-- one's first button shows (the main bar's pages with the form).
stub.BARS = {
    { name = "ActionButton", first = 1 },
    { name = "MultiBarBottomLeftButton", first = 61 },
    { name = "MultiBarBottomRightButton", first = 49 },
    { name = "MultiBarRightButton", first = 25 },
    { name = "MultiBarLeftButton", first = 37 },
}

function stub.newEnv(options)
    options = options or {}
    local env = setmetatable({}, { __index = _G })

    env.__frames = {}
    env.__printed = {}
    env._G = env

    env.UIParent = makeWidget("Frame")
    env.SlashCmdList = {}
    env.unpack = table.unpack -- the game's Lua 5.1 has it as a global

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do pieces[index] = tostring((select(index, ...))) end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    local statusBar -- defined with the secrets below

    function env.CreateFrame(kind, name, parent)
        local frame = makeWidget(kind or "Frame", parent)
        frame.frameName = name
        if kind == "StatusBar" then statusBar(frame) end
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        return frame
    end

    -- Time: GetTime in seconds since the client started; timers wait for
    -- __runTimers, which runs those due by then.
    env.__now = 100
    function env.GetTime() return env.__now end
    env.__timers = {}
    env.C_Timer = {
        After = function(seconds, fn) table.insert(env.__timers, { at = env.__now + seconds, fn = fn }) end,
    }
    function env.__runTimers()
        local pending = env.__timers
        env.__timers = {}
        for _, timer in ipairs(pending) do
            if timer.at <= env.__now then
                timer.fn()
            else
                table.insert(env.__timers, timer)
            end
        end
    end

    -- Secret values: the call that hands one out succeeds, but it is no
    -- number, and comparing it or doing sums with it raises. __reveal lets a
    -- test see what the client would have drawn.
    local hidden = setmetatable({}, { __mode = "k" })
    local function refuse() error("attempt to perform arithmetic or compare on a secret value") end
    local secretMeta = {
        __eq = refuse, __lt = refuse, __le = refuse,
        __add = refuse, __sub = refuse, __mul = refuse, __div = refuse, __unm = refuse, __mod = refuse,
        __tostring = function() return "<secret number>" end,
    }
    function env.__secret(value)
        local secret = setmetatable({}, secretMeta)
        hidden[secret] = value
        return secret
    end
    function env.__reveal(value)
        if getmetatable(value) == secretMeta then return hidden[value] end
        return value
    end
    function env.issecretvalue(value) return getmetatable(value) == secretMeta end
    local function isSecret(value) return getmetatable(value) == secretMeta end

    -- Status bars, as the client draws them. A secret may go in as the range
    -- or the value (SecretArguments AllowedWhenTainted); from then on the
    -- bar gives its value back only as a secret. The value is kept inside
    -- the range, unless a test sets __barsKeepAnyValue. The fill is the
    -- value's place in the range; a range of nothing draws empty, or full
    -- with the StandardNoRangeFill style (unless both ends are zero).
    env.Enum = {
        StatusBarFillStyle = { Standard = 0, StandardNoRangeFill = 1, Center = 2, Reverse = 3 },
    }
    function statusBar(bar)
        bar.fillStyle = 0 -- Standard
        bar.low, bar.high, bar.value = 0, 0, 0
        local function take(value)
            if isSecret(value) then bar.secretValue = true end
            return env.__reveal(value)
        end
        local function keepInRange()
            if not env.__barsKeepAnyValue then
                bar.value = math.max(bar.low, math.min(bar.high, bar.value))
            end
        end
        function bar:SetFillStyle(style) self.fillStyle = style end
        -- What the client does with a range upside down is not known, so the
        -- stand-in refuses one: code that never makes one is safe either way.
        function bar:SetMinMaxValues(low, high)
            local a, b = take(low), take(high)
            if a > b then error("SetMinMaxValues: the low end is above the high end") end
            self.low, self.high = a, b
            keepInRange()
        end
        function bar:GetMinMaxValues()
            if self.secretValue then return env.__secret(self.low), env.__secret(self.high) end
            return self.low, self.high
        end
        function bar:SetValue(value)
            self.value = take(value)
            keepInRange()
        end
        function bar:GetValue()
            return self.secretValue and env.__secret(self.value) or self.value
        end
        function bar:SetStatusBarTexture(asset)
            self.fill = self.fill or makeWidget("Texture", self)
            self.fill.texture = asset
            return true
        end
        function bar:GetStatusBarTexture() return self.fill end
        function bar:SetStatusBarColor(r, g, b, a) self.barColor = { r, g, b, a } end
        --- Test helper: how full the client draws this bar, 0 to 1. A bar
        -- with no texture draws nothing.
        function bar:__drawn()
            if not self.fill then return 0 end
            local range = self.high - self.low
            if range == 0 then
                local noRange = self.fillStyle == 1 -- StandardNoRangeFill
                return (noRange and not (self.low == 0 and self.high == 0)) and 1 or 0
            end
            return math.max(0, math.min(1, (self.value - self.low) / range))
        end
    end

    env.Enum.PowerType = { Energy = 3, ComboPoints = 14 }

    -- Units, by token: what the client says of each. Make one with __mob,
    -- __enemyPlayer or __friend.
    env.__units = {}
    local function unit(token) return env.__units[token] end
    function env.UnitExists(token) return unit(token) ~= nil end
    function env.UnitName(token) local u = unit(token); return u and u.name end
    function env.UnitIsPlayer(token) local u = unit(token); return u and u.player or false end
    function env.UnitCanAttack(_, token) local u = unit(token); return u and u.hostile or false end
    function env.UnitIsDeadOrGhost(token) local u = unit(token); return u and u.dead or false end
    function env.UnitHealth(token)
        local u = unit(token)
        local health = u and u.health or 0
        return env.__era and health or env.__secret(health)
    end
    -- Forever hides max health too when the unit isn't player-controlled
    -- (SecretWhenUnitHealthMaxRestricted): every mob.
    function env.UnitHealthMax(token)
        local u = unit(token)
        local max = u and u.healthMax or 0
        if env.__era or (u and u.player) then return max end
        return env.__secret(max)
    end

    --- A mob the player can attack, with `health` of `healthMax` left.
    function env.__mob(name, health, healthMax)
        return { name = name, health = health, healthMax = healthMax or health, hostile = true }
    end
    function env.__enemyPlayer(name, health, healthMax)
        local u = env.__mob(name, health, healthMax)
        u.player = true
        return u
    end
    function env.__friend(name, health)
        local u = env.__mob(name, health)
        u.hostile = false
        return u
    end

    -- The player: a druid in Cat Form with full energy and no combo points.
    env.__form = 1
    env.__points = 0
    env.__energy = 100
    function env.GetShapeshiftFormID() return env.__form end
    function env.GetComboPoints(who, target)
        if who ~= "player" or target ~= "target" or not unit("target") then return 0 end
        return env.__points
    end
    function env.UnitPower(token, powerType)
        if token == "player" and powerType == env.Enum.PowerType.Energy then return env.__energy end
        return 0
    end

    -- Spells: names, ranks, tooltips, icons and costs, and which ranks the
    -- character knows. Asked by name, the client answers with the highest
    -- rank known.
    env.__known = { [22568] = true, [5221] = true }
    local function spell(id) return stub.SPELLS[id] end
    env.C_Spell = {
        GetSpellName = function(id) local s = spell(id); return s and s.name end,
        GetSpellSubtext = function(id) local s = spell(id); return s and s.rank end,
        GetSpellDescription = function(id) local s = spell(id); return s and s.description end,
        GetSpellTexture = function(id) local s = spell(id); return s and s.icon end,
        GetSpellPowerCost = function(id)
            local s = spell(id)
            if s then return { { type = env.Enum.PowerType.Energy, cost = s.cost, name = "ENERGY" } } end
        end,
        GetSpellInfo = function(identifier)
            if type(identifier) == "number" then
                local s = spell(identifier)
                return s and { name = s.name, spellID = identifier, iconID = s.icon }
            end
            local best
            for id, s in pairs(stub.SPELLS) do
                if s.name == identifier and env.__known[id] and (not best or id > best) then best = id end
            end
            return best and { name = identifier, spellID = best, iconID = spell(best).icon }
        end,
    }

    -- The action bars: each button shows a slot, and a slot holds a spell.
    env.__actions = {}
    function env.GetActionInfo(slot)
        local action = env.__actions[slot]
        if action then return action[1], action[2] end
    end
    env.__buttons = {}
    for _, bar in ipairs(stub.BARS) do
        for index = 1, 12 do
            local button = makeWidget("CheckButton", env.UIParent)
            button.action = bar.first + index - 1
            env[bar.name .. index] = button
            table.insert(env.__buttons, button)
        end
    end
    --- Put spell `id` in action slot `slot`.
    function env.__place(slot, id) env.__actions[slot] = { "spell", id } end

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

    -- Classic Era: health is a plain number and there are no secrets. Nor,
    -- here, the StandardNoRangeFill style, so the plain way is tested too.
    if options.era then
        env.__era = true
        env.issecretvalue = nil
        env.Enum.StatusBarFillStyle = nil
    end

    return env
end

return stub
