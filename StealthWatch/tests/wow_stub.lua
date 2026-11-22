-- A stand-in for the parts of the WoW client StealthWatch touches: unit
-- frames' events, nameplates, the players they show, spell names, the raid
-- warning text, sounds and the options window. Widgets record what was done
-- to them so tests can assert on it.
--
-- Shaped after the Forever client's own interface code (Gethe/wow-ui-source,
-- branch "forever", 1.60.1): a cast by anyone but the player can arrive with
-- its spell id secret (SecretWhenUnitSpellCastRestricted), while who an enemy
-- player is never is (SecretWhenUnitIdentityRestricted only hides NPCs).

local stub = {}

local function makeWidget(kind, parent)
    local widget = {
        kind = kind,
        parent = parent,
        scripts = {},
        registeredEvents = {}, -- event -> true for every unit, or a set of unit tokens
        points = {},
        shown = true,
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
    function widget:ClearAllPoints() self.points = {} end
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
    function widget:IsShown() return self.shown end
    function widget:CreateTexture() return makeWidget("Texture", self) end
    function widget:CreateFontString() return makeWidget("FontString", self) end
    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text end
    -- What the client measures a wrapped font string at; zero until a test
    -- says otherwise, as a client that has not laid the text out yet would.
    function widget:GetStringHeight() return self.stringHeight or 0 end
    function widget:SetJustifyH(value) self.justifyH = value end
    function widget:SetTextColor(r, g, b) self.textColor = { r, g, b } end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end

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

-- What the client says of one class: its name, its file name and its colour.
stub.CLASSES = {
    ROGUE = { name = "Rogue", color = "fffff569" },
    DRUID = { name = "Druid", color = "ffff7d0a" },
    MAGE = { name = "Mage", color = "ff3fc7eb" },
    WARRIOR = { name = "Warrior", color = "ffc79c6e" },
}

-- Spell names the client knows, by id: the stealth spells' ranks, and a few
-- that are not stealth.
stub.SPELLS = {
    [1784] = "Stealth", [1785] = "Stealth", [1786] = "Stealth", [1787] = "Stealth",
    [1856] = "Vanish", [1857] = "Vanish",
    [5215] = "Prowl", [6783] = "Prowl", [9913] = "Prowl",
    [20580] = "Shadowmeld",
    [3680] = "Lesser Invisibility", [11392] = "Invisibility",
    [2983] = "Sprint", [1953] = "Blink", [8690] = "Hearthstone", [133] = "Fireball",
}

function stub.newEnv()
    local env = setmetatable({}, { __index = _G })

    env.__frames = {}
    env.__printed = {}
    env._G = env

    env.UIParent = makeWidget("Frame")
    env.SlashCmdList = {}

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do pieces[index] = tostring((select(index, ...))) end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    function env.CreateFrame(kind, name, parent)
        local frame = makeWidget(kind or "Frame", parent)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        return frame
    end

    -- Time: GetTime in seconds since the client started.
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
    -- number, cannot key a table usefully, and comparing it raises.
    local secretMeta = {
        __eq = function() error("attempt to compare a secret number value") end,
        __lt = function() error("attempt to compare a secret number value") end,
        __le = function() error("attempt to compare a secret number value") end,
        __tostring = function() return "<secret number>" end,
    }
    function env.__secret() return setmetatable({}, secretMeta) end
    function env.issecretvalue(value) return getmetatable(value) == secretMeta end

    -- Units, by token ("target", "nameplate3"): what the client says of each.
    -- Make one with __enemy / __friend.
    env.__units = {}
    local function unit(token) return env.__units[token] end
    function env.UnitExists(token) return unit(token) ~= nil end
    function env.UnitIsPlayer(token) local u = unit(token); return u and u.player or false end
    function env.UnitCanAttack(_, token) local u = unit(token); return u and u.hostile or false end
    function env.UnitGUID(token) local u = unit(token); return u and u.guid end
    function env.UnitName(token) local u = unit(token); if u then return u.name, u.realm end end
    function env.UnitLevel(token) local u = unit(token); return u and u.level or 0 end
    function env.UnitRace(token) local u = unit(token); if u then return u.race, u.race end end
    function env.UnitClass(token)
        local u = unit(token)
        if u then return stub.CLASSES[u.classFile].name, u.classFile end
    end
    function env.UnitIsDeadOrGhost(token) local u = unit(token); return u and u.dead or false end

    local serial = 0
    --- An enemy player: name, class file ("ROGUE"), level, race.
    function env.__enemy(name, classFile, level, race)
        serial = serial + 1
        return {
            guid = string.format("Player-5250-%08X", serial), name = name, classFile = classFile or "ROGUE",
            level = level or 60, race = race or "Human", player = true, hostile = true,
        }
    end
    --- A player on the player's own side.
    function env.__friend(name, classFile)
        local u = env.__enemy(name, classFile)
        u.hostile = false
        return u
    end

    -- Class colours, as the client keeps them.
    env.RAID_CLASS_COLORS = {}
    for file, class in pairs(stub.CLASSES) do
        env.RAID_CLASS_COLORS[file] = { colorStr = class.color }
    end

    -- Spell names.
    env.C_Spell = {
        GetSpellName = function(id) return stub.SPELLS[id] end,
    }
    -- How hidden a spell's casts are: 0 never, 1 always, 2 at times. Nil for
    -- an id the client does not know.
    env.__castSecrecy = {}
    env.C_Secrets = {
        GetSpellCastSecrecy = function(id) return env.__castSecrecy[id] end,
    }

    -- Console variables, as strings.
    env.__cvars = { nameplateShowEnemies = "1", nameplateMaxDistance = "41" }
    function env.GetCVar(name) return env.__cvars[name] end
    function env.GetCVarBool(name) return env.__cvars[name] == "1" end

    -- Sounds played: each kit handed to PlaySound, and its channel.
    env.__sounds = {}
    env.SOUNDKIT = { RAID_WARNING = 8959, RAID_BOSS_EMOTE_WARNING = 12197 }
    function env.PlaySound(kit, channel) table.insert(env.__sounds, { kit = kit, channel = channel }) end

    -- The raid warning text in the middle of the screen, Forever's way;
    -- each message as { text, color, displayTime }.
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
