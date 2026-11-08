-- Shared setup for the quest specs: a logged-in client with the quest log,
-- tracker and tooltips in place, and ways to stock bags, bank and saved banks.

local helpers = require("helpers")
local trackerStub = require("tracker_stub")

local Q = {}

--- A stack as a bank slot saves it. Every item gets its own id from its name
-- unless one is given.
local ids = {}
local nextID = 1000
function Q.itemID(name)
    if not ids[name] then
        ids[name] = nextID
        nextID = nextID + 1
    end
    return ids[name]
end

function Q.stack(name, count)
    return {
        link = "|cffffffff|Hitem:" .. Q.itemID(name) .. "::::::::60:::::|h[" .. name .. "]|h|r",
        count = count, icon = 1, quality = 1,
    }
end

--- Logged in as Carl on Stormwind, with the quest log, tracker and tooltip
-- hooks in place before BankBags loads, as they are in the game.
function Q.client(setup)
    return helpers.loggedIn(function(env, ns)
        trackerStub.install(env)
        if setup then setup(env, ns) end
    end)
end

--- Put a quest in the log: one objective per entry, each
-- { text, type, numFulfilled, numRequired }.
local nextLogIndex = 1
function Q.quest(env, questID, objectives, title)
    local list = {}
    for index, o in ipairs(objectives) do
        list[index] = { text = o[1], type = o[2], numFulfilled = o[3], numRequired = o[4], finished = o[3] >= o[4] }
    end
    env.__quests[questID] = { logIndex = nextLogIndex, title = title or ("Quest " .. questID), objectives = list }
    nextLogIndex = nextLogIndex + 1
end

function Q.bags(env, name, count)
    env.__bagCounts[name] = count
end

--- The bank as the client reads it at a banker: container id -> slots.
function Q.bank(env, containers)
    helpers.bank(env, containers)
end

function Q.banked(env, name, count)
    Q.bank(env, { [-1] = { Q.stack(name, count) } })
end

function Q.openBank(env) helpers.fire(env, "BANKFRAME_OPENED") end
function Q.closeBank(env) helpers.fire(env, "BANKFRAME_CLOSED") end

--- Away from a banker the bank reads as empty.
function Q.walkAway(env)
    Q.closeBank(env)
    Q.bank(env, {})
end

function Q.visitBank(env)
    Q.openBank(env)
    Q.walkAway(env)
end

--- A saved bank for another character, as BankBags would have saved it
-- when they visited a banker: each entry { name, count }.
function Q.savedBank(ns, realm, name, items)
    local slots = {}
    for index, item in ipairs(items) do
        slots[index] = Q.stack(item[1], item[2])
    end
    ns.db.characters[realm .. "-" .. name] = {
        name = name, realm = realm, class = "MAGE", saved = 0,
        containers = { { id = -1, name = "Bank", size = #slots, slots = slots } },
    }
end

function Q.lineText(env, questID, index, moduleName)
    local block = env[moduleName or "QuestObjectiveTracker"].blocks[questID]
    local line = block and block:GetExistingLine(index)
    return line and line.Text:GetText()
end

function Q.plainLineText(env, questID, index, moduleName)
    local text = Q.lineText(env, questID, index, moduleName)
    return text and (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function plain(text)
    return text and (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

--- Open the map, or let something redraw its quest log: Blizzard draws the
-- whole log again.
function Q.drawMap(env)
    env.QuestLogQuests_Update()
end

--- The line the map's quest log shows for a quest's objective, found by
-- the start of its text: lines come from a shared pool in no set order.
-- Lines the log has put away count, when `putAway` says so.
function Q.mapLine(env, questID, startsWith, putAway)
    local lines = {}
    for _, line in ipairs(env.__mapPool.active) do
        table.insert(lines, line)
    end
    if putAway then
        for _, line in ipairs(env.__mapPool.free) do
            table.insert(lines, line)
        end
    end
    for _, line in ipairs(lines) do
        if line.questID == questID and line.Text:GetText():sub(1, #startsWith) == startsWith then
            return line
        end
    end
end

--- That line's text without colour codes, as the player reads it.
function Q.mapText(env, questID, startsWith)
    local line = Q.mapLine(env, questID, startsWith)
    return line and plain(line.Text:GetText())
end

--- The colour code the note on a line is written in, if it has one.
function Q.noteColour(env, questID, index)
    local text = Q.lineText(env, questID, index)
    return text and text:match("(|c%x%x%x%x%x%x%x%x)%(")
end

--- Show an item's tooltip the way the client does: it runs every post-call
-- registered for items, with the tooltip and its data.
function Q.showItemTooltip(env, tooltip, itemID)
    tooltip.doubleLines = {}
    for _, func in ipairs(env.__tooltipPostCalls[env.Enum.TooltipDataType.Item] or {}) do
        func(tooltip, { id = itemID, type = env.Enum.TooltipDataType.Item })
    end
    return tooltip.doubleLines
end

--- Click a checkbox the way the player does: the tick flips, then OnClick.
function Q.click(checkbox)
    checkbox:SetChecked(not checkbox:GetChecked())
    checkbox.scripts.OnClick(checkbox)
end

return Q
