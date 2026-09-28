-- A minimal stand-in for the WoW API, enough to load GatherMap outside the
-- game. Widgets record what was done to them so tests can assert on it.

local stub = {}

local function makeWidget(kind, parent)
    local widget = {
        kind = kind,
        parent = parent,
        scripts = {},
        registeredEvents = {},
        points = {},
        shown = true,
        scale = 1,
        frameLevel = parent and (parent.frameLevel or 1) + 1 or 1,
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
    function widget:SetScale(value) self.scale = value end
    function widget:GetScale() return self.scale end
    function widget:SetAlpha(value) self.alpha = value end
    function widget:GetAlpha() return self.alpha or 1 end
    function widget:GetParent() return self.parent end
    function widget:SetFrameStrata(value) self.strata = value end
    function widget:SetFrameLevel(value) self.frameLevel = value end
    function widget:GetFrameLevel() return self.frameLevel end
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
    function widget:SetShown(value) if value then self:Show() else self:Hide() end end
    function widget:IsShown() return self.shown end
    function widget:GetCenter() return self.centerX or 0, self.centerY or 0 end
    function widget:GetEffectiveScale() return 1 end
    function widget:CreateTexture() return makeWidget("Texture", self) end
    function widget:CreateFontString() return makeWidget("FontString", self) end
    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
    function widget:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function widget:SetTexCoord(...) self.texCoord = { ... } end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text end
    function widget:SetTextColor(r, g, b) self.textColor = { r, g, b } end
    function widget:SetJustifyH(value) self.justifyH = value end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end
    function widget:EnableMouse(value) self.mouseEnabled = value end
    function widget:RegisterForClicks(...) self.clicks = { ... } end
    function widget:RegisterForDrag(...) self.drag = { ... } end
    function widget:SetHighlightTexture(value) self.highlightTexture = value end
    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end
    function widget:GetName() return self.frameName end
    -- Sliders: setting a new value fires OnValueChanged, as the client does.
    function widget:SetMinMaxValues(low, high) self.minValue, self.maxValue = low, high end
    function widget:SetValueStep(value) self.valueStep = value end
    function widget:SetObeyStepOnDrag(value) self.obeyStep = value end
    function widget:SetValue(value)
        if self.value == value then return end
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
    function widget:GetValue() return self.value end
    function widget:SetScrollChild(child) self.scrollChild = child end
    -- Tooltips.
    function widget:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
    function widget:GetOwner() return self.owner end
    function widget:AddLine(text, r, g, b)
        self.lines = self.lines or {}
        table.insert(self.lines, { text = text, color = { r, g, b } })
    end

    -- Test helper: drive this widget's OnEvent handler.
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
    env._G = env

    env.UIParent = makeWidget("Frame")
    env.GameTooltip = makeWidget("GameTooltip", env.UIParent)
    env.GameTooltip.shown = false
    -- SetText starts a tooltip afresh.
    function env.GameTooltip:SetText(value) self.text = value; self.lines = {} end
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

    -- Time: GetTime in seconds since the client started, time() the clock.
    env.__now = 100
    env.__time = 1790000000
    function env.GetTime() return env.__now end
    function env.time() return env.__time end
    env.C_Timer = { After = function(_, fn) fn() end }
    function env.InCombatLockdown() return false end

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

    -- Where the player is: UnitPosition's x, y, z and instance. The probe's
    -- spot in Westfall, on continent 0.
    env.__position = { -10603.8, 1154.0, 0, 0 }
    function env.UnitPosition()
        local p = env.__position
        if p then return p[1], p[2], p[3], p[4] end
    end
    env.__facing = 0
    function env.GetPlayerFacing() return env.__facing end
    env.__indoors = false
    function env.IsIndoors() return env.__indoors end
    env.__cvars = { rotateMinimap = "0" }
    function env.GetCVar(name) return env.__cvars[name] end

    -- Maps: each map's continent and the world positions of its top-left
    -- (x0, y0) and bottom-right (x1, y1) corners. A Westfall of round
    -- numbers; 947, the whole world, has no place.
    function env.CreateVector2D(x, y) return { x = x, y = y } end
    env.__maps = {
        [1436] = { continent = 0, x0 = -10000, y0 = 2000, x1 = -11000, y1 = 1000 },
    }
    env.__playerMap = 1436
    env.C_Map = {
        -- A map's x follows world Y and its y follows world X.
        GetWorldPosFromMapPos = function(mapID, pos)
            local m = env.__maps[mapID]
            if not m then return nil end
            return m.continent, env.CreateVector2D(m.x0 + (m.x1 - m.x0) * pos.y, m.y0 + (m.y1 - m.y0) * pos.x)
        end,
        GetBestMapForUnit = function() return env.__playerMap end,
        GetPlayerMapPosition = function(mapID)
            local m, p = env.__maps[mapID], env.__position
            if not m or not p then return nil end
            return env.CreateVector2D((p[2] - m.y0) / (m.y1 - m.y0), (p[1] - m.x0) / (m.x1 - m.x0))
        end,
    }

    -- The minimap, 140 pixels across, at zoom 0.
    env.Minimap = env.CreateFrame("Frame", "Minimap", env.UIParent)
    env.Minimap:SetSize(140, 140)
    env.__zoom = 0
    function env.Minimap:GetZoom() return env.__zoom end

    -- The world map, closed, on 1436; its canvas 1000 by 700 at scale 1.
    env.WorldMapFrame = makeWidget("Frame", env.UIParent)
    env.WorldMapFrame.shown = false
    local canvas = makeWidget("Frame", env.WorldMapFrame)
    canvas:SetSize(1000, 700)
    env.__worldMapID = 1436
    env.__canvasScale = 1
    env.__providers = {}
    function env.WorldMapFrame:GetCanvas() return canvas end
    function env.WorldMapFrame:GetMapID() return env.__worldMapID end
    function env.WorldMapFrame:GetCanvasScale() return env.__canvasScale end
    function env.WorldMapFrame:AddDataProvider(provider)
        table.insert(env.__providers, provider)
        provider:OnAdded(self)
    end
    -- Test helpers: the map turns to another map, or zooms.
    function env.__changeMap(id)
        env.__worldMapID = id
        for _, provider in ipairs(env.__providers) do provider:OnMapChanged() end
    end
    function env.__zoomMap(scale)
        env.__canvasScale = scale
        for _, provider in ipairs(env.__providers) do provider:OnCanvasScaleChanged() end
    end
    env.MapCanvasDataProviderMixin = {
        OnAdded = function(self, map) self.owningMap = map end,
        GetMap = function(self) return self.owningMap end,
        RefreshAllData = function() end,
        RemoveAllData = function() end,
        OnMapChanged = function(self) self:RefreshAllData() end,
        OnCanvasScaleChanged = function() end,
    }
    function env.CreateFromMixins(...)
        local object = {}
        for index = 1, select("#", ...) do
            for key, value in pairs((select(index, ...))) do object[key] = value end
        end
        return object
    end

    -- Loot: the GUID GetLootSourceInfo gives for the open window.
    env.__lootSource = nil
    function env.GetLootSourceInfo() return env.__lootSource end

    -- Skills: { name, isHeader, rank, isExpanded (headers only, default true) }.
    env.__skills = {
        { "Professions", true },
        { "Herbalism", false, 50 },
        { "Mining", false, 70 },
    }
    function env.GetNumSkillLines() return #env.__skills end
    function env.GetSkillLineInfo(index)
        local line = env.__skills[index]
        local expanded = line[4]
        if expanded == nil then expanded = true end
        return line[1], line[2], expanded, line[3] or 0
    end

    -- Item icons: a fake file ID per item.
    env.C_Item = { GetItemIconByID = function(id) return 1000 + id end }

    return env
end

return stub
