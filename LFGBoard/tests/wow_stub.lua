-- A minimal stand-in for the WoW API, enough to load LFGBoard outside the
-- game: frames, timers, chat, the player, talents, the group finder,
-- sounds and links. It records what was done so tests can assert on it.

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
        checked = false,
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
    -- The client raises on an event name it does not have.
    function widget:RegisterEvent(event)
        if env.__unknownEvents[event] then
            error("Attempt to register unknown event \"" .. event .. "\"", 2)
        end
        self.registeredEvents[event] = true
    end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end
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
    function widget:GetParent() return self.parent end
    function widget:GetName() return self.frameName end
    function widget:GetCenter() return 0, 0 end
    function widget:GetEffectiveScale() return 1 end
    function widget:SetFrameStrata(value) self.strata = value end
    function widget:SetFrameLevel(value) self.frameLevel = value end
    function widget:SetClampedToScreen() end
    function widget:SetMovable() end
    function widget:EnableMouse(value) self.mouseEnabled = value end
    function widget:RegisterForDrag(...) self.drag = { ... } end
    function widget:RegisterForClicks(...) self.clicks = { ... } end
    function widget:StartMoving() self.moving = true end
    function widget:StopMovingOrSizing() self.moving = false end
    function widget:SetBackdrop(value) self.backdrop = value end
    function widget:SetBackdropColor() end
    function widget:SetBackdropBorderColor() end
    function widget:SetHighlightTexture(value) self.highlightTexture = value end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text end
    function widget:SetTextColor(...) self.textColor = { ... } end
    function widget:SetJustifyH(value) self.justifyH = value end
    function widget:SetWordWrap(value) self.wordWrap = value end
    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
    function widget:SetColorTexture(...) self.color = { ... } end
    function widget:SetAlpha(value) self.alpha = value end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end
    function widget:SetEnabled(value) self.enabled = value and true or false end
    function widget:IsEnabled() return self.enabled end
    function widget:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
    function widget:AddLine(value) self.lines = self.lines or {}; table.insert(self.lines, value) end
    function widget:CreateTexture() return makeWidget(env, "Texture", self) end
    function widget:CreateFontString() return makeWidget(env, "FontString", self) end
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
    function widget:SetShown(value)
        if value then self:Show() else self:Hide() end
    end
    function widget:IsShown() return self.shown end

    -- Test helper: drive this widget's OnEvent handler.
    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then handler(self, event, ...) end
    end
    -- Test helper: a click, which a disabled button ignores. A check button
    -- flips before its script runs, as the client's does.
    function widget:Click(mouseButton)
        if not self.enabled then return end
        if self.template == "UICheckButtonTemplate" then
            self.checked = not self.checked
        end
        if self.scripts.OnClick then
            self.scripts.OnClick(self, mouseButton or "LeftButton")
        end
    end

    return widget
end

