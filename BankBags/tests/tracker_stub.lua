-- The quest log, bag counts and objective tracker, for Tracker.lua's tests.
-- Installed into an environment from wow_stub before the addon loads, since
-- the tracker exists before any addon does.
--
-- The tracker follows Blizzard's own code from Gethe/wow-ui-source, branch
-- "forever" (1.60.1), Blizzard_ObjectiveTracker: a module's
-- DoQuestObjectives asks GetQuestLogLeaderBoard for each objective's text and
-- hands it to block:AddObjective, which pulls a line from a pool shared by
-- the module's blocks and sets the line's Text. Lines are recycled between
-- quests, which is why the tests move lines from one quest to another.

local M = {}

local LINE_HEIGHT = 12

-- Colour codes take no room on screen.
local function visible(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function M.install(env)
    -- Quests in the log: [questID] = { logIndex, objectives = { ... } }.
    env.__quests = {}
    -- How many of each item, by name, are in the bags.
    env.__bagCounts = {}
    -- How many characters fit on one tracker line before it wraps.
    env.__lineWidth = 40

    env.hooksecurefunc = function(target, key, hook)
        if type(target) == "string" then
            target, key, hook = env, target, key
        end
        local original = target[key]
        target[key] = function(...)
            local results = table.pack(original(...))
            hook(...)
            return table.unpack(results, 1, results.n)
        end
    end

    -- Bags only: away from a banker an item count that asks for the bank
    -- gets the bags alone, so Tracker.lua must not ask.
    env.C_Item.GetItemCount = function(itemInfo)
        return env.__bagCounts[itemInfo] or 0
    end

    env.C_QuestLog = {
        GetLogIndexForQuestID = function(questID)
            local quest = env.__quests[questID]
            return quest and quest.logIndex
        end,
        GetQuestObjectives = function(questID)
            local quest = env.__quests[questID]
            local copies = {}
            for index, objective in ipairs(quest and quest.objectives or {}) do
                copies[index] = {
                    text = objective.text,
                    type = objective.type,
                    finished = objective.finished,
                    numFulfilled = objective.numFulfilled,
                    numRequired = objective.numRequired,
                }
            end
            return copies
        end,
    }

    local function questAt(logIndex)
        for questID, quest in pairs(env.__quests) do
            if quest.logIndex == logIndex then
                return quest, questID
            end
        end
    end

    -- The log, walked by index: a quest wherever one sits, and a zone header
    -- in every gap, as the log mixes the two.
    env.C_QuestLog.GetNumQuestLogEntries = function()
        local last, count = 0, 0
        for _, quest in pairs(env.__quests) do
            last = math.max(last, quest.logIndex)
            count = count + 1
        end
        return last, count
    end
    env.C_QuestLog.GetInfo = function(logIndex)
        local quest, questID = questAt(logIndex)
        if quest then
            return { title = quest.title, questID = questID, questLogIndex = logIndex, isHeader = false }
        end
        return { title = "Loch Modan", questID = 0, questLogIndex = logIndex, isHeader = true }
    end

    -- Item tooltips: post-calls registered through TooltipDataProcessor, and
    -- the tooltips that record what was added to them.
    env.Enum = env.Enum or {}
    env.Enum.TooltipDataType = { Item = 0, Spell = 1 }
    env.__tooltipPostCalls = {}
    env.TooltipDataProcessor = {
        AllTypes = "ALL",
        AddTooltipPostCall = function(tooltipType, func)
            env.__tooltipPostCalls[tooltipType] = env.__tooltipPostCalls[tooltipType] or {}
            table.insert(env.__tooltipPostCalls[tooltipType], func)
        end,
    }
    local function recordLines(tooltip)
        tooltip.doubleLines = {}
        function tooltip:AddDoubleLine(left, right) table.insert(self.doubleLines, { left, right }) end
        tooltip.Show = tooltip.Show or function(self) self.shown = true end
        return tooltip
    end
    recordLines(env.GameTooltip)
    env.ItemRefTooltip = recordLines({})
    env.ShoppingTooltip1 = recordLines({})

    env.GetNumQuestLeaderBoards = function(logIndex)
        local quest = questAt(logIndex)
        return quest and #quest.objectives or 0
    end

    env.GetQuestLogLeaderBoard = function(index, logIndex)
        local quest = questAt(logIndex)
        local objective = quest and quest.objectives[index]
        if objective then
            return objective.text, objective.type, objective.finished
        end
    end

    -- A FontString that wraps at so many characters (__lineWidth unless told
    -- which), so its height says how many lines its text takes, the way
    -- GetHeight and GetStringHeight do in the client.
    local function makeFontString(widthKey)
        local fs = { text = "", explicitHeight = nil }
        function fs:SetText(text) self.text = text or "" end
        function fs:GetText() return self.text end
        function fs:SetHeight(height) self.explicitHeight = height end
        function fs:GetStringHeight()
            local length = #visible(self.text)
            return LINE_HEIGHT * math.max(1, math.ceil(length / env[widthKey or "__lineWidth"]))
        end
        function fs:GetHeight()
            if self.explicitHeight and self.explicitHeight > 0 then
                return self.explicitHeight
            end
            return self:GetStringHeight()
        end
        return fs
    end

    local function makeModule(name)
        local module = { blocks = {}, pool = {} }

        local function getLine()
            local line = table.remove(module.pool)
            if not line then
                line = { shown = true, Text = makeFontString() }
                function line:Show() self.shown = true end
                function line:Hide() self.shown = false end
            end
            return line
        end

        local function makeBlock(questID)
            local block = { id = questID, usedLines = {} }

            function block:GetExistingLine(objectiveKey)
                return self.usedLines[objectiveKey]
            end

            function block:AddObjective(objectiveKey, text)
                local line = self.usedLines[objectiveKey] or getLine()
                self.usedLines[objectiveKey] = line
                line.Text:SetHeight(0)
                line.Text:SetText(text)
                line:Show()
                return line
            end

            -- Blizzard's block:Free(): its lines go back to the module's pool.
            function block:Free()
                for key, line in pairs(self.usedLines) do
                    line:Hide()
                    table.insert(module.pool, line)
                    self.usedLines[key] = nil
                end
                module.blocks[self.id] = nil
            end

            return block
        end

        -- QuestObjectiveTrackerMixin:DoQuestObjectives, trimmed to the lines.
        function module:DoQuestObjectives(block)
            local logIndex = env.C_QuestLog.GetLogIndexForQuestID(block.id)
            for index = 1, env.GetNumQuestLeaderBoards(logIndex) do
                local text = env.GetQuestLogLeaderBoard(index, logIndex, true)
                if text then
                    block:AddObjective(index, text)
                end
            end
        end

        -- QuestObjectiveTrackerMixin:UpdateSingle, as far as it matters here.
        function module:UpdateQuest(questID)
            local block = self.blocks[questID]
            if not block then
                block = makeBlock(questID)
                self.blocks[questID] = block
            end
            self:DoQuestObjectives(block)
            return block
        end

        env[name] = module
        return module
    end

    makeModule("QuestObjectiveTracker")
    makeModule("CampaignQuestObjectiveTracker")

    M.installQuestMap(env, makeFontString)
end

-- The world map's quest log, from Blizzard_UIPanels_Game/Mainline/
-- QuestMapFrame.lua in the same source: QuestLogQuests_Update hands every
-- objective line back to one pool, then draws the log again. A quest that
-- is not complete gets a line for each objective not yet finished, with the
-- line's questID set, its Text from GetQuestLogLeaderBoard, and its height
-- taken from the text's. The pool hands its lines out in no set order, so
-- this one lists them backwards: a line's place says nothing about which
-- objective it shows.
function M.installQuestMap(env, makeFontString)
    -- How many characters fit on one line of the log before it wraps.
    env.__mapLineWidth = 40
    -- Quests the log leaves out, as a search box would: [questID] = true.
    env.__mapHidden = {}

    local pool = { active = {}, free = {} }
    env.__mapPool = pool

    function pool:Acquire()
        local line = table.remove(self.free)
        if not line then
            line = { shown = false, Text = makeFontString("__mapLineWidth") }
            function line:Show() self.shown = true end
            function line:Hide() self.shown = false end
            function line:IsShown() return self.shown end
            function line:SetHeight(height) self.height = height end
        end
        table.insert(self.active, line)
        return line
    end

    -- Blizzard's frame pool hides a line as it takes it back.
    function pool:ReleaseAll()
        for _, line in ipairs(self.active) do
            line:Hide()
            table.insert(self.free, line)
        end
        self.active = {}
    end

    function pool:EnumerateActive()
        local index = #self.active + 1
        return function()
            index = index - 1
            local line = self.active[index]
            if line then
                return line, true
            end
        end
    end

    env.QuestScrollFrame = { objectiveFramePool = pool }

    env.QuestLogQuests_Update = function()
        pool:ReleaseAll()
        local last = env.C_QuestLog.GetNumQuestLogEntries()
        for logIndex = 1, last do
            local info = env.C_QuestLog.GetInfo(logIndex)
            if not info.isHeader and not env.__mapHidden[info.questID] then
                local lines, finishedAll = {}, true
                for index = 1, env.GetNumQuestLeaderBoards(logIndex) do
                    local text, _, finished = env.GetQuestLogLeaderBoard(index, logIndex)
                    if text and not finished then
                        table.insert(lines, text)
                        finishedAll = false
                    end
                end
                -- A complete quest shows its turn-in text instead.
                if not finishedAll then
                    for _, text in ipairs(lines) do
                        local line = pool:Acquire()
                        line.questID = info.questID
                        line:Show()
                        line.Text:SetText(text)
                        line:SetHeight(line.Text:GetStringHeight())
                    end
                end
            end
        end
    end
end

return M
