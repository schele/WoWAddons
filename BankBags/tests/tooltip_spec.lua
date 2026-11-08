local Q = require("quest_helpers")

--- Carl with 12 Boar Intestines in his saved bank.
local function client(setup)
    local ns, env = Q.client(setup)
    Q.banked(env, "Boar Intestines", 12)
    Q.visitBank(env)
    return ns, env
end

local function has(lines, left, right)
    for _, line in ipairs(lines) do
        if line[1] == left and tostring(line[2]) == tostring(right) then
            return true
        end
    end
    return false
end

describe("an item's tooltip", function()
    it("says how many are in your bank", function()
        local _, env = client()

        local lines = Q.showItemTooltip(env, env.GameTooltip, Q.itemID("Boar Intestines"))

        assertTrue(has(lines, "Bank", 12))
    end)

    it("says how many each of your characters on this realm has banked", function()
        local ns, env = client()
        Q.savedBank(ns, "Stormwind", "Alt", { { "Boar Intestines", 5 } })

        local lines = Q.showItemTooltip(env, env.GameTooltip, Q.itemID("Boar Intestines"))

        assertTrue(has(lines, "Bank", 12))
        assertTrue(has(lines, "Alt's bank", 5))
    end)

    it("puts your own bank first, then the others by name", function()
        local ns, env = client()
        Q.savedBank(ns, "Stormwind", "Zed", { { "Boar Intestines", 1 } })
        Q.savedBank(ns, "Stormwind", "Alt", { { "Boar Intestines", 5 } })

        local lines = Q.showItemTooltip(env, env.GameTooltip, Q.itemID("Boar Intestines"))

        assertEqual("Bank", lines[1][1])
        assertEqual("Alt's bank", lines[2][1])
        assertEqual("Zed's bank", lines[3][1])
    end)

    it("leaves out characters on other realms", function()
        local ns, env = client()
        Q.savedBank(ns, "Faraway", "Alt", { { "Boar Intestines", 5 } })

        local lines = Q.showItemTooltip(env, env.GameTooltip, Q.itemID("Boar Intestines"))

        assertEqual(1, #lines)
    end)

    it("adds nothing for an item no bank holds", function()
        local _, env = client()

        local lines = Q.showItemTooltip(env, env.GameTooltip, Q.itemID("Spider Ichor"))

        assertEqual(0, #lines)
    end)

    it("works on a linked item's tooltip too", function()
        local _, env = client()

        local lines = Q.showItemTooltip(env, env.ItemRefTooltip, Q.itemID("Boar Intestines"))

        assertTrue(has(lines, "Bank", 12))
    end)

    it("leaves the comparison tooltips alone", function()
        local _, env = client()

        local lines = Q.showItemTooltip(env, env.ShoppingTooltip1, Q.itemID("Boar Intestines"))

        assertEqual(0, #lines)
    end)

    it("is on to begin with", function()
        local ns = client()
        ns.SettingsPanel.panel:Show()

        assertTrue(ns.db.tooltipCounts)
        assertTrue(ns.SettingsPanel.tooltipCounts:GetChecked())
    end)

    it("adds nothing when turned off", function()
        local ns, env = client()
        ns.SettingsPanel.panel:Show()
        Q.click(ns.SettingsPanel.tooltipCounts)

        local lines = Q.showItemTooltip(env, env.GameTooltip, Q.itemID("Boar Intestines"))

        assertFalse(ns.db.tooltipCounts)
        assertEqual(0, #lines)
    end)

    it("loads quietly on a client without the tooltip hook", function()
        local helpers = require("helpers")
        local ns = helpers.loggedIn()
        assertTrue(ns.db.tooltipCounts)
    end)
end)
