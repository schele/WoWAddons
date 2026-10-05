local helpers = require("helpers")

local Codec = helpers.loadPure("Codec.lua").Codec
local points = helpers.points

local function same(expected, actual)
    assertEqual(#expected, #actual, "number of points")
    for n = 1, #expected do
        assertEqual(expected[n][1], actual[n][1], "tab of point " .. n)
        assertEqual(expected[n][2], actual[n][2], "talent of point " .. n)
    end
end

describe("exporting a plan", function()
    it("writes TP1, the class, and two characters a point", function()
        assertEqual("TP1:DRUID:212213", Codec.Encode("DRUID", points("2.1", "2.2", "1.3")))
    end)

    it("writes talents past 9 in base 36", function()
        assertEqual("TP1:DRUID:2a1z", Codec.Encode("DRUID", points("2.10", "1.35")))
    end)

    it("writes an empty plan", function()
        assertEqual("TP1:DRUID:", Codec.Encode("DRUID", {}))
    end)

    it("refuses a talent past 35, which two characters cannot hold", function()
        local text, why = Codec.Encode("DRUID", points("2.36"))
        assertNil(text)
        assertMatch("36", why)
    end)
end)

describe("importing a plan", function()
    it("reads back what was written", function()
        local plan = points("2.1x5", "2.10", "1.35", "3.4")
        local decoded = Codec.Decode(Codec.Encode("DRUID", plan))
        assertEqual("DRUID", decoded.class)
        same(plan, decoded.points)
    end)

    it("trims and accepts either case", function()
        local decoded = Codec.Decode("  tp1:druid:2A2b\n")
        assertEqual("DRUID", decoded.class)
        same(points("2.10", "2.11"), decoded.points)
    end)

    it("reads an empty plan", function()
        local decoded = Codec.Decode("TP1:MAGE:")
        assertEqual("MAGE", decoded.class)
        assertEqual(0, #decoded.points)
    end)

    it("refuses what is not a TalentPlanner string", function()
        for _, text in ipairs({ "", "hello", "TP2:DRUID:21", "TP1::21", "TP1:DRUID:2-", "https://example.com/talent-calc", 42 }) do
            local decoded, why = Codec.Decode(text)
            assertNil(decoded, tostring(text))
            assertEqual("Not a TalentPlanner string.", why)
        end
    end)

    it("refuses points cut short", function()
        local decoded, why = Codec.Decode("TP1:DRUID:212")
        assertNil(decoded)
        assertEqual("The points are cut short.", why)
    end)

    it("refuses a fourth tree, naming the point", function()
        local decoded, why = Codec.Decode("TP1:DRUID:2141")
        assertNil(decoded)
        assertEqual("Point 2 names tree 4; there are three.", why)
    end)

    it("refuses talent 0", function()
        local decoded, why = Codec.Decode("TP1:DRUID:20")
        assertNil(decoded)
        assertEqual("Point 1 names talent 0.", why)
    end)
end)
