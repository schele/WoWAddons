-- A stand-in for the WoW API, enough to load the addon outside the game.
-- Widgets record what was done to them so tests can assert on it.

local stub = {}

local function makeWidget(kind, parent, template, env)
    local widget = {
        kind = kind, parent = parent, template = template,
        points = {}, scripts = {}, registeredEvents = {}, children = {},
        width = 0, height = 0, shown = true, text = "", alpha = 1,
        mouseEnabled = true, highlightLocked = false,
    }
    if parent and parent.children then table.insert(parent.children, widget) end

    function widget:SetPoint(...) table.insert(self.points, { ... }) end
    function widget:ClearAllPoints() self.points = {} end
    function widget:SetAllPoints() end
    function widget:GetPoint(index)
        local point = self.points[index or 1]
        if point then return table.unpack(point) end
    end
    function widget:SetSize(w, h) self.width, self.height = w, h end
    function widget:SetWidth(w) self.width = w end
    function widget:SetHeight(h) self.height = h end
    function widget:GetWidth() return self.width end
    function widget:GetHeight() return self.height end

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
    function widget:Fire(event, ...)
        if self.scripts.OnEvent then self.scripts.OnEvent(self, event, ...) end
    end

    function widget:EnableMouse(value) self.mouseEnabled = value and true or false end
    function widget:EnableMouseWheel() end
    function widget:RegisterForClicks(...) self.clicks = { ... } end
    function widget:RegisterForDrag(...) self.drag = { ... } end
    function widget:SetMovable() end
    function widget:SetClampedToScreen() end
    function widget:StartMoving() self.moving = true end
    function widget:StopMovingOrSizing() self.moving = false end
    function widget:SetFrameStrata(value) self.strata = value end
    function widget:SetFrameLevel(value) self.frameLevel = value end
    function widget:GetFrameLevel() return self.frameLevel or 1 end
    function widget:SetAlpha(value) self.alpha = value end
    function widget:LockHighlight() self.highlightLocked = true end
    function widget:UnlockHighlight() self.highlightLocked = false end
    function widget:GetName() return self.frameName end
    function widget:GetParent() return self.parent end
    function widget:GetCenter() return self.centerX or 0, self.centerY or 0 end
    function widget:GetEffectiveScale() return 1 end

    function widget:SetText(value)
        self.text = value or ""
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, true) end
    end
    function widget:GetText() return self.text end
    function widget:SetTextColor(r, g, b) self.textColor = { r, g, b } end
    function widget:SetJustifyH(value) self.justifyH = value end
    function widget:SetAutoFocus() end
    function widget:ClearFocus() end
    function widget:SetMaxLetters() end

    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
    function widget:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
    function widget:SetTexCoord() end
    function widget:SetVertexColor() end
    function widget:SetBackdrop(value) self.backdrop = value end
    function widget:SetBackdropColor() end
    function widget:SetBackdropBorderColor() end
    function widget:SetHighlightTexture(value) self.highlightTexture = value end

    function widget:CreateTexture(_, layer)
        local texture = makeWidget("Texture", self, nil, env)
        texture.drawLayer = layer
        return texture
    end
    function widget:CreateFontString(_, layer, font)
        local fontString = makeWidget("FontString", self, nil, env)
        fontString.drawLayer, fontString.font = layer, font
        return fontString
    end

    return widget
end

stub.makeWidget = makeWidget

function stub.newEnv()
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.__frames = {}
    env.__printed = {}
    env.__timers = {}
    env.SlashCmdList = {}
    env.UISpecialFrames = {}

    env.UIParent = makeWidget("Frame", nil, nil, env)
    env.Minimap = makeWidget("Frame", env.UIParent, nil, env)
    env.Minimap.width, env.Minimap.height = 140, 140

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do pieces[index] = tostring((select(index, ...))) end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    -- The real client raises on a template it does not have. Tests stage a
    -- missing one by listing it here.
    env.__missingTemplates = {}
    function env.CreateFrame(kind, name, parent, template)
        if template and env.__missingTemplates[template] then
            error(string.format("Couldn't find inherited node '%s'", template), 2)
        end
        local frame = makeWidget(kind or "Frame", parent, template, env)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        return frame
    end

    -- Timers run when a test says so, like the client's next frame.
    env.C_Timer = {
        After = function(_, fn) table.insert(env.__timers, fn) end,
    }
    function env.__runTimers()
        local timers = env.__timers
        env.__timers = {}
        for _, fn in ipairs(timers) do fn() end
    end

    -- Items: only what a test has put in env.__items is "cached". Anything
    -- else comes back nil, as an item the client has not seen does.
    env.__items = {}
    env.__requested = {}
    env.C_Item = {
        GetItemInfo = function(id)
            local item = env.__items[id]
            if not item then return nil end
            return item.name, "|Hitem:" .. id .. "|h[" .. item.name .. "]|h", item.quality or 1,
                60, 58, item.type or "Armor", item.subType or "Cloth", 1, item.equipLoc or "", item.icon or 134400
        end,
        GetItemIconByID = function(id) return 100000 + id end,
        RequestLoadItemDataByID = function(id) env.__requested[id] = true end,
    }
    env.INVTYPE_2HWEAPON = "Two-Hand"
    env.INVTYPE_CHEST = "Chest"

    env.GameTooltip = makeWidget("GameTooltip", env.UIParent, nil, env)
    env.GameTooltip.shown = false
    function env.GameTooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
    function env.GameTooltip:SetItemByID(id) self.itemID = id end
    function env.GameTooltip:SetText(text) self.text = text end
    function env.GameTooltip:AddLine(text) self.lines = self.lines or {}; table.insert(self.lines, text) end

    env.__modifiedClicks = {}
    function env.HandleModifiedItemClick(link)
        table.insert(env.__modifiedClicks, link)
        return true
    end

    env.__cursorX, env.__cursorY = 0, 0
    function env.GetCursorPosition() return env.__cursorX, env.__cursorY end

    return env
end

return stub
