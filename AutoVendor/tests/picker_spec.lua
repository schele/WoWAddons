local helpers = require("helpers")

local function loggedIn()
    local ns, env = helpers.loadAddon()
    helpers.login(env)
    return ns, env
end

--- Logged in with the page on screen, as the options window shows it.
local function opened()
    local ns, env = loggedIn()
    ns.SettingsPanel.panel:Show()
    return ns, env, ns.Picker
end

--- The bag icons the page is showing, in order: buttons are kept for reuse,
-- so a hidden one is not part of the grid.
local function shownButtons(picker)
    local shown = {}
    for _, button in ipairs(picker.buttons) do
        if button:IsShown() then
            shown[#shown + 1] = button
        end
    end
    return shown
end

local function click(button)
    button.scripts.OnClick(button, "LeftButton")
end

--- Ten or more white items of its own, each worth a copper, ids from 5001.
local function manyItems(env, count)
    for index = 1, count do
        local id = 5000 + index
        env.__items[id] = { name = string.format("Item %02d", index), quality = 1, price = 1 }
        helpers.put(env, 1 + math.floor((index - 1) / 6), 1 + (index - 1) % 6, id)
    end
end

describe("the bag grid", function()
    it("shows each item in the bags that could be sold, once, as its icon", function()
        local ns, env = loggedIn()
        helpers.put(env, 0, 1, 2589)
        helpers.put(env, 0, 2, 2589)
        helpers.put(env, 0, 3, 3300) -- grey: sold anyway
        ns.SettingsPanel.panel:Show()

        local buttons = shownButtons(ns.Picker)
        assertEqual(1, #buttons)
        assertEqual(2589, buttons[1].itemID)
        assertEqual(1, buttons[1].icon:GetTexture())
        assertFalse(ns.Picker.empty:IsShown())
    end)

    it("says when nothing else in the bags can be sold", function()
        local _, _, picker = opened()
        assertEqual(0, #shownButtons(picker))
        assertTrue(picker.empty:IsShown())
        assertEqual("Nothing else in your bags can be sold.", picker.empty:GetText())
    end)

    it("is headed with what a click does, under the junk list", function()
        local ns, env = loggedIn()
        helpers.command(env, "junk 117")
        local panel = ns.SettingsPanel
        panel.panel:Show()

        assertEqual("In your bags (click to always sell)", panel.bagsHeading:GetText())
        local point = panel.bagsHeading.points[#panel.bagsHeading.points]
        assertEqual(panel.junkRows[1].frame, point[2])
        assertEqual("BOTTOMLEFT", point[3])
        assertEqual(-12, point[5])
        assertEqual(panel.bagsHeading, ns.Picker.frame.points[1][2])
    end)
end)

describe("clicking a bag icon", function()
    it("puts the item on the junk list and takes it off the grid", function()
        local ns, env = loggedIn()
        helpers.put(env, 0, 1, 2589)
        ns.SettingsPanel.panel:Show()

        click(shownButtons(ns.Picker)[1])

        assertTrue(ns.Junk.Has(2589))
        assertMatch("Selling %[Linen Cloth%] at every merchant%.", helpers.printed(env))
        assertEqual(0, #shownButtons(ns.Picker))
        assertEqual("Linen Cloth", ns.SettingsPanel.junkRows[1].label:GetText())
    end)

    it("adds what the button holds now, after the grid has moved up", function()
        local ns, env = loggedIn()
        helpers.put(env, 0, 1, 2589) -- Linen Cloth
        helpers.put(env, 0, 2, 117) -- Tough Jerky
        ns.SettingsPanel.panel:Show()
        local first = shownButtons(ns.Picker)[1]

        click(first)
        assertEqual(117, first.itemID, "the next item moved into its place")
        click(first)

        assertTrue(ns.Junk.Has(2589))
        assertTrue(ns.Junk.Has(117))
    end)
end)

describe("hovering a bag icon", function()
    it("shows the item's tooltip, and hides it after", function()
        local ns, env = loggedIn()
        helpers.put(env, 0, 1, 2589)
        ns.SettingsPanel.panel:Show()
        local button = shownButtons(ns.Picker)[1]

        button.scripts.OnEnter(button)
        assertEqual(2589, env.GameTooltip.itemID)
        assertEqual(button, env.GameTooltip.owner)
        assertTrue(env.GameTooltip:IsShown())

        button.scripts.OnLeave(button)
        assertFalse(env.GameTooltip:IsShown())
    end)
end)

describe("the bag grid and the bags", function()
    it("follows the bags while the page is open", function()
        local ns, env = opened()
        helpers.put(env, 0, 4, 117)

        helpers.fire(env, "BAG_UPDATE_DELAYED")

        local buttons = shownButtons(ns.Picker)
        assertEqual(1, #buttons)
        assertEqual(117, buttons[1].itemID)
    end)

    it("does no work for bag changes while the page is closed", function()
        local ns, env = opened()
        ns.SettingsPanel.panel:Hide()
        local reads = 0
        local sellable = ns.Bags.Sellable
        ns.Bags.Sellable = function(...)
            reads = reads + 1
            return sellable(...)
        end

        helpers.fire(env, "BAG_UPDATE_DELAYED")

        assertEqual(0, reads)
    end)

    it("shows an item once the client has described it", function()
        local ns, env = loggedIn()
        env.__uncached[2589] = true
        helpers.put(env, 0, 1, 2589)
        ns.SettingsPanel.panel:Show()
        assertEqual(0, #shownButtons(ns.Picker))

        env.__uncached[2589] = nil
        helpers.fire(env, "BAG_UPDATE_DELAYED")

        assertEqual(1, #shownButtons(ns.Picker))
    end)

    it("wraps to a new row after ten icons, and the page grows with it", function()
        local ns, env = loggedIn()
        manyItems(env, 10)
        ns.SettingsPanel.panel:Show()
        local ten = ns.SettingsPanel.content:GetHeight()

        manyItems(env, 11)
        helpers.fire(env, "BAG_UPDATE_DELAYED")

        local buttons = shownButtons(ns.Picker)
        assertEqual(11, #buttons)
        local point = buttons[11].points[#buttons[11].points]
        assertEqual(ns.Picker.frame, point[2])
        assertEqual(0, point[4])
        assertEqual(-36, point[5])
        assertEqual(36, ns.SettingsPanel.content:GetHeight() - ten)
    end)
end)
