local helpers = require("helpers")
local Q = require("quest_helpers")

local QUEST = 101

local stack, client, quest, bags, bank, banked = Q.stack, Q.client, Q.quest, Q.bags, Q.bank, Q.banked
local visitBank, drawMap, mapLine, mapText = Q.visitBank, Q.drawMap, Q.mapLine, Q.mapText

--- A quest in the log, bags and bank stocked, the bank visited once, and
-- the map's quest log drawn.
local function mapped(objectives, stock, setup)
    local ns, env = client(setup)
    quest(env, QUEST, objectives)
    local slots = {}
    for name, counts in pairs(stock) do
        bags(env, name, counts[1])
        if counts[2] > 0 then
            table.insert(slots, stack(name, counts[2]))
        end
    end
    bank(env, { [-1] = slots })
    visitBank(env)
    drawMap(env)
    return ns, env
end

-- Carl's Thelsamar Blood Sausages: 12 Boar Intestines, all in the bank, and
-- the log saying 0/3.
local function intestines(carried, inBank, setup)
    return mapped({ { "0/3 Boar Intestines", "item", 0, 3 } },
        { ["Boar Intestines"] = { carried, inBank } }, setup)
end

describe("quest items in the bank, in the map's quest log", function()
    it("says how many are in the bank", function()
        local _, env = intestines(0, 12)

        assertEqual("0/3 Boar Intestines (12 in bank)", mapText(env, QUEST, "0/3 Boar Intestines"))
    end)

    it("colours the note as the tracker does", function()
        local _, env = intestines(0, 12)

        assertMatch("^0/3 Boar Intestines |cffffa040%(12 in bank%)|r$",
            mapLine(env, QUEST, "0/3 Boar Intestines").Text:GetText())
    end)

    it("notes each objective of a quest on its own, whatever order the lines come in", function()
        local _, env = mapped({
            { "0/3 Boar Intestines", "item", 0, 3 },
            { "0/3 Bear Meat", "item", 0, 3 },
            { "0/3 Spider Ichor", "item", 0, 3 },
        }, {
            ["Boar Intestines"] = { 0, 12 },
            ["Bear Meat"] = { 0, 2 },
            ["Spider Ichor"] = { 0, 0 },
        })

        assertEqual("0/3 Boar Intestines (12 in bank)", mapText(env, QUEST, "0/3 Boar Intestines"))
        assertEqual("0/3 Bear Meat (2 in bank)", mapText(env, QUEST, "0/3 Bear Meat"))
        assertEqual("0/3 Spider Ichor", mapText(env, QUEST, "0/3 Spider Ichor"))
    end)

    it("finds the right objective when the log skips a finished one", function()
        -- The log leaves out a finished objective, so the only line is the
        -- quest's second objective.
        local _, env = mapped({
            { "3/3 Bear Meat", "item", 3, 3 },
            { "0/3 Boar Intestines", "item", 0, 3 },
        }, {
            ["Bear Meat"] = { 1, 6 },
            ["Boar Intestines"] = { 0, 12 },
        })

        assertNil(mapLine(env, QUEST, "3/3 Bear Meat"))
        assertEqual("0/3 Boar Intestines (12 in bank)", mapText(env, QUEST, "0/3 Boar Intestines"))
    end)

    it("adds nothing when the bags hold enough", function()
        local _, env = intestines(3, 12)

        assertEqual("0/3 Boar Intestines", mapLine(env, QUEST, "0/3 Boar Intestines").Text:GetText())
    end)

    it("adds nothing when none are banked", function()
        local _, env = intestines(0, 0)

        assertEqual("0/3 Boar Intestines", mapLine(env, QUEST, "0/3 Boar Intestines").Text:GetText())
    end)

    it("adds what an alt has banked, as the tracker does", function()
        local ns, env = client()
        quest(env, QUEST, { { "0/3 Boar Intestines", "item", 0, 3 } })
        bank(env, {})
        visitBank(env)
        Q.savedBank(ns, "Stormwind", "Morwen", { { "Boar Intestines", 5 } })
        drawMap(env)

        assertEqual("0/3 Boar Intestines (5 on Morwen)", mapText(env, QUEST, "0/3 Boar Intestines"))
    end)

    it("does not pile up notes when the log redraws", function()
        local _, env = intestines(0, 12)

        drawMap(env)
        helpers.fire(env, "BAG_UPDATE_DELAYED")
        drawMap(env)

        assertEqual("0/3 Boar Intestines (12 in bank)", mapText(env, QUEST, "0/3 Boar Intestines"))
    end)
end)

