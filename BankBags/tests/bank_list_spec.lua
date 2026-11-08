local helpers = require("helpers")
local Q = require("quest_helpers")

local SAUSAGES = "Thelsamar Blood Sausages"

--- Carl with Thelsamar Blood Sausages in his log, the bank stocked.
local function atBanker(objectives, bankSlots, setup)
    local ns, env = Q.client(setup)
    Q.quest(env, 101, objectives, SAUSAGES)
    Q.bank(env, { [-1] = bankSlots })
    return ns, env
end

describe("opening the bank", function()
    it("lists what to take out for your quests", function()
        local _, env = atBanker({ { "0/3 Boar Intestines", "item", 0, 3 } }, { Q.stack("Boar Intestines", 12) })

        Q.openBank(env)

        assertMatch("Take out 3 Boar Intestines for Thelsamar Blood Sausages %(12 in the bank%)%.", helpers.printed(env))
    end)

    it("counts what you already carry", function()
        local _, env = atBanker({ { "1/3 Boar Intestines", "item", 1, 3 } }, { Q.stack("Boar Intestines", 12) })
        Q.bags(env, "Boar Intestines", 1)

        Q.openBank(env)

        assertMatch("Take out 2 Boar Intestines for", helpers.printed(env))
    end)

    it("never says to take out more than the bank holds", function()
        local _, env = atBanker({ { "0/3 Boar Intestines", "item", 0, 3 } }, { Q.stack("Boar Intestines", 2) })

        Q.openBank(env)

        assertMatch("Take out 2 Boar Intestines for Thelsamar Blood Sausages %(2 in the bank%)%.", helpers.printed(env))
    end)

    it("lists every item of every quest that needs one", function()
        local _, env = atBanker({
            { "0/3 Boar Intestines", "item", 0, 3 },
            { "0/3 Bear Meat", "item", 0, 3 },
            { "0/3 Spider Ichor", "item", 0, 3 },
        }, { Q.stack("Boar Intestines", 12), Q.stack("Bear Meat", 4) })
        Q.quest(env, 202, { { "0/14 Golem Isospring", "item", 0, 14 } }, "Harvesting the Harvesters")
        Q.bank(env, { [-1] = { Q.stack("Boar Intestines", 12), Q.stack("Bear Meat", 4) }, [5] = { Q.stack("Golem Isospring", 7) } })

        Q.openBank(env)

        local printed = helpers.printed(env)
        assertMatch("Take out 3 Boar Intestines for Thelsamar Blood Sausages", printed)
        assertMatch("Take out 3 Bear Meat for Thelsamar Blood Sausages", printed)
        assertMatch("Take out 7 Golem Isospring for Harvesting the Harvesters", printed)
        assertFalse(printed:find("Spider Ichor") ~= nil, "nothing banked, nothing to take out")
    end)

    it("says nothing when your bags already hold enough", function()
        local _, env = atBanker({ { "3/3 Boar Intestines", "item", 3, 3 } }, { Q.stack("Boar Intestines", 12) })
        Q.bags(env, "Boar Intestines", 3)

        Q.openBank(env)

        assertEqual("", helpers.printed(env))
    end)

    it("says nothing of objectives that are not about items", function()
        local _, env = atBanker({ { "9/15 Defias Trapper slain", "monster", 9, 15 } }, { Q.stack("Defias Trapper slain", 5) })

        Q.openBank(env)

        assertEqual("", helpers.printed(env))
    end)

    it("lists once a visit, not on every change at the bank", function()
        local _, env = atBanker({ { "0/3 Boar Intestines", "item", 0, 3 } }, { Q.stack("Boar Intestines", 12) })
        Q.openBank(env)
        local first = helpers.printed(env)

        helpers.fire(env, "PLAYERBANKSLOTS_CHANGED")
        env.__runTimers()

        assertEqual(first, helpers.printed(env))
    end)

    it("is on to begin with", function()
        local ns = Q.client()
        ns.SettingsPanel.panel:Show()

        assertTrue(ns.db.bankList)
        assertTrue(ns.SettingsPanel.bankList:GetChecked())
    end)

    it("says nothing when turned off", function()
        local ns, env = atBanker({ { "0/3 Boar Intestines", "item", 0, 3 } }, { Q.stack("Boar Intestines", 12) })
        ns.SettingsPanel.panel:Show()
        Q.click(ns.SettingsPanel.bankList)

        Q.openBank(env)

        assertFalse(ns.db.bankList)
        assertEqual("", helpers.printed(env))
    end)
end)
