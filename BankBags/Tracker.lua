local addonName, ns = ...

-- Quest items in the bank, on the objective tracker, and listed in chat at a
-- banker. Forever's objective
-- count is no guide to the bank: it can show "14/14 Golem Isospring" with 7
-- of them banked, or "0/3 Boar Intestines" with 12 banked. Whenever the bags
-- hold too few for an item objective, its line gets the bank's share, from
-- the copy BankBags saved: "0/3 Boar Intestines (12 in bank)". Not from an
-- item count that includes the bank: away from a banker the client has no
-- bank to count, and that count is the bags alone.
--
-- The tracker holds quest item buttons that call protected functions, so
-- this never writes into Blizzard's tables or calls the tracker's methods
-- that change state. It post-hooks DoQuestObjectives and only changes the
-- text of the line's FontString, and only when the note fits without making
-- the line taller than Blizzard laid it out.

local Tracker = {}
ns.Tracker = Tracker

ns.AddDefaults({
    questNotes = true, -- the note on the tracker
    questAlts = true, -- ...with other characters' banks on this realm
    questWarn = true, -- ...in red on a ticked objective the bags fall short of
    bankList = true, -- at a banker, list what to take out
})

local ORANGE = "|cffffa040"
local RED = "|cffff4040"

--- Flip one of BankBags' on/off options, as the settings page does, and
-- redraw the notes it may change.
function ns.SetOption(key, value)
    ns.db[key] = value and true or false
    Tracker.Redraw()
end

--- The item an objective is about, from its text: "0/3 Boar Intestines" or
-- "Boar Intestines: 0/3".
function Tracker.ItemName(text)
    return text:match("^%d+/%d+%s+(.+)$") or text:match("^(.-):%s*%d+/%d+$")
end

local function bagCount(name)
    return (C_Item and C_Item.GetItemCount or GetItemCount)(name) or 0
end

--- The saved banks a pass of notes reads: this character's counts by item
-- name, and each alt's on this realm when that option is on.
function Tracker.Banks()
    local banks = { own = ns.Bank.Counts(ns.Bank.CharacterKey()).byName, alts = {} }
    if ns.db and ns.db.questAlts then
        for _, other in ipairs(ns.Bank.Others()) do
            table.insert(banks.alts, { name = other.name, counts = ns.Bank.Counts(other.key).byName })
        end
    end
    return banks
end

--- The note for an objective, or nil when it needs none: its parts, most
-- useful first, each { full, short }, and the colour to write it in.
-- Nothing is said while the bags hold enough. Otherwise: this character's
-- bank, then the alts', most first, but only while the bags and own bank
-- together fall short. A ticked objective the bags fall short of is red, and
-- with nothing banked anywhere says how many are carried.
function Tracker.Note(objective, banks)
    if objective.type ~= "item" then
        return nil
    end
    local name = Tracker.ItemName(objective.text or "")
    if not name then
        return nil
    end
    local need = objective.numRequired or 0
    local bags = bagCount(name)
    if bags >= need then
        return nil
    end

    local parts = {}
    local own = banks.own[name] or 0
    if own > 0 then
        table.insert(parts, { own .. " in bank", own .. " bank" })
    end
    if bags + own < need then
        local alts = {}
        for _, alt in ipairs(banks.alts) do
            local n = alt.counts[name] or 0
            if n > 0 then
                table.insert(alts, { name = alt.name, n = n })
            end
        end
        table.sort(alts, function(a, b)
            if a.n ~= b.n then
                return a.n > b.n
            end
            return a.name < b.name
        end)
        for _, alt in ipairs(alts) do
            table.insert(parts, { alt.n .. " on " .. alt.name, alt.n .. " " .. alt.name })
        end
    end

    local ticked = objective.finished or (objective.numFulfilled or 0) >= need
    local warn = ns.db and ns.db.questWarn and ticked
    if #parts == 0 then
        if not warn then
            return nil
        end
        parts = { { bags .. " carried", bags .. " carried" } }
    end
    return parts, warn and RED or ORANGE
end

