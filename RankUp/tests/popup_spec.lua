local helpers = require("helpers")

local HEALING_TOUCH = { name = "Healing Touch", fromRank = "Rank 4", toRank = "Rank 5", toID = 5189, slots = { 3, 14 } }
local REJUVENATION = { name = "Rejuvenation", fromRank = "Rank 2", toRank = "Rank 3", toID = 1430, slots = { 20 } }

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

describe("the popup", function()
    it("lists one line per spell", function()
        local ns = helpers.loadAddon()

        ns.Popup.Show({ HEALING_TOUCH, REJUVENATION })

        local lines = ns.Popup.frame.lines
        assertEqual("Healing Touch: Rank 4 -> Rank 5 (2 buttons)", lines[1]:GetText())
        assertEqual("Rejuvenation: Rank 2 -> Rank 3 (1 button)", lines[2]:GetText())
        assertTrue(ns.Popup.IsShown())
    end)

    it("hides the lines a longer list left behind", function()
        local ns = helpers.loadAddon()

        ns.Popup.Show({ HEALING_TOUCH, REJUVENATION })
        ns.Popup.Show({ HEALING_TOUCH })

        assertTrue(ns.Popup.frame.lines[1]:IsShown())
        assertFalse(ns.Popup.frame.lines[2]:IsShown())
    end)

    it("grows to fit a long list", function()
        local ns = helpers.loadAddon()
        ns.Popup.Show({ HEALING_TOUCH })
        local short = ns.Popup.frame:GetHeight()

        local many = {}
        for index = 1, 12 do
            many[index] = HEALING_TOUCH
        end
        ns.Popup.Show(many)

        assertTrue(ns.Popup.frame:GetHeight() > short)
        assertTrue(ns.Popup.frame.lines[12]:IsShown())
    end)

    it("words a rank plainly when the client gave it no words", function()
        local ns = helpers.loadAddon()

        ns.Popup.Show({ { name = "Fishing", toID = 7731, slots = { 9 } } })

        assertEqual("Fishing: older rank -> highest rank (1 button)", ns.Popup.frame.lines[1]:GetText())
    end)

    it("is not shown before anything asks for it", function()
        local ns = helpers.loadAddon()

        assertFalse(ns.Popup.IsShown())
    end)
end)

describe("the popup's buttons", function()
    it("Upgrade upgrades and closes", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        ns.Popup.Show(ns.Ranks.Outdated())

        ns.Popup.frame.upgrade:Click()

        assertEqual(5189, env.__actions[3].id)
        assertFalse(ns.Popup.IsShown())
    end)

    it("Not now closes and changes nothing", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        ns.Popup.Show(ns.Ranks.Outdated())

        ns.Popup.frame.notNow:Click()

        assertEqual(5188, env.__actions[3].id)
        assertFalse(ns.Popup.IsShown())
    end)

    it("closes on Escape, as the game's dialogs do", function()
        local ns, env = helpers.loadAddon()

        ns.Popup.Show({ HEALING_TOUCH })

        assertTrue(contains(env.UISpecialFrames, "RankUpPopup"))
    end)
end)

describe("the popup and combat", function()
    it("disables Upgrade when a fight starts, and enables it after", function()
        local ns = helpers.loadAddon()
        ns.Popup.Show({ HEALING_TOUCH })

        ns.Popup.SetCombat(true)
        assertFalse(ns.Popup.frame.upgrade:IsEnabled())

        ns.Popup.SetCombat(false)
        assertTrue(ns.Popup.frame.upgrade:IsEnabled())
    end)

    it("opens with Upgrade disabled during a fight", function()
        local ns, env = helpers.loadAddon()
        env.__inCombat = true

        ns.Popup.Show({ HEALING_TOUCH })

        assertFalse(ns.Popup.frame.upgrade:IsEnabled())
    end)

    it("stays open when a fight stops Upgrade partway", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        helpers.place(env, 14, 5186)
        ns.Popup.Show(ns.Ranks.Outdated())
        env.__onPlace = function()
            env.__inCombat = true
        end

        ns.Popup.frame.upgrade:Click()

        assertTrue(ns.Popup.IsShown())
    end)
end)
