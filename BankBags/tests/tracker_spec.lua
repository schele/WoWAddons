local helpers = require("helpers")
local Q = require("quest_helpers")

local QUEST = 101

local stack, client, quest, bags, bank, banked = Q.stack, Q.client, Q.quest, Q.bags, Q.bank, Q.banked
local openBank, walkAway, visitBank = Q.openBank, Q.walkAway, Q.visitBank
local lineText, plainLineText = Q.lineText, Q.plainLineText

--- A quest with one item objective, bags and bank stocked, the bank visited
-- once, and the tracker drawn.
local function tracked(objective, item, carried, inBank, setup)
    local ns, env = client(setup)
    quest(env, QUEST, { objective })
    bags(env, item, carried)
    banked(env, item, inBank)
    visitBank(env)
    env.QuestObjectiveTracker:UpdateQuest(QUEST)
    return ns, env
end

-- Carl's Thelsamar Blood Sausages: 12 Boar Intestines, all in the bank, and
-- the tracker saying 0/3.
local function intestines(carried, inBank, shown)
    return tracked({ shown .. "/3 Boar Intestines", "item", shown, 3 }, "Boar Intestines", carried, inBank)
end

describe("quest items in the bank, on the tracker", function()
    it("says how many are in the bank when the count leaves them out", function()
        local _, env = intestines(0, 12, 0)

        assertEqual("0/3 Boar Intestines (12 in bank)", plainLineText(env, QUEST, 1))
    end)

    it("says how many are in the bank when the count takes them in", function()
        -- Carl's Golem Isospring: 7 carried, 7 banked, and the tracker at 14/14.
        local _, env = tracked({ "14/14 Golem Isospring", "item", 14, 14 }, "Golem Isospring", 7, 7)

        assertEqual("14/14 Golem Isospring (7 in bank)", plainLineText(env, QUEST, 1))
    end)

    it("colours the note so it stands out from the objective", function()
        local _, env = intestines(0, 12, 0)

        assertMatch("^0/3 Boar Intestines |c%x%x%x%x%x%x%x%x%(12 in bank%)|r$", lineText(env, QUEST, 1))
    end)

    it("adds up every stack, in every bank bag and tab", function()
        local _, env = client()
        quest(env, QUEST, { { "0/3 Boar Intestines", "item", 0, 3 } })
        bank(env, {
            [-1] = { stack("Boar Intestines", 2), false, stack("Bear Meat", 4) },
            [5] = { stack("Boar Intestines", 5) },
            [10] = { false, stack("Boar Intestines", 1) },
        })
        visitBank(env)
        env.QuestObjectiveTracker:UpdateQuest(QUEST)

        assertEqual("0/3 Boar Intestines (8 in bank)", plainLineText(env, QUEST, 1))
    end)

    it("notes each objective of a quest on its own", function()
        local _, env = client()
        quest(env, QUEST, {
            { "0/3 Boar Intestines", "item", 0, 3 },
            { "0/3 Bear Meat", "item", 0, 3 },
            { "0/3 Spider Ichor", "item", 0, 3 },
        })
        bank(env, { [-1] = { stack("Boar Intestines", 12), stack("Bear Meat", 2) } })
        visitBank(env)
        env.QuestObjectiveTracker:UpdateQuest(QUEST)

        assertEqual("0/3 Boar Intestines (12 in bank)", plainLineText(env, QUEST, 1))
        assertEqual("0/3 Bear Meat (2 in bank)", plainLineText(env, QUEST, 2))
        assertEqual("0/3 Spider Ichor", lineText(env, QUEST, 3))
    end)

    it("reads the 'Name: 0/3' form of the text as well", function()
        local _, env = tracked({ "Boar Intestines: 0/3", "item", 0, 3 }, "Boar Intestines", 0, 12)

        assertEqual("Boar Intestines: 0/3 (12 in bank)", plainLineText(env, QUEST, 1))
    end)

    it("works in the campaign quests too", function()
        local _, env = client()
        quest(env, QUEST, { { "0/3 Boar Intestines", "item", 0, 3 } })
        banked(env, "Boar Intestines", 12)
        visitBank(env)
        env.CampaignQuestObjectiveTracker:UpdateQuest(QUEST)

        assertEqual("0/3 Boar Intestines (12 in bank)", plainLineText(env, QUEST, 1, "CampaignQuestObjectiveTracker"))
    end)

    it("counts another character's bank as theirs, not this character's", function()
        local _, env = client(function(env)
            env.BankBagsDB = { characters = { ["Stormwind-Alt"] = { name = "Alt", realm = "Stormwind", containers = {
                { id = -1, name = "Bank", size = 1, slots = { stack("Boar Intestines", 12) } },
            } } } }
        end)
        quest(env, QUEST, { { "0/3 Boar Intestines", "item", 0, 3 } })
        env.QuestObjectiveTracker:UpdateQuest(QUEST)

        assertEqual("0/3 Boar Intestines (12 on Alt)", plainLineText(env, QUEST, 1))
    end)
end)