describe("the map's quest log, following the items", function()
    it("drops the note when the bags come to hold enough", function()
        local _, env = intestines(0, 12)

        bags(env, "Boar Intestines", 3)
        helpers.fire(env, "BAG_UPDATE_DELAYED")

        assertEqual("0/3 Boar Intestines", mapLine(env, QUEST, "0/3 Boar Intestines").Text:GetText())
    end)

    it("updates the note when the bank changes at a banker", function()
        local _, env = intestines(0, 12)

        Q.openBank(env)
        bank(env, { [-1] = { stack("Boar Intestines", 4) } })
        helpers.fire(env, "PLAYERBANKSLOTS_CHANGED", 1)
        env.__runTimers()

        assertEqual("0/3 Boar Intestines (4 in bank)", mapText(env, QUEST, "0/3 Boar Intestines"))
    end)

    it("does not write on a line the log has put away", function()
        local _, env = intestines(0, 12)
        local line = mapLine(env, QUEST, "0/3 Boar Intestines")

        env.__mapHidden[QUEST] = true
        drawMap(env)
        bags(env, "Boar Intestines", 3)
        helpers.fire(env, "BAG_UPDATE_DELAYED")

        assertFalse(line:IsShown())
        assertEqual("0/3 Boar Intestines (12 in bank)", (line.Text:GetText():gsub("|c%x+", ""):gsub("|r", "")))
    end)
end)

describe("a line of the map's quest log with little room left", function()
    -- "0/3 Boar Intestines" is 19 characters; the full note adds 13 and the
    -- short one 10.
    local function narrow(width)
        return intestines(0, 12, function(env) env.__mapLineWidth = width end)
    end

    it("uses the short note when the full one would wrap onto another line", function()
        local _, env = narrow(30)

        assertEqual("0/3 Boar Intestines (12 bank)", mapText(env, QUEST, "0/3 Boar Intestines"))
    end)

    it("is left alone when even the short note would wrap", function()
        local _, env = narrow(25)

        assertEqual("0/3 Boar Intestines", mapLine(env, QUEST, "0/3 Boar Intestines").Text:GetText())
    end)
end)

describe("the map's quest log and the setting", function()
    it("takes the notes off the log the moment it is turned off", function()
        local ns, env = intestines(0, 12)
        ns.SettingsPanel.panel:Show()

        Q.click(ns.SettingsPanel.questNotes)

        assertEqual("0/3 Boar Intestines", mapLine(env, QUEST, "0/3 Boar Intestines").Text:GetText())
    end)

    it("stays off when the log redraws", function()
        local ns, env = intestines(0, 12)
        ns.SettingsPanel.panel:Show()
        Q.click(ns.SettingsPanel.questNotes)

        drawMap(env)

        assertEqual("0/3 Boar Intestines", mapLine(env, QUEST, "0/3 Boar Intestines").Text:GetText())
    end)

    it("says on the settings page that it covers the map too", function()
        local ns = client()
        ns.SettingsPanel.panel:Show()

        assertMatch("map", ns.SettingsPanel.questNotes.label:GetText())
    end)
end)

describe("loading, with the map's quest log", function()
    it("hooks the log when it loads after BankBags", function()
        local update
        local _, env = client(function(env)
            update = env.QuestLogQuests_Update
            env.QuestLogQuests_Update = nil
        end)
        env.QuestLogQuests_Update = update
        helpers.fire(env, "ADDON_LOADED", "Blizzard_WorldMap")

        quest(env, QUEST, { { "0/3 Boar Intestines", "item", 0, 3 } })
        banked(env, "Boar Intestines", 12)
        visitBank(env)
        drawMap(env)

        assertEqual("0/3 Boar Intestines (12 in bank)", mapText(env, QUEST, "0/3 Boar Intestines"))
    end)

    it("leaves the tracker's notes as they were", function()
        local _, env = intestines(0, 12)
        env.QuestObjectiveTracker:UpdateQuest(QUEST)

        assertEqual("0/3 Boar Intestines (12 in bank)", Q.plainLineText(env, QUEST, 1))
    end)
end)
