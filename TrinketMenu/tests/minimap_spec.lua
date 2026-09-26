local helpers = require("helpers")

-- Logged in with a minimap on screen, which the stub does not have, and
-- what is printed kept.
local function withMinimap()
    local ns, env = helpers.loadAddon()
    env.Minimap = env.CreateFrame("Frame", nil, env.UIParent)
    env.Minimap:SetSize(140, 140)
    env.__said = {}
    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        table.insert(env.__said, table.concat(parts, " "))
    end
    helpers.login(ns, env)
    return ns, env
end

describe("the minimap button's geometry", function()
    local ns = helpers.loadAddon()

    it("puts angle 0 to the right and 90 at the top", function()
        local x, y = ns.MinimapButton.PositionFor(0, 80)
        assertNear(80, x)
        assertNear(0, y)
        x, y = ns.MinimapButton.PositionFor(90, 80)
        assertNear(0, x)
        assertNear(80, y)
    end)

    it("turns a cursor offset back into an angle between 0 and 360", function()
        assertNear(0, ns.MinimapButton.AngleFor(10, 0))
        assertNear(90, ns.MinimapButton.AngleFor(0, 10))
        assertNear(225, ns.MinimapButton.AngleFor(-10, -10))
    end)
end)

describe("the minimap button", function()
    it("sits on the minimap at its own angle, with TrinketMenu's own icon", function()
        local ns, env = withMinimap()
        local button = ns.MinimapButton.Button()
        assertEqual(env.Minimap, button:GetParent())
        assertEqual(275, ns.db.minimap.angle)
        assertEqual("Interface\\AddOns\\TrinketMenu\\logo", button.icon:GetTexture())
    end)

    it("opens the settings on a click", function()
        local ns = withMinimap()
        local opened = 0
        ns.OpenSettings = function() opened = opened + 1 end
        local button = ns.MinimapButton.Button()
        button.scripts.OnClick(button, "LeftButton")
        assertEqual(1, opened)
    end)

    it("hides and shows with /tm minimap, says so, and remembers", function()
        local ns, env = withMinimap()
        helpers.command(env, "minimap")
        assertFalse(ns.MinimapButton.Button():IsShown())
        assertTrue(ns.db.minimap.hide)
        assertMatch("/tm minimap brings it back", table.concat(env.__said, "\n"))
        helpers.command(env, "minimap")
        assertTrue(ns.MinimapButton.Button():IsShown())
    end)
end)
