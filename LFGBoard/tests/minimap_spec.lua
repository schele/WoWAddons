local helpers = require("helpers")

describe("the minimap button's geometry", function()
    it("puts angle 0 to the right and 90 at the top", function()
        local ns = helpers.loadAddon()

        local x, y = ns.MinimapButton.PositionFor(0, 80)
        assertNear(80, x)
        assertNear(0, y)
        x, y = ns.MinimapButton.PositionFor(90, 80)
        assertNear(0, x)
        assertNear(80, y)
    end)

    it("turns a cursor offset back into an angle between 0 and 360", function()
        local ns = helpers.loadAddon()

        assertNear(0, ns.MinimapButton.AngleFor(10, 0))
        assertNear(90, ns.MinimapButton.AngleFor(0, 10))
        assertNear(225, ns.MinimapButton.AngleFor(-10, -10))
    end)
end)

describe("the minimap button", function()
    it("sits on the minimap at its own angle, clear of the other addons'", function()
        local ns, env = helpers.loggedIn()

        local button = ns.MinimapButton.Button()

        assertEqual(env.Minimap, button:GetParent())
        assertEqual(125, ns.db.minimap.angle)
        assertEqual("Interface\\AddOns\\LFGBoard\\minimap", button.icon:GetTexture())
    end)

    it("opens and closes the board on a click", function()
        local ns = helpers.loggedIn()
        local button = ns.MinimapButton.Button()

        button:Click()
        assertTrue(ns.Window.Frame():IsShown())

        button:Click()
        assertFalse(ns.Window.Frame():IsShown())
    end)

    it("hides and shows with /lfgb minimap, and remembers", function()
        local ns, env = helpers.loggedIn()

        helpers.command(env, "minimap")
        assertFalse(ns.MinimapButton.Button():IsShown())
        assertTrue(ns.db.minimap.hide)

        helpers.command(env, "minimap")
        assertTrue(ns.MinimapButton.Button():IsShown())
    end)
end)
