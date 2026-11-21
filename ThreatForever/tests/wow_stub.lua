-- A stand-in for the parts of the WoW client ThreatForever touches: units and
-- the group, each one's threat on a mob, combat, the window's frame, status
-- bars, the raid warning text, sounds and the options window. Widgets record
-- what was done to them so tests can assert on it.
--
-- Shaped after the Forever client's own interface code (Gethe/wow-ui-source,
-- branch "forever", 1.60.1). UnitDetailedThreatSituation is tagged
-- SecretWhenUnitThreatValuesRestricted: plain when one unit is the player, a
-- pet or an ally and the other "a non-boss or nameplate target". So against a
-- boss the numbers come back secret. UnitThreatSituation is tagged
-- SecretWhenUnitThreatStateRestricted, plain against a "nameplate, boss,
-- target, etc.", so who is about to pull stays readable on a boss.

local stub = {}

local function makeWidget(kind, parent)
    local widget = {
        kind = kind,
        parent = parent,
        scripts = {},
        registeredEvents = {},
        points = {},
        shown = true,
        children = {},
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
    function widget:SetPoint(...) table.insert(self.points, { ... }) end
    function widget:GetPoint(index)
        local point = self.points[index or 1]
        if point then return table.unpack(point) end
    end
    function widget:ClearAllPoints() self.points = {} end
    function widget:SetAllPoints(target) self.allPoints = target or true end
    function widget:SetSize(w, h) self.width, self.height = w, h end
    function widget:SetWidth(value) self.width = value end
    function widget:SetHeight(value) self.height = value end
    function widget:GetWidth() return self.width or 0 end
    function widget:GetHeight() return self.height or 0 end
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
    function widget:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function widget:IsShown() return self.shown end
    function widget:CreateTexture() return makeWidget("Texture", self) end
    function widget:CreateFontString() return makeWidget("FontString", self) end
    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
    function widget:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function widget:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a } end
    function widget:SetAlpha(value) self.alpha = value end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text end
    -- string.format, as the client's: a secret number raises here, so a
    -- caller that hands one over has to be ready for that.
    function widget:SetFormattedText(format, ...) self.text = string.format(format, ...) end
    function widget:GetStringHeight() return self.stringHeight or 0 end
    function widget:SetJustifyH(value) self.justifyH = value end
    function widget:SetWordWrap(value) self.wordWrap = value end
    function widget:SetTextColor(r, g, b) self.textColor = { r, g, b } end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end
    function widget:SetFrameStrata(value) self.strata = value end
    function widget:SetFrameLevel(value) self.level = value end
    function widget:SetClampedToScreen(value) self.clamped = value end
    function widget:SetMovable(value) self.movable = value end
    function widget:EnableMouse(value) self.mouse = value end
    function widget:RegisterForDrag(...) self.drag = { ... } end
    function widget:StartMoving() self.moving = true end
    function widget:StopMovingOrSizing() self.moving = false end

    -- Status bars. A secret value is taken and drawn, as the client's bars
    -- do: that is the one place an addon may hand one over and have it shown.
    function widget:SetMinMaxValues(low, high) self.min, self.max = low, high end
    function widget:GetValue() return self.value end
    -- A slider fires OnValueChanged when its value changes, as the client's.
    function widget:SetValue(value)
        if self.kind == "Slider" then
            if self.value == value then return end
            self.value = value
            if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value, false) end
            return
        end
        self.value = value
    end
    function widget:SetValueStep(value) self.valueStep = value end
    function widget:SetObeyStepOnDrag(value) self.obeyStep = value end
    --- Test helper: the player dragging a slider to `value`.
    function widget:Drag(value)
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value, true) end
    end
    function widget:SetStatusBarTexture(value) self.barTexture = value end
    function widget:SetStatusBarColor(r, g, b, a) self.barColor = { r, g, b, a } end

    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end
    function widget:UnregisterAllEvents() self.registeredEvents = {} end
    function widget:RegisterUnitEvent(event, ...)
        local units = {}
        for index = 1, select("#", ...) do units[(select(index, ...))] = true end
        self.registeredEvents[event] = units
    end
    function widget:Hears(event, unit)
        local registration = self.registeredEvents[event]
        if registration == true then return true end
        return type(registration) == "table" and unit ~= nil and registration[unit] == true
    end
    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then handler(self, event, ...) end
    end

    return widget
end

stub.makeWidget = makeWidget

-- What the client says of one class: its name and its colour.
stub.CLASSES = {
    WARRIOR = { name = "Warrior", r = 0.78, g = 0.61, b = 0.43 },
    ROGUE = { name = "Rogue", r = 1, g = 0.96, b = 0.41 },
    MAGE = { name = "Mage", r = 0.25, g = 0.78, b = 0.92 },
    PRIEST = { name = "Priest", r = 1, g = 1, b = 1 },
    HUNTER = { name = "Hunter", r = 0.67, g = 0.83, b = 0.45 },
}

-- The game's threat colours, by status: 0 under the tank, 1 over the tank
-- but not yet pulled, 2 tanking with someone over you, 3 tanking securely.
stub.THREAT_COLORS = {
    [0] = { 0.69, 0.69, 0.69 },
    [1] = { 1, 1, 0.47 },
    [2] = { 1, 0.6, 0 },
    [3] = { 1, 0, 0 },
}

