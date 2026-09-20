-- A minimal stand-in for the WoW API, enough to load the addon outside the
-- game. Widgets record what was done to them so tests can assert on it.
--
-- The point of interest is SetAttribute, SetPoint, SetSize, Show and Hide.
-- We can never test that Blizzard equips the right item, or actually moves a
-- frame on screen; we can test that we asked it to, and that we refused to
-- ask while a real client would have refused the ask outright.

local stub = {}

-- env is threaded through explicitly at every top-level creation site
-- (UIParent, CreateFrame, SettingsPanel, GameMenuFrame below); a child
-- widget (CreateTexture/CreateFontString further down) inherits its
-- parent's rather than needing every call site updated. refuseInCombat below
-- is the thing here that needs it, to refuse the way the real client does
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
        -- Whether the real client would refuse a secure-adjacent write on
        -- this frame in combat. Inherited from the parent at creation time,
        -- then possibly upgraded to true below by CreateFrame's own checks
        -- (a secure template, or the bar's anchor by name). The real
        -- client's IsProtected() returns (isProtected, isExplicit) for
        -- exactly this reason: protection flows down from a protected
        -- frame to everything created under it -- a secure button's own
        -- icon texture is no less untouchable in combat than the button is.
        protected = parent and parent.protected or false,
        -- An EditBox grabs focus as it comes into existence in the real
        -- client, same as ForeverPanel's stub documents; that starting state
        -- is what lets ClearFocus() fire OnEditFocusLost on the first call.
        focused = (kind == "EditBox"),
    }

    -- Shared by every secure-adjacent write below (SetAttribute already had
    -- its own copy of this check; SetPoint, SetSize, Show, Hide, SetShown
    -- and ClearAllPoints used to have none at all, or none consistently).
    -- Raises, rather than silently no-op-ing or recording a flag: the real
    -- client refuses these outright in combat, loudly enough that an addon
    -- doing one anyway finds out immediately. A stub that instead just
    -- accepted the call quietly would let exactly this class of bug back in
    -- -- a frame move or a show/hide reachable from a path the addon
    -- believed was combat-safe -- the same way a too-permissive stub
    -- already has, more than once, on this branch.
    --
    -- Gated on self.protected rather than applied to every widget: the real
    -- client only refuses these on a protected frame, not on a plain options
    -- panel, and a stub that refused universally hid the case of the whole
    -- addon logging in mid-fight, because the only way to dodge a false
    -- refusal on Settings.lua's unprotected panel was to not load it.
    local function refuseInCombat(self, name)
        if self.protected and self.__env and self.__env.__inCombat then
            error("Interface action failed because of an AddOn (" .. name .. " blocked during combat lockdown)", 3)
        end
    end

    function widget:SetPoint(...)
        refuseInCombat(self, "SetPoint")
        table.insert(self.points, { ... })
    end
    function widget:ClearAllPoints()
        refuseInCombat(self, "ClearAllPoints")
        self.points = {}
    end
    function widget:SetAllPoints() end
    function widget:GetPoint(index)
        local point = self.points[index or 1]
        if point then return table.unpack(point) end
    end

    -- Guarded like SetSize below: resizing a protected frame is refused in
    -- combat whichever call does it, and a stub that let one of the three
    -- through would hide exactly the bug the other two are here to catch.
    function widget:SetWidth(value)
        refuseInCombat(self, "SetWidth")
        self.width = value
    end
    function widget:GetWidth() return self.width end
    function widget:SetHeight(value)
        refuseInCombat(self, "SetHeight")
        self.height = value
    end
    function widget:GetHeight() return self.height end
    function widget:SetSize(w, h)
        refuseInCombat(self, "SetSize")
        self.width, self.height = w, h
    end

    -- OnShow and OnHide fire here, as the client fires them, rather than
    -- being left for a test to call by hand. A frame that cleans up after
    -- itself in OnHide -- the spell picker's click catcher, for one -- is
    -- only correct if hiding actually runs it.
    function widget:Show()
        refuseInCombat(self, "Show")
        self.shown = true
        local handler = self.scripts.OnShow
        if handler then handler(self) end
    end
    function widget:Hide()
        refuseInCombat(self, "Hide")
        self.shown = false
        local handler = self.scripts.OnHide
        if handler then handler(self) end
    end
    function widget:SetShown(value)
        refuseInCombat(self, "SetShown")
        self.shown = value and true or false
    end
    function widget:IsShown() return self.shown end

    -- Real, and read-only from addon code: protection comes from a secure
    -- template or from being a Blizzard frame, never from an addon asking
    -- for it. There is no SetProtected on a real Frame -- see CreateFrame
    -- below for how this fixture decides the flag instead.
    function widget:IsProtected() return self.protected == true end

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
    -- Recorded because which click types a secure button asks for decides
    -- whether it casts at all. The stub cannot model the client's own
    -- refusal to act on the wrong edge, so the registration is the only
    -- thing a test can hold on to. See row_spec.
    function widget:RegisterForClicks(...) self.clickRegistrations = { ... } end
    -- Recorded, not ignored: row_spec asserts a button never calls this,
    -- since RegisterForDrag is for STARTING a drag and this addon only ever
    -- receives one (see Row.Create's OnReceiveDrag).
    function widget:RegisterForDrag(...) self.dragRegistered = { ... } end
    -- Recorded, not ignored: a frame that takes no mouse takes no click and
    -- shows no mouseover highlight, and nothing else about it looks wrong.
    function widget:EnableMouse(value) self.mouseEnabled = value ~= false end
    function widget:EnableMouseWheel() end
    -- Driven by a test: env.__mouseOver = someFrame. The real answer depends
    -- on where the cursor is, which a test has no way to arrange.
    function widget:IsMouseOver() return self.__env.__mouseOver == self end
    -- Geometry the stub does not otherwise model. A test that needs a frame
    -- to have a top sets one: row.top = 400.
    function widget:GetTop() return self.top end
    function widget:GetEffectiveScale() return self.__env.__uiScale or 1 end
    function widget:SetFrameLevel(value) self.frameLevel = value end
    function widget:GetFrameLevel() return self.frameLevel or 1 end
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

    -- Secure attributes are what the client acts on, so the tests assert on
    -- these rather than on anything happening. See refuseInCombat above for
    -- why this raises instead of no-op-ing.
    function widget:SetAttribute(name, value)
        refuseInCombat(self, "SetAttribute")
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
    function widget:SetStatusBarTexture(value) self.statusBarTexture = value end
    function widget:GetStatusBarTexture() return self.statusBarTexture end

    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end

    function widget:SetText(value)
        self.text = value or ""
        local handler = self.scripts.OnTextChanged
        if handler then handler(self) end
    end
    function widget:GetText() return self.text end
    function widget:GetName() return self.frameName end
    function widget:GetObjectType() return self.kind end
    function widget:SetTextColor(r, g, b) self.textColor = { r, g, b } end
    function widget:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
    function widget:SetTexCoord(...) self.texCoord = { ... } end
    function widget:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a } end

    -- Recorded as plain fields rather than behind a getter: the real
    -- GetHighlightTexture hands back a Texture object, not the path, so a
    -- stub accessor returning the path would be teaching a test something
    -- the client does not do.
    function widget:SetHighlightTexture(value, blend)
        self.highlightTexture = value
        self.highlightBlend = blend
    end

    -- The client animates the sweep itself; all an addon ever does is hand
    -- it a start and a duration, so that pair is the whole observable state.
    function widget:SetCooldown(start, duration)
        self.cooldownStart = start
        self.cooldownDuration = duration
    end
    function widget:GetCooldownTimes()
        return self.cooldownStart, self.cooldownDuration
    end
    function widget:SetHideCountdownNumbers() end

    -- The draw layer is recorded because it is not merely cosmetic: the
    -- client shows and hides anything in the HIGHLIGHT layer on mouseover by
    -- itself, so the layer is the whole of how a hover effect works.
    function widget:CreateTexture(name, layer)
        local texture = makeWidget("Texture", self)
        texture.drawLayer = layer
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

    -- Where the cursor is, in raw pixels, which is what the real call
    -- answers in. A test drags by moving this between handler calls.
    env.__cursorY = 0
    function env.GetCursorPosition() return 0, env.__cursorY end

    env.SlashCmdList = {}
    env.OKAY = "Okay"

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do
            pieces[index] = tostring((select(index, ...)))
        end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    --- Test helper: templates this client does not have. The real client
    -- raises on an unknown template rather than returning nil, and this
    -- client family has already dropped GetSpellInfo and GetSpellBookItemName
    -- out from under the addon, so a template going missing is a case the
    -- addon has to survive -- which means the stub has to be able to stage it.
    env.__missingTemplates = {}

    function env.CreateFrame(kind, name, parent, template)
        if template and env.__missingTemplates[template] then
            error(string.format("Couldn't find inherited node '%s'", template), 2)
        end

        local frame = makeWidget(kind or "Frame", parent, template, env)
        frame.frameName = name
        -- A secure template is what makes the real client refuse a write on
        -- this frame in combat.
        if template and template:find("Secure") then
            frame.protected = true
        end
        -- TrinketBar's anchor carries no secure template of its own, but
        -- every button in the pool hangs off it -- moving, showing or
        -- hiding it moves, shows or hides them too. The real client gives
        -- addon code no way to make a plain frame protected (there is no
        -- SetProtected setter, only the read-only IsProtected), so the
        -- fixture has to know this one frame is combat-sensitive by its
        -- name, the same seam Bar.lua already uses to find it back
        -- (CreateFrame("Frame", "TrinketBarAnchor", ...)).
        if name == "TrinketBarAnchor" then
            frame.protected = true
        end
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

    -- Class colors, keyed the way RAID_CLASS_COLORS really is. Kept even
    -- though nothing here reads a unit's class yet, on the chance a later
    -- trinket-bar feature colors something by class.
    env.RAID_CLASS_COLORS = {
        DRUID   = { r = 1.00, g = 0.49, b = 0.04 },
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
        MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
        PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
    }

    -- Clock -------------------------------------------------------------
    -- Fixed rather than real, so a test can say "this happened five seconds
    -- ago" and mean it -- useful for anything timed against a cooldown.
    env.__now = 1000
    function env.GetTime() return env.__now end

    -- What is in the trinket slots: env.__worn[13] = "item link".
    env.__worn = {}

    -- When something comes off cooldown, keyed the way each API is asked:
    --   env.__cooldowns["worn:13"]  = { start = 100, duration = 120 }
    --   env.__cooldowns["bag:0:1"]  = { start = 100, duration = 120 }
    env.__cooldowns = {}

    env.INVSLOT_TRINKET1 = 13
    env.INVSLOT_TRINKET2 = 14

    --- Test helper: put a trinket in a worn slot and register what it is.
    function env.__wear(slot, name)
        local link = string.format("|Hitem:%s|h[%s]|h", name, name)
        env.__worn[slot] = link
        env.__items[link] = {
            name = name,
            equipLoc = "INVTYPE_TRINKET",
            texture = 133308,
        }
        return link
    end

    function env.GetInventoryItemLink(unit, slot)
        return unit == "player" and env.__worn[slot] or nil
    end

    function env.GetInventoryItemCooldown(unit, slot)
        local entry = env.__cooldowns["worn:" .. tostring(slot)]
        if not entry then return 0, 0, 1 end
        return entry.start, entry.duration, 1
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

    -- What is in the bags: env.__bags[bag][slot] = "item link". Bag 0 is the
    -- backpack, 1-4 the worn bags, which is the range the real API uses.
    env.__bags = { [0] = {}, {}, {}, {}, {} }

    -- What the client knows about an item, by link:
    --   env.__items["|cff...|Hitem:1|h[Card]|h|r"] =
    --       { name = "Card", equipLoc = "INVTYPE_TRINKET", texture = 133308 }
    env.__items = {}

    env.NUM_BAG_SLOTS = 4

    --- Test helper: put a trinket in a bag slot and register what it is.
    function env.__carry(bag, slot, name, equipLoc)
        local link = string.format("|Hitem:%s|h[%s]|h", name, name)
        env.__bags[bag] = env.__bags[bag] or {}
        env.__bags[bag][slot] = link
        env.__items[link] = {
            name = name,
            equipLoc = equipLoc or "INVTYPE_TRINKET",
            texture = 133308,
        }
        return link
    end

    -- Namespaced by default, which is the shape this client family has been
    -- moving towards. A test covering an older client deletes these and adds
    -- the globals itself, from the same __bags and __items tables.
    env.C_Container = {
        GetContainerNumSlots = function(bag)
            local contents = env.__bags[bag]
            if not contents then return 0 end
            local highest = 0
            for slot in pairs(contents) do
                if slot > highest then highest = slot end
            end
            return highest
        end,
        GetContainerItemLink = function(bag, slot)
            return env.__bags[bag] and env.__bags[bag][slot] or nil
        end,
        GetContainerItemCooldown = function(bag, slot)
            local entry = env.__cooldowns[string.format("bag:%d:%d", bag, slot)]
            if not entry then return 0, 0, 1 end
            return entry.start, entry.duration, 1
        end,
    }

    env.C_Item = {
        GetItemInfo = function(link)
            local item = env.__items[link]
            if not item then return nil end
            -- name, link, quality, level, minLevel, type, subType,
            -- stackCount, equipLoc, texture -- the real call's shape, which
            -- is what Items.lua has to read positionally.
            return item.name, link, 1, 1, 1, "Armor", "Miscellaneous", 1,
                item.equipLoc, item.texture
        end,
    }

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