--- A fresh client. `saved` is LFGBoardDB as the client would load it.
function stub.newEnv(saved)
    local env = setmetatable({}, { __index = _G })

    env._G = env
    env.__frames = {}
    env.__printed = {}
    env.__unknownEvents = {}
    env.LFGBoardDB = saved
    env.SlashCmdList = {}
    env.UISpecialFrames = {}
    env.UIParent = makeWidget(env, "Frame")
    env.Minimap = makeWidget(env, "Frame", env.UIParent)
    env.Minimap.width = 140
    env.GameTooltip = makeWidget(env, "GameTooltip", env.UIParent)

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

    -- Time, and timers that run when a test says so.
    env.__now = 1000
    function env.GetTime() return env.__now end
    env.__timers = {}
    env.C_Timer = {
        After = function(_, fn) table.insert(env.__timers, fn) end,
    }
    function env.__runTimers()
        local pending = env.__timers
        env.__timers = {}
        for _, fn in ipairs(pending) do fn() end
    end
    function env.InCombatLockdown() return false end
    function env.GetCursorPosition() return 0, 0 end

    env.SOUNDKIT = { TELL_MESSAGE = 3081, IG_CHARACTER_INFO_TAB = 841 }
    env.__sounds = {}
    function env.PlaySound(id) table.insert(env.__sounds, id) end

    -- The player: a level 20 druid in no group.
    env.__player = { name = "Skyler", realm = "Aldira", level = 20, class = "Druid", classFile = "DRUID" }
    env.__inGroup = false
    function env.UnitName(unit)
        if unit == "player" then return env.__player.name end
    end
    function env.GetRealmName() return env.__player.realm end
    function env.UnitLevel(unit)
        if unit == "player" then return env.__player.level end
    end
    function env.UnitClass(unit)
        if unit == "player" then return env.__player.class, env.__player.classFile end
    end
    function env.IsInGroup() return env.__inGroup end

    -- Talent trees with each talent's rank. A tab's info puts an ID before
    -- the name, as newer clients do; __talentNameFirst gives the name first.
    env.__talents = {
        { name = "Balance", ranks = { 0, 0 } },
        { name = "Feral Combat", ranks = { 5, 3, 2 } },
        { name = "Restoration", ranks = { 1, 0 } },
    }
    env.__talentNameFirst = false
    function env.GetNumTalentTabs() return #env.__talents end
    function env.GetTalentTabInfo(tab)
        local tree = env.__talents[tab]
        if env.__talentNameFirst then
            return tree.name, "icon", 0, "file"
        end
        return 100 + tab, tree.name, "description", "icon", 0
    end
    function env.GetNumTalents(tab) return #env.__talents[tab].ranks end
    function env.GetTalentInfo(tab, index)
        return "Talent", "icon", 1, index, env.__talents[tab].ranks[index], 5
    end

    env.RAID_CLASS_COLORS = {
        WARRIOR = { colorStr = "ffc79c6e" }, PALADIN = { colorStr = "fff58cba" },
        HUNTER = { colorStr = "ffabd473" }, ROGUE = { colorStr = "fffff569" },
        PRIEST = { colorStr = "ffffffff" }, SHAMAN = { colorStr = "ff0070de" },
        MAGE = { colorStr = "ff69ccf0" }, WARLOCK = { colorStr = "ff9482c9" },
        DRUID = { colorStr = "ffff7d0a" },
    }
    -- What a sender's GUID says about their class.
    env.__guids = {}
    function env.GetPlayerInfoByGUID(guid)
        local class = env.__guids[guid]
        if class then return "Localized", class, "Race", "Race", 0, "Name", "" end
    end

    -- Chat: the box a whisper opens in, and links clicked.
    function env.ChatFrame_OpenChat(text) env.__openedChat = text end
    env.__itemRefs = {}
    function env.SetItemRef(link) table.insert(env.__itemRefs, link) end
    function env.hooksecurefunc(name, fn)
        local original = env[name]
        env[name] = function(...)
            local results = { original(...) }
            fn(...)
            return table.unpack(results)
        end
    end

    -- The group finder: categories, activities, and listings by result ID.
    env.__categories = { [2] = "Dungeons", [114] = "Raids", [116] = "Quests" }
    env.__activities = {
        [10] = { fullName = "The Deadmines", maxNumPlayers = 5 },
        [11] = { fullName = "Wailing Caverns", maxNumPlayers = 5 },
        [12] = { fullName = "Shadowfang Keep", maxNumPlayers = 5 },
        [20] = { fullName = "Molten Core", maxNumPlayers = 40 },
        [30] = { fullName = "Elwynn Forest Quests", maxNumPlayers = 5 },
    }
    env.__results = {}
    env.__resultOrder = {}
    env.__searches = {}
    env.C_LFGList = {
        GetAvailableCategories = function()
            local ids = {}
            for _, id in ipairs({ 2, 114, 116 }) do
                if env.__categories[id] then ids[#ids + 1] = id end
            end
            return ids
        end,
        GetLfgCategoryInfo = function(id)
            local name = env.__categories[id]
            if name then return { name = name } end
        end,
        Search = function(categoryID) table.insert(env.__searches, categoryID) end,
        GetSearchResults = function()
            local ids = {}
            for _, id in ipairs(env.__resultOrder) do
                if env.__results[id] then ids[#ids + 1] = id end
            end
            return #ids, ids
        end,
        GetSearchResultInfo = function(id)
            local listing = env.__results[id]
            if not listing then return nil end
            return {
                searchResultID = id,
                activityIDs = { listing.activityID },
                leaderName = listing.leader,
                comment = listing.comment,
                name = "",
                numMembers = #listing.members,
                isDelisted = listing.delisted == true,
            }
        end,
        GetSearchResultMemberInfo = function(id, index)
            local listing = env.__results[id]
            local member = listing and listing.members[index]
            if member then return member.role, member.class end
        end,
        GetActivityInfoTable = function(id) return env.__activities[id] end,
    }

    return env
end

--- An older group finder: categories and activities read by the older
-- calls, which give a name first rather than a table.
function stub.useOlderFinder(env)
    local finder = env.C_LFGList
    finder.GetLfgCategoryInfo = nil
    finder.GetActivityInfoTable = nil
    function finder.GetCategoryInfo(id) return env.__categories[id] end
    function finder.GetActivityInfo(id)
        local activity = env.__activities[id]
        if activity then
            return activity.fullName, "short", 2, 1, 0, 0, 0, activity.maxNumPlayers
        end
    end
end

return stub