function stub.newEnv()
    local env = setmetatable({}, { __index = _G })

    env.__frames = {}
    env.__printed = {}
    env._G = env

    env.UIParent = makeWidget("Frame")
    env.SlashCmdList = {}
    env.UISpecialFrames = {}

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do pieces[index] = tostring((select(index, ...))) end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    -- CreateFrame. "SettingsFrameTemplate" brings the options window's
    -- frame: its border and title (NineSlice), background (Bg) and red X.
    function env.CreateFrame(kind, name, parent, template)
        local frame = makeWidget(kind or "Frame", parent)
        frame.frameName = name
        frame.template = template
        if template == "OptionsSliderTemplate" then
            frame.Low = makeWidget("FontString", frame)
            frame.High = makeWidget("FontString", frame)
            frame.Text = makeWidget("FontString", frame)
        end
        if template == "SettingsFrameTemplate" then
            frame.NineSlice = makeWidget("Frame", frame)
            frame.NineSlice.Text = makeWidget("FontString", frame.NineSlice)
            frame.Bg = makeWidget("Frame", frame)
            frame.ClosePanelButton = makeWidget("Button", frame)
        end
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        return frame
    end

    -- Time.
    env.__now = 100
    function env.GetTime() return env.__now end
    env.__timers = {}
    env.C_Timer = { After = function(_, fn) table.insert(env.__timers, fn) end }
    function env.__runTimers()
        local pending = env.__timers
        env.__timers = {}
        for _, fn in ipairs(pending) do fn() end
    end

    -- A secret value: the call that hands it out succeeds, but it is no
    -- number and comparing it raises.
    local secretMeta = {
        __eq = function() error("attempt to compare a secret number value") end,
        __lt = function() error("attempt to compare a secret number value") end,
        __le = function() error("attempt to compare a secret number value") end,
        __tostring = function() return "<secret number>" end,
    }
    function env.__secret() return setmetatable({}, secretMeta) end
    function env.issecretvalue(value) return getmetatable(value) == secretMeta end

    -- Units, by token: what the client says of each. A mob carries `threat`,
    -- each group token's place on its threat list: { scaled, status,
    -- tanking }. A mob with `boss` hands the numbers out secret.
    env.__units = {}
    local function unit(token) return token and env.__units[token] end
    function env.UnitExists(token) return unit(token) ~= nil end
    function env.UnitName(token) local u = unit(token); if u then return u.name end end
    function env.UnitGUID(token) local u = unit(token); return u and u.guid end
    function env.UnitClass(token)
        local u = unit(token)
        if u and u.classFile then return stub.CLASSES[u.classFile].name, u.classFile end
    end
    function env.UnitCanAttack(_, token) local u = unit(token); return u and u.hostile or false end
    function env.UnitIsDeadOrGhost(token) local u = unit(token); return u and u.dead or false end
    function env.UnitIsUnit(a, b)
        local ua, ub = unit(a), unit(b)
        return ua ~= nil and ua == ub
    end
    function env.UnitAffectingCombat(token)
        local u = unit(token)
        return u and u.combat or false
    end

    local function entry(token, mobToken)
        local mob = unit(mobToken)
        local who = unit(token)
        if not (mob and who and mob.threat) then return nil, mob end
        -- Keyed by the group member's own record, so "player" and "raid1"
        -- for the same person read the same place.
        for key, value in pairs(mob.threat) do
            if unit(key) == who then return value, mob end
        end
        return nil, mob
    end

    -- Nothing at all for a unit not on the list (MayReturnNothing).
    function env.UnitDetailedThreatSituation(token, mobToken)
        local place, mob = entry(token, mobToken)
        if not place then return end
        if mob.boss then
            return env.__secret(), env.__secret(), env.__secret(), env.__secret(), env.__secret()
        end
        return place.tanking or false, place.status or 0, place.scaled or 0, place.scaled or 0, 0
    end

    function env.UnitThreatSituation(token, mobToken)
        local place = entry(token, mobToken)
        if not place then return nil end
        return place.status or 0
    end

    -- Nameplates: a mob with one has a "nameplateN" token, the same unit as
    -- any other token for it. The game says which plate is the target's.
    env.C_NamePlate = {
        GetNamePlateForUnit = function(token)
            local u = unit(token)
            if not u then return nil end
            for index = 1, 40 do
                local plate = "nameplate" .. index
                if env.__units[plate] == u then
                    return { namePlateUnitToken = plate }
                end
            end
        end,
    }

    function env.GetThreatStatusColor(status)
        local color = stub.THREAT_COLORS[status] or stub.THREAT_COLORS[0]
        return color[1], color[2], color[3]
    end

    env.RAID_CLASS_COLORS = {}
    for file, class in pairs(stub.CLASSES) do
        env.RAID_CLASS_COLORS[file] = { r = class.r, g = class.g, b = class.b }
    end

    -- The group: __party is the other party members' tokens in order, or
    -- with __raid set, every raid token including the player's own.
    env.__party = {}
    env.__raid = nil
    function env.IsInRaid() return env.__raid ~= nil end
    function env.IsInGroup() return env.__raid ~= nil or #env.__party > 0 end
    function env.GetNumGroupMembers()
        if env.__raid then return #env.__raid end
        return #env.__party > 0 and #env.__party + 1 or 0
    end
    function env.GetNumSubgroupMembers() return #env.__party end

    -- Sounds played: each kit handed to PlaySound, and its channel.
    env.__sounds = {}
    env.SOUNDKIT = { RAID_WARNING = 8959 }
    function env.PlaySound(kit, channel) table.insert(env.__sounds, { kit = kit, channel = channel }) end

    -- The raid warning text in the middle of the screen, Forever's way.
    env.__warnings = {}
    env.RaidWarningFrame = makeWidget("Frame", env.UIParent)
    env.RaidWarningUtil = {
        AddMessage = function(text, color, displayTime)
            table.insert(env.__warnings, { text = text, color = color, displayTime = displayTime })
        end,
    }

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