describe("an objective that needs no note", function()
    it("is left alone when your bags hold enough", function()
        local _, env = intestines(3, 12, 3)

        assertEqual("3/3 Boar Intestines", lineText(env, QUEST, 1))
    end)

    it("is left alone when nothing is in the bank", function()
        local _, env = intestines(1, 0, 1)

        assertEqual("1/3 Boar Intestines", lineText(env, QUEST, 1))
    end)

    it("is left alone when it is not about items", function()
        local _, env = tracked({ "9/15 Defias Trapper slain", "monster", 9, 15 }, "Defias Trapper slain", 0, 5)

        assertEqual("9/15 Defias Trapper slain", lineText(env, QUEST, 1))
    end)
end)

describe("where the bank count comes from", function()
    it("knows nothing of the bank before it has been saved", function()
        local _, env = client()
        quest(env, QUEST, { { "0/3 Boar Intestines", "item", 0, 3 } })
        env.QuestObjectiveTracker:UpdateQuest(QUEST)

        assertEqual("0/3 Boar Intestines", lineText(env, QUEST, 1))
    end)

    it("adds the note the moment you open the bank", function()
        local _, env = client()
        quest(env, QUEST, { { "0/3 Boar Intestines", "item", 0, 3 } })
        banked(env, "Boar Intestines", 12)
        env.QuestObjectiveTracker:UpdateQuest(QUEST)

        openBank(env)

        assertEqual("0/3 Boar Intestines (12 in bank)", plainLineText(env, QUEST, 1))
    end)

    it("still knows after you walk away from the banker", function()
        local _, env = intestines(0, 12, 0)

        helpers.fire(env, "BAG_UPDATE_DELAYED")
        env.QuestObjectiveTracker:UpdateQuest(QUEST)

        assertEqual("0/3 Boar Intestines (12 in bank)", plainLineText(env, QUEST, 1))
    end)

    it("uses the bank saved in an earlier session", function()
        local _, env = client(function(env)
            env.BankBagsDB = { characters = { ["Stormwind-Carl"] = { name = "Carl", containers = {
                { id = -1, name = "Bank", size = 1, slots = { stack("Boar Intestines", 12) } },
            } } } }
        end)
        quest(env, QUEST, { { "0/3 Boar Intestines", "item", 0, 3 } })
        env.QuestObjectiveTracker:UpdateQuest(QUEST)

        assertEqual("0/3 Boar Intestines (12 in bank)", plainLineText(env, QUEST, 1))
    end)

    it("drops the note when you forget your bank", function()
        local _, env = intestines(0, 12, 0)

        helpers.command(env, "forget Carl")

        assertEqual("0/3 Boar Intestines", lineText(env, QUEST, 1))
    end)
end)