-- Every way to write a note, longest first: all its parts in full, then
-- short, then the same again without the last part, and so on.
local function wordings(parts)
    local list = {}
    for count = #parts, 1, -1 do
        for form = 1, 2 do
            local words = {}
            for i = 1, count do
                words[i] = parts[i][form]
            end
            table.insert(list, "(" .. table.concat(words, ", ") .. ")")
        end
    end
    return list
end

local function heightOf(fontString, text)
    fontString:SetHeight(0) -- as Blizzard does, or GetHeight can be stale
    fontString:SetText(text)
    return fontString:GetHeight()
end

-- The text Blizzard gave the line, plus the note when it fits.
local function render(line, questID, index, banks)
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    if not logIndex then
        return
    end
    local base = GetQuestLogLeaderBoard(index, logIndex, true)
    local objective = C_QuestLog.GetQuestObjectives(questID)[index]
    if not (base and objective) then
        return
    end

    local fontString = line.Text
    local height = heightOf(fontString, base)
    if not (ns.db and ns.db.questNotes) then
        return
    end
    local parts, colour = Tracker.Note(objective, banks)
    if not parts then
        return
    end
    for _, note in ipairs(wordings(parts)) do
        if heightOf(fontString, base .. " " .. colour .. note .. "|r") <= height + 0.5 then
            return
        end
    end
    heightOf(fontString, base)
end

-- Every line written on, for redrawing when the bank or bags change:
-- [line] = { block, questID, index }. Weak, so freed lines can go.
local written = setmetatable({}, { __mode = "k" })

local function afterObjectives(_, block)
    local questID = block.id
    local logIndex = questID and C_QuestLog.GetLogIndexForQuestID(questID)
    if not logIndex then
        return
    end
    local banks = Tracker.Banks()
    for index = 1, GetNumQuestLeaderBoards(logIndex) do
        local line = block:GetExistingLine(index)
        if line and line.Text then
            written[line] = { block = block, questID = questID, index = index }
            pcall(render, line, questID, index, banks)
        end
    end
end

--- Redraw the notes: the bank was saved or forgotten, the bags changed, or
-- the setting was flipped. The tracker's count may not have changed, so it
-- will not redraw by itself. Only lines that still show the objective they
-- showed when last written on are touched.
function Tracker.Redraw()
    if not next(written) then
        return
    end
    local banks = Tracker.Banks()
    for line, at in pairs(written) do
        if at.block.id == at.questID and at.block:GetExistingLine(at.index) == line then
            pcall(render, line, at.questID, at.index, banks)
        else
            written[line] = nil
        end
    end
end

--- At a banker, as it opens: a line in chat for each quest item to take out,
-- from the bank just saved. Never more than the bank holds, nor than the
-- bags fall short by.
function Tracker.ListForBank()
    if not (ns.db and ns.db.bankList and C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then
        return
    end
    local banked = ns.Bank.Counts(ns.Bank.CharacterKey()).byName
    for logIndex = 1, (C_QuestLog.GetNumQuestLogEntries()) do
        local info = C_QuestLog.GetInfo(logIndex)
        if info and not info.isHeader and info.questID then
            for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                local name = objective.type == "item" and Tracker.ItemName(objective.text or "")
                if name then
                    local inBank = banked[name] or 0
                    local take = math.min(inBank, (objective.numRequired or 0) - bagCount(name))
                    if take > 0 then
                        ns.Print(string.format("Take out %d %s for %s (%d in the bank).",
                            take, name, info.title, inBank))
                    end
                end
            end
        end
    end
end

local hooked = {}
local function hookTrackers()
    for _, name in ipairs({ "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }) do
        local module = _G[name]
        if module and module.DoQuestObjectives and not hooked[name] then
            hooksecurefunc(module, "DoQuestObjectives", afterObjectives)
            hooked[name] = true
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:SetScript("OnEvent", function(_, event, loaded)
    if event == "ADDON_LOADED" then
        if loaded == "Blizzard_ObjectiveTracker" then
            hookTrackers()
        end
    else
        Tracker.Redraw()
    end
end)

hookTrackers()
