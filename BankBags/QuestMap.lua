local addonName, ns = ...

-- Quest items in the bank, in the world map's quest log: the same note the
-- tracker gets, "0/3 Boar Intestines (12 in bank)", on the log's objective
-- lines. Tracker.lua decides the note; this finds the lines.
--
-- Blizzard draws the whole log again whenever it changes
-- (QuestLogQuests_Update): every objective line goes back to one pool, and a
-- line comes out for each objective not yet finished, with its quest's ID
-- and the objective's text. Finished objectives get no line, and the pool
-- hands lines out in no set order, so a line is matched to its objective by
-- its text, not by its place. As on the tracker, this only changes the text
-- of the line's FontString, after Blizzard has drawn it, and only when the
-- note fits without making the line taller: Blizzard set the line's height
-- from its text and does not look again.

local Tracker = ns.Tracker
local QuestMap = {}
ns.QuestMap = QuestMap

-- How tall the log lays out a line: from its text's height, as Blizzard
-- measures it there.
local function stringHeightOf(fontString, text)
    fontString:SetText(text)
    return fontString:GetStringHeight()
end

-- Every line written on, for redrawing when the bank or bags change:
-- [line] = { questID, index, text }, the text being what was left on it.
-- Weak, so lines the pool lets go of can go.
local written = setmetatable({}, { __mode = "k" })

local function render(line, at, banks)
    local logIndex = C_QuestLog.GetLogIndexForQuestID(at.questID)
    local base = logIndex and GetQuestLogLeaderBoard(at.index, logIndex)
    local objective = C_QuestLog.GetQuestObjectives(at.questID)[at.index]
    if base and objective then
        at.text = Tracker.Write(line.Text, base, objective, banks, stringHeightOf)
    end
end

-- Which of the quest's objectives this text is, as Blizzard wrote it.
local function objectiveIndex(logIndex, text)
    for index = 1, GetNumQuestLeaderBoards(logIndex) do
        if GetQuestLogLeaderBoard(index, logIndex) == text then
            return index
        end
    end
end

local function afterLogUpdate()
    local pool = QuestScrollFrame and QuestScrollFrame.objectiveFramePool
    if not pool then
        return
    end
    local banks
    for line in pool:EnumerateActive() do
        local questID = line.questID
        local logIndex = questID and C_QuestLog.GetLogIndexForQuestID(questID)
        local text = logIndex and line.Text and line.Text:GetText()
        local index = text and objectiveIndex(logIndex, text)
        if index then
            banks = banks or Tracker.Banks()
            local at = { questID = questID, index = index, text = text }
            written[line] = at
            pcall(render, line, at, banks)
        end
    end
end

--- Redraw the notes in the log. Only lines still out and still showing
-- what was last written on them: a line the log put away keeps its old
-- text until Blizzard hands it out again and writes it afresh.
function QuestMap.Redraw()
    if not next(written) then
        return
    end
    local banks = Tracker.Banks()
    for line, at in pairs(written) do
        if line:IsShown() and line.questID == at.questID and line.Text:GetText() == at.text then
            pcall(render, line, at, banks)
        else
            written[line] = nil
        end
    end
end

local hooked = false
local function hookLog()
    if not hooked and type(QuestLogQuests_Update) == "function" then
        hooksecurefunc("QuestLogQuests_Update", afterLogUpdate)
        hooked = true
    end
end

-- The log is part of the game's own panels, there before any addon, but
-- the map can come in later: look again as each addon loads until it is.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self)
    hookLog()
    if hooked then
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

hookLog()