describe("when the items move", function()
    it("drops the note when you take them out of the bank", function()
        local _, env = client()
        quest(env, QUEST, { { "0/3 Boar Intestines", "item", 0, 3 } })
        banked(env, "Boar Intestines", 12)
        openBank(env)
        env.QuestObjectiveTracker:UpdateQuest(QUEST)

        bank(env, { [-1] = { false } })
        bags(env, "Boar Intestines", 12)
        helpers.fire(env, "PLAYERBANKSLOTS_CHANGED")
        env.__runTimers()

        assertEqual("0/3 Boar Intestines", lineText(env, QUEST, 1))
    end)

    it("adds the note when you put some in the bank", function()
        -- The count stays 14/14, so the tracker itself has no reason to redraw.
        local _, env = client()
        quest(env, QUEST, { { "14/14 Golem Isospring", "item", 14, 14 } })
        bags(env, "Golem Isospring", 14)
        bank(env, {})
        openBank(env)
        env.QuestObjectiveTracker:UpdateQuest(QUEST)

        bags(env, "Golem Isospring", 7)
        bank(env, { [5] = { stack("Golem Isospring", 7) } })
        helpers.fire(env, "BAG_UPDATE", 5)
        env.__runTimers()

        assertEqual("14/14 Golem Isospring (7 in bank)", plainLineText(env, QUEST, 1))
    end)

    it("drops the note when the bags come to hold enough", function()
        local _, env = intestines(0, 12, 0)

        bags(env, "Boar Intestines", 3)
        helpers.fire(env, "BAG_UPDATE_DELAYED")

        assertEqual("0/3 Boar Intestines", lineText(env, QUEST, 1))
    end)

    it("does not write on a line that now shows another quest", function()
        local _, env = intestines(0, 12, 0)
        local OTHER = 202
        quest(env, OTHER, { { "1/1 Note from the Farmer", "item", 1, 1 } })
        bags(env, "Note from the Farmer", 1)

        env.QuestObjectiveTracker.blocks[QUEST]:Free()
        env.QuestObjectiveTracker:UpdateQuest(OTHER)
        helpers.fire(env, "BAG_UPDATE_DELAYED")

        assertEqual("1/1 Note from the Farmer", lineText(env, OTHER, 1))
    end)

    it("does not write on a line the tracker reused for something else", function()
        -- Blizzard adds lines like "Ready for turn-in" straight to the block,
        -- not through DoQuestObjectives, from the same pool.
        local _, env = intestines(0, 12, 0)
        local OTHER = 202
        quest(env, OTHER, {})

        env.QuestObjectiveTracker.blocks[QUEST]:Free()
        local block = env.QuestObjectiveTracker:UpdateQuest(OTHER)
        block:AddObjective("QuestComplete", "Ready for turn-in")
        helpers.fire(env, "BAG_UPDATE_DELAYED")

        assertEqual("Ready for turn-in", block:GetExistingLine("QuestComplete").Text:GetText())
    end)

    it("does not pile up notes when the tracker redraws", function()
        local _, env = intestines(0, 12, 0)

        env.QuestObjectiveTracker:UpdateQuest(QUEST)
        helpers.fire(env, "BAG_UPDATE_DELAYED")
        env.QuestObjectiveTracker:UpdateQuest(QUEST)

        assertEqual("0/3 Boar Intestines (12 in bank)", plainLineText(env, QUEST, 1))
    end)
end)

describe("a line with little room left", function()
    -- "0/3 Boar Intestines" is 19 characters; the full note adds 13 and the
    -- short one 10.
    local function narrow(width)
        return tracked({ "0/3 Boar Intestines", "item", 0, 3 }, "Boar Intestines", 0, 12,
            function(env) env.__lineWidth = width end)
    end

    it("uses the short note when the full one would wrap onto another line", function()
        local _, env = narrow(30)

        assertEqual("0/3 Boar Intestines (12 bank)", plainLineText(env, QUEST, 1))
    end)

    it("is left alone when even the short note would wrap", function()
        local _, env = narrow(25)

        assertEqual("0/3 Boar Intestines", lineText(env, QUEST, 1))
    end)

    it("keeps the note on an objective that already wraps, if it fits in the last line", function()
        local _, env = narrow(16)

        assertEqual("0/3 Boar Intestines (12 in bank)", plainLineText(env, QUEST, 1))
    end)
end)

