local helpers = require("helpers")

local PARTY = {
    { "party1", "Brann", "WARRIOR" },
    { "party2", "Celia", "MAGE" },
    { "party3", "Dorn", "PRIEST" },
}

--- Brann tanking your target, Defias Pillager, which has a nameplate too;
-- you at 40%. `setup(env)` runs before login.
local function fight(setup)
    local ns, env = helpers.fighting({ party1 = 100, player = 40 }, PARTY, setup)
    env.__units.nameplate1 = env.__units.mob
    helpers.fire(env, "NAME_PLATE_UNIT_ADDED", "nameplate1")
    return ns, env
end

--- The mobs' names, in the order the window shows them.
local function mobs(ns)
    local out = {}
    for index, list in ipairs(ns.Threat.All()) do
        out[index] = list.name or "?"
    end
    return table.concat(out, ", ")
end

describe("a part for each mob you fight", function()
    it("is on to begin with, for three mobs at most", function()
        local ns = fight()

        assertTrue(ns.settings.split)
        assertEqual(3, ns.settings.maxMobs)
    end)

    it("shows your target first, then the other mobs your group fights", function()
        local ns, env = fight()

        helpers.otherMob(env, "nameplate2", "Defias Thug", { party1 = 100, player = 60 })

        assertEqual("Defias Pillager, Defias Thug", mobs(ns))
    end)

    it("puts the mob someone is closest to pulling first, after your target", function()
        local ns, env = fight()

        helpers.otherMob(env, "nameplate2", "Defias Thug", { party1 = 100, player = 30 })
        helpers.otherMob(env, "nameplate3", "Defias Looter", { party1 = 100, party2 = 90 })

        assertEqual("Defias Pillager, Defias Looter, Defias Thug", mobs(ns))
    end)

    it("puts a mob someone is over the tank on before the rest, even with its numbers hidden", function()
        local ns, env = fight()

        helpers.otherMob(env, "nameplate2", "Defias Looter", { party1 = 100, player = 95 })
        helpers.otherMob(env, "nameplate3", "Edwin VanCleef", { party1 = 100, party2 = { 80, 1 } }, { boss = true })

        assertEqual("Defias Pillager, Edwin VanCleef, Defias Looter", mobs(ns))
    end)

    it("shows no more mobs than set", function()
        local ns, env = fight()
        helpers.otherMob(env, "nameplate2", "Defias Thug", { party1 = 100, player = 30 })
        helpers.otherMob(env, "nameplate3", "Defias Looter", { party1 = 100, player = 20 })
        helpers.otherMob(env, "nameplate4", "Defias Miner", { party1 = 100, player = 10 })
        assertEqual(3, #ns.Threat.All(), "three to begin with")

        ns.settings.maxMobs = 2
        ns.Refresh()
        helpers.fire(env, "UNIT_THREAT_LIST_UPDATE", "target")

        assertEqual("Defias Pillager, Defias Thug", mobs(ns))
    end)

    it("leaves out mobs your group is not on the threat list of, and mobs not fighting", function()
        local ns, env = fight()

        helpers.otherMob(env, "nameplate2", "Defias Thug", {})
        helpers.otherMob(env, "nameplate3", "Defias Looter", { player = 30 }, { calm = true })

        assertEqual("Defias Pillager", mobs(ns))
    end)

    it("shows your target once, nameplate or not", function()
        local ns = fight()

        assertEqual(1, #ns.Threat.All())
    end)

    it("shows your target alone with the option off", function()
        local ns, env = fight(function(env)
            env.ThreatForeverDB = { settings = { split = false } }
        end)

        helpers.otherMob(env, "nameplate2", "Defias Thug", { party1 = 100, player = 60 })

        assertEqual("Defias Pillager", mobs(ns))
    end)

    it("drops a mob when its nameplate goes", function()
        local ns, env = fight()
        helpers.otherMob(env, "nameplate2", "Defias Thug", { party1 = 100, player = 60 })

        helpers.fire(env, "NAME_PLATE_UNIT_REMOVED", "nameplate2")
        env.__units.nameplate2 = nil
        helpers.fire(env, "UNIT_THREAT_LIST_UPDATE", "target")

        assertEqual("Defias Pillager", mobs(ns))
    end)

    it("shows the mobs your group fights with nothing targeted, the closest to being pulled first", function()
        local ns, env = fight()
        helpers.otherMob(env, "nameplate2", "Defias Thug", { party1 = 100, player = 60 })

        helpers.target(env, nil)

        -- You are at 60% on the Thug and 40% on the Pillager.
        assertEqual("Defias Thug, Defias Pillager", mobs(ns))
    end)
end)

describe("the window, a part per mob", function()
    it("heads each mob's part with its name, its rows under it", function()
        local ns, env = fight()

        helpers.otherMob(env, "nameplate2", "Defias Thug", { party3 = 100, player = 60 })

        local window = ns.Window
        assertEqual("Defias Pillager", window.headers[1]:GetText())
        assertEqual("Brann", window.rows[1].name:GetText())
        assertEqual("Skyler", window.rows[2].name:GetText())
        assertEqual("Defias Thug", window.headers[2]:GetText())
        assertTrue(window.headers[2]:IsShown())
        assertEqual("Dorn", window.rows[3].name:GetText())
        assertEqual("Skyler", window.rows[4].name:GetText())
        assertFalse(window.rows[5]:IsShown())
    end)

    it("puts each part under the one before it", function()
        local ns, env = fight()

        helpers.otherMob(env, "nameplate2", "Defias Thug", { party3 = 100, player = 60 })

        local function top(widget)
            return select(5, widget:GetPoint(1))
        end
        local window = ns.Window
        assertTrue(top(window.rows[2]) < top(window.rows[1]))
        assertTrue(top(window.headers[2]) < top(window.rows[2]), "the second heading under the first part")
        assertTrue(top(window.rows[3]) < top(window.headers[2]))
    end)

    it("gives each mob five rows at most when it shows more than one", function()
        local ns, env = fight()
        local mob = env.__units.mob
        for _, who in ipairs({ "party2", "party3", "pet" }) do
            mob.threat[who] = { scaled = 10, status = 0, tanking = false }
        end
        helpers.member(env, "pet", "Wolf")
        helpers.member(env, "partypet1", "Cat")
        mob.threat.partypet1 = { scaled = 5, status = 0, tanking = false }

        helpers.otherMob(env, "nameplate2", "Defias Thug", { party1 = 100, player = 60 })

        assertEqual("Defias Thug", ns.Window.headers[2]:GetText())
        assertEqual("Brann", ns.Window.rows[6].name:GetText(), "the second part starts after five")
    end)

    it("hides the parts it does not use", function()
        local ns, env = fight()
        helpers.otherMob(env, "nameplate2", "Defias Thug", { party1 = 100, player = 60 })

        helpers.fire(env, "NAME_PLATE_UNIT_REMOVED", "nameplate2")
        env.__units.nameplate2 = nil
        helpers.fire(env, "UNIT_THREAT_LIST_UPDATE", "target")

        assertFalse(ns.Window.headers[2]:IsShown())
    end)

    it("grows with each part", function()
        local ns, env = fight()
        local one = ns.Window.frame:GetHeight()

        helpers.otherMob(env, "nameplate2", "Defias Thug", { party1 = 100, player = 60 })

        assertTrue(ns.Window.frame:GetHeight() > one)
    end)
end)

describe("the warning, a part per mob", function()
    it("comes when you are about to pull a mob that is not your target", function()
        local _, env = fight()

        helpers.otherMob(env, "nameplate2", "Defias Thug", { party1 = 100, player = { 95, 1 } })

        assertEqual(1, #env.__warnings)
    end)
end)

describe("the settings page, a part per mob", function()
    local function opened(setup)
        local ns, env = helpers.loggedIn(setup)
        ns.SettingsPanel.panel:Show()
        return ns, env, ns.SettingsPanel
    end

    it("has a switch for it", function()
        local ns, _, panel = opened()

        assertEqual("A part for each mob you fight", panel.labels.split:GetText())
        assertTrue(panel.checks.split:GetChecked())
    end)

    it("has a slider for how many mobs, one to five, at three", function()
        local ns, _, panel = opened()

        local slider = panel.maxMobs
        assertEqual("OptionsSliderTemplate", slider.template)
        assertEqual(1, slider.min)
        assertEqual(5, slider.max)
        assertEqual(3, slider:GetValue())
        assertEqual("Mobs at once: 3", panel.maxMobsLabel:GetText())
    end)

    it("sets how many mobs when dragged", function()
        local ns, _, panel = opened()

        panel.maxMobs:Drag(5)

        assertEqual(5, ns.settings.maxMobs)
        assertEqual("Mobs at once: 5", panel.maxMobsLabel:GetText())
    end)
end)
