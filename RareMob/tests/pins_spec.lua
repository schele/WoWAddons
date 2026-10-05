local helpers = require("helpers")

local NOW = 1790000000
local DAY = 86400

local function texts(lines)
    local list = {}
    for _, line in ipairs(lines) do list[#list + 1] = line.text end
    return table.concat(list, " | ")
end

--- A pin on the minimap showing rare `id`.
local function pinFor(ns, env, id)
    local pool = ns.Pins.Pool(env.Minimap)
    pool:Begin()
    local pin = pool:Acquire()
    ns.Pins.Set(pin, { id = id, x = 0, y = 0, sighting = false }, 14)
    pool:Finish()
    return pin, pool
end

describe("a pin", function()
    it("is a skull, bright for a rare seen on WoW Forever", function()
        local ns, env = helpers.loggedIn(function(env, ns)
            ns.AddRecordings("other", { [462] = helpers.sighting("Vultros", 26, NOW) })
        end)
        local pin = pinFor(ns, env, 462)
        assertEqual("Interface\\AddOns\\RareMob\\minimap", pin.icon:GetTexture())
        assertFalse(pin.icon.desaturated)
        assertEqual(1, pin:GetAlpha())
        assertEqual(14, pin:GetWidth())
        assertFalse(pin.edge:IsShown(), "not the player's own sighting")
    end)

    it("is dimmed for a rare only in the database", function()
        local ns, env = helpers.loggedIn()
        local pin = pinFor(ns, env, 462)
        assertTrue(pin.icon.desaturated)
        assertTrue(pin:GetAlpha() < 1)
    end)

    it("has a gold edge for the player's own sighting", function()
        local ns, env = helpers.loggedIn(helpers.withSightings({ [462] = helpers.sighting("Vultros", 26, NOW) }))
        local pin = pinFor(ns, env, 462)
        assertTrue(pin.edge:IsShown())
        assertEqual(1, pin.edge.color[1])
        assertEqual(0.82, pin.edge.color[2])
    end)

    it("pulses while its rare is near, and stops when it is gone", function()
        local ns, env = helpers.loggedIn()
        env.__units.target = env.__creature(462, "Vultros", 26, "rare")
        helpers.fire(env, "PLAYER_TARGET_CHANGED")
        local pin = pinFor(ns, env, 462)
        assertTrue(pin.pulsing)
        assertTrue(pin.glow:IsShown())
        ns.Pins.Animate(0.2)
        local first = pin.glow:GetAlpha()
        ns.Pins.Animate(0.5)
        assertTrue(first ~= pin.glow:GetAlpha(), "the glow's strength changes over time")

        env.__units.target = nil
        env.__now = env.__now + 31
        ns.Spotter.Tick()
        pin = pinFor(ns, env, 462)
        assertFalse(pin.pulsing)
        assertFalse(pin.glow:IsShown())
    end)

    it("glows steadily when its rare is the one picked in the list", function()
        local ns, env = helpers.loggedIn()
        ns.Pins.highlight = 462
        local pin = pinFor(ns, env, 462)
        assertTrue(pin.glow:IsShown())
        assertFalse(pin.pulsing)
        pin = pinFor(ns, env, 520)
        assertFalse(pin.glow:IsShown())
    end)

    it("lets a left click through to the map", function()
        local ns, env = helpers.loggedIn()
        local pin = pinFor(ns, env, 462)
        assertEqual("LeftButton", pin.passThrough[1])
    end)
end)

describe("a pin's tooltip", function()
    it("for a rare seen: name, level, kind, when, and that WoW Forever has it", function()
        local ns, env = helpers.loggedIn(function(env, ns)
            ns.AddRecordings("other", { [462] = helpers.sighting("Vultros", 26, NOW - 3 * DAY) })
        end)
        assertEqual("Vultros | Level 26 | Rare | Last seen 3 days ago | Seen on WoW Forever",
            texts(ns.Pins.TooltipLines(462)))
    end)

    it("for a rare only in the database: a level range, rare elite, not seen yet", function()
        local ns = helpers.loggedIn()
        assertEqual("Elite Rare | Level 40-42 | Rare elite | From the classic database, not seen on WoW Forever yet",
            texts(ns.Pins.TooltipLines(1)))
    end)

    it("shows on hover and goes on leaving", function()
        local ns, env = helpers.loggedIn()
        local pin = pinFor(ns, env, 462)
        pin.scripts.OnEnter(pin)
        assertEqual("Vultros", env.GameTooltip.text)
        assertEqual(pin, env.GameTooltip:GetOwner())
        assertEqual(3, #env.GameTooltip.lines)
        pin.scripts.OnLeave(pin)
        assertFalse(env.GameTooltip:IsShown())
    end)
end)

describe("a pool of pins", function()
    it("hides the pins not handed out this time", function()
        local ns, env = helpers.loggedIn()
        local pool = ns.Pins.Pool(env.Minimap)
        pool:Begin()
        ns.Pins.Set(pool:Acquire(), { id = 462, x = 0, y = 0 }, 14)
        ns.Pins.Set(pool:Acquire(), { id = 520, x = 0, y = 0 }, 14)
        pool:Finish()
        pool:Begin()
        ns.Pins.Set(pool:Acquire(), { id = 462, x = 0, y = 0 }, 14)
        pool:Finish()
        assertEqual(1, #pool:Shown())
        assertFalse(pool.pins[2]:IsShown())
    end)
end)