describe("the setting", function()
    local function click(checkbox)
        checkbox:SetChecked(not checkbox:GetChecked())
        checkbox.scripts.OnClick(checkbox)
    end

    it("is on to begin with", function()
        local ns = client()
        ns.SettingsPanel.panel:Show()

        assertTrue(ns.db.questNotes)
        assertTrue(ns.SettingsPanel.questNotes:GetChecked())
    end)

    it("takes the notes off the tracker the moment it is turned off", function()
        local ns, env = intestines(0, 12, 0)
        ns.SettingsPanel.panel:Show()

        click(ns.SettingsPanel.questNotes)

        assertFalse(ns.db.questNotes)
        assertEqual("0/3 Boar Intestines", lineText(env, QUEST, 1))
    end)

    it("stays off when the tracker redraws", function()
        local ns, env = intestines(0, 12, 0)
        ns.SettingsPanel.panel:Show()
        click(ns.SettingsPanel.questNotes)

        env.QuestObjectiveTracker:UpdateQuest(QUEST)
        helpers.fire(env, "BAG_UPDATE_DELAYED")

        assertEqual("0/3 Boar Intestines", lineText(env, QUEST, 1))
    end)

    it("puts the notes back when it is turned on again", function()
        local ns, env = intestines(0, 12, 0)
        ns.SettingsPanel.panel:Show()
        click(ns.SettingsPanel.questNotes)

        click(ns.SettingsPanel.questNotes)

        assertEqual("0/3 Boar Intestines (12 in bank)", plainLineText(env, QUEST, 1))
    end)
end)

describe("loading", function()
    it("loads quietly on a client without the quest tracker", function()
        local ns = helpers.loggedIn()
        assertTrue(ns.db ~= nil)
    end)

    it("hooks the tracker when it loads after BankBags", function()
        local tracker
        local _, env = client(function(env)
            tracker = env.QuestObjectiveTracker
            env.QuestObjectiveTracker = nil
        end)
        env.QuestObjectiveTracker = tracker
        helpers.fire(env, "ADDON_LOADED", "Blizzard_ObjectiveTracker")

        quest(env, QUEST, { { "0/3 Boar Intestines", "item", 0, 3 } })
        banked(env, "Boar Intestines", 12)
        visitBank(env)
        env.QuestObjectiveTracker:UpdateQuest(QUEST)

        assertEqual("0/3 Boar Intestines (12 in bank)", plainLineText(env, QUEST, 1))
    end)
end)

describe("other characters' banks", function()
    -- Alt and Bob play on Stormwind, as Carl does: mail can reach them. The
    -- tracker is wide enough for a note with two parts, unless `setup` says.
    local function withAlts(own, alts, setup)
        local ns, env = client(setup or function(env) env.__lineWidth = 60 end)
        quest(env, QUEST, { { "0/3 Boar Intestines", "item", 0, 3 } })
        if own > 0 then banked(env, "Boar Intestines", own) else bank(env, {}) end
        visitBank(env)
        for _, alt in ipairs(alts) do
            Q.savedBank(ns, alt[3] or "Stormwind", alt[1], { { "Boar Intestines", alt[2] } })
        end
        env.QuestObjectiveTracker:UpdateQuest(QUEST)
        return ns, env
    end

    it("adds what an alt has banked when your own bank falls short", function()
        local _, env = withAlts(0, { { "Alt", 5 } })

        assertEqual("0/3 Boar Intestines (5 on Alt)", plainLineText(env, QUEST, 1))
    end)

    it("puts your own bank first", function()
        local _, env = withAlts(1, { { "Alt", 5 } })

        assertEqual("0/3 Boar Intestines (1 in bank, 5 on Alt)", plainLineText(env, QUEST, 1))
    end)

    it("leaves the alts out when your own bank holds enough", function()
        local _, env = withAlts(12, { { "Alt", 5 } })

        assertEqual("0/3 Boar Intestines (12 in bank)", plainLineText(env, QUEST, 1))
    end)

    it("leaves out characters on other realms, which mail cannot reach", function()
        local _, env = withAlts(0, { { "Alt", 5, "Faraway" } })

        assertEqual("0/3 Boar Intestines", lineText(env, QUEST, 1))
    end)

    it("lists the alt with the most first", function()
        local _, env = withAlts(0, { { "Alt", 2 }, { "Bob", 5 } })

        assertEqual("0/3 Boar Intestines (5 on Bob, 2 on Alt)", plainLineText(env, QUEST, 1))
    end)

    it("drops the alts before the line would wrap", function()
        -- 19 characters, then " (1 in bank, 5 on Alt)" is 22, " (1 bank, 5 Alt)"
        -- 16 and " (1 in bank)" 12.
        local _, env = withAlts(1, { { "Alt", 5 } }, function(env) env.__lineWidth = 32 end)

        assertEqual("0/3 Boar Intestines (1 in bank)", plainLineText(env, QUEST, 1))
    end)

    it("is on to begin with", function()
        local ns = client()
        ns.SettingsPanel.panel:Show()

        assertTrue(ns.db.questAlts)
        assertTrue(ns.SettingsPanel.questAlts:GetChecked())
    end)

    it("leaves the alts out when turned off", function()
        local ns, env = withAlts(1, { { "Alt", 5 } })
        ns.SettingsPanel.panel:Show()

        Q.click(ns.SettingsPanel.questAlts)

        assertFalse(ns.db.questAlts)
        assertEqual("0/3 Boar Intestines (1 in bank)", plainLineText(env, QUEST, 1))
    end)
end)

describe("a ticked objective you cannot hand in yet", function()
    local RED, ORANGE = "|cffff4040", "|cffffa040"

    -- Carl's Golem Isospring: ticked at 14/14 with only 7 carried.
    local function isosprings(inBank)
        return tracked({ "14/14 Golem Isospring", "item", 14, 14 }, "Golem Isospring", 7, inBank)
    end

    it("writes the note in red", function()
        local _, env = isosprings(7)

        assertEqual(RED, Q.noteColour(env, QUEST, 1))
        assertEqual("14/14 Golem Isospring (7 in bank)", plainLineText(env, QUEST, 1))
    end)

    it("says how many you carry when none are banked anywhere", function()
        local _, env = isosprings(0)

        assertEqual("14/14 Golem Isospring (7 carried)", plainLineText(env, QUEST, 1))
        assertEqual(RED, Q.noteColour(env, QUEST, 1))
    end)

    it("keeps the usual colour on an objective not ticked yet", function()
        local _, env = tracked({ "0/3 Boar Intestines", "item", 0, 3 }, "Boar Intestines", 0, 12)

        assertEqual(ORANGE, Q.noteColour(env, QUEST, 1))
    end)

    it("is on to begin with", function()
        local ns = client()
        ns.SettingsPanel.panel:Show()

        assertTrue(ns.db.questWarn)
        assertTrue(ns.SettingsPanel.questWarn:GetChecked())
    end)

    it("is plain again when turned off", function()
        local ns, env = isosprings(7)
        ns.SettingsPanel.panel:Show()

        Q.click(ns.SettingsPanel.questWarn)

        assertFalse(ns.db.questWarn)
        assertEqual(ORANGE, Q.noteColour(env, QUEST, 1))
    end)

    it("says nothing of what you carry when turned off", function()
        local ns, env = isosprings(0)
        ns.SettingsPanel.panel:Show()

        Q.click(ns.SettingsPanel.questWarn)

        assertEqual("14/14 Golem Isospring", lineText(env, QUEST, 1))
    end)
end)
