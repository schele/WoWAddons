local helpers = require("helpers")

local function parse(text, fromGuild)
    local ns = helpers.loadAddon()
    return ns.Parse.Message(text, fromGuild)
end

describe("a recruiting message", function()
    it("gives the dungeon, the roles and the size", function()
        local got = parse("LF2M DM need heals + dps")

        assertEqual("dungeon", got.kind)
        assertEqual("dm", got.activity.key)
        assertTrue(got.roles.healer)
        assertTrue(got.roles.dps)
        assertNil(got.roles.tank)
        assertEqual(3, got.size.have)
        assertEqual(5, got.size.of)
    end)

    it("is read in lower case with run-together abbreviations", function()
        local got = parse("lf1m sfk tank")

        assertEqual("sfk", got.activity.key)
        assertTrue(got.roles.tank)
        assertEqual(4, got.size.have)
    end)

    it("is LFM, LF more, looking for more, or LF or need with a role", function()
        for _, text in ipairs({ "LFM WC", "LF more for RFC", "looking for more SFK",
            "LF tank DM", "need heals for wc", "LF 2M DM" }) do
            local got = parse(text)
            assertTrue(got ~= nil, text)
            assertEqual("dungeon", got.kind, text)
        end
    end)

    it("leaves out the roles a group already has", function()
        local got = parse("LFM WC, have tank, need healer")

        assertTrue(got.roles.healer)
        assertNil(got.roles.tank)
    end)

    it("reads need all as every role", function()
        local got = parse("LF3M DM need all")

        assertTrue(got.roles.tank)
        assertTrue(got.roles.healer)
        assertTrue(got.roles.dps)
        assertEqual(2, got.size.have)
    end)

    it("leaves the roles and size unknown when it names none", function()
        local got = parse("LFM DM")

        assertNil(got.roles)
        assertNil(got.size)
    end)

    it("takes an explicit size as written, and a raid's only that way", function()
        assertEqual(3, parse("LFM SFK 3/5 need tank").size.have)
        assertEqual(31, parse("LFM MC 31/40 need heals").size.have)
        assertEqual(40, parse("LFM MC 31/40 need heals").size.of)
        assertNil(parse("LF2M MC").size)
    end)

    it("tells Dire Maul from the Deadmines", function()
        assertEqual("diremaul", parse("LFM DME").activity.key)
        assertEqual("dm", parse("LFM DM").activity.key)
    end)

    it("is a quest group when it says quest, elite or q and a name", function()
        assertEqual("quest", parse("LF2M quest Hogger").kind)
        assertEqual("quest", parse("lfm q defias").kind)
        assertEqual("quest", parse("LF1M elite quest").kind)
        assertNil(parse("LF2M quest Hogger").activity)
    end)

    it("is Other when it names nothing the board knows", function()
        local got = parse("LFM new dungeon Blackroot need tank")

        assertEqual("other", got.kind)
        assertTrue(got.roles.tank)
    end)

    it("is not done when it says then full", function()
        local got = parse("LF1M DM tank then full")

        assertEqual("dungeon", got.kind)
        assertNil(got.done)
    end)

    it("reads a message with an item link in it", function()
        local got = parse("LFM DM |cff1eff00|Hitem:10400::::::::20:::::::|h[Blackened Defias Leggings]|h|r need tank")

        assertEqual("dm", got.activity.key)
        assertTrue(got.roles.tank)
        assertNil(got.roles.dps)
    end)
end)

describe("a message that is not recruiting", function()
    it("is a player looking for a group, and is skipped", function()
        assertNil(parse("LFG DM"))
        assertNil(parse("lfg wc any role"))
    end)

    it("still counts when LFG comes with a need", function()
        local got = parse("LFG DM need tank")

        assertTrue(got.roles.tank)
    end)

    it("is guild recruitment in a channel, but not in guild chat", function()
        assertNil(parse("LFM <Guild> recruiting, guild bank and tabard"))
        assertEqual("dm", parse("LFM DM guild run", true).activity.key)
    end)

    it("is done when it says full, filled, nvm or no longer", function()
        for _, text in ipairs({ "full", "group full thanks", "filled", "nvm", "no longer lf" }) do
            local got = parse(text)
            assertTrue(got and got.done, text)
        end
    end)

    it("is chatter, and gives nothing", function()
        assertNil(parse("anyone selling linen?"))
        assertNil(parse("wts [Linen Cloth]"))
    end)
end)

describe("the ways people ask for a role", function()
    it("let a few words come between the ask and the role", function()
        local cases = {
            ["Need a tank for DM"] = "tank",
            ["need 1 tank for DM"] = "tank",
            ["LF 1 more dps DM"] = "dps",
            ["LF a healer for WC"] = "healer",
            ["lf 2 dps sm cath"] = "dps",
            ["need 2 dps for SFK"] = "dps",
            ["Looking for a tank for SFK"] = "tank",
            ["need a heal for wc"] = "healer",
        }
        for text, role in pairs(cases) do
            local got = parse(text)
            assertTrue(got ~= nil, text)
            assertTrue(got.roles and got.roles[role], text)
        end
    end)

    it("count a role followed by needed", function()
        local got = parse("Tank and healer needed for DM")

        assertTrue(got.roles.tank)
        assertTrue(got.roles.healer)
        assertNil(got.roles.dps)
    end)

    it("leave out the poster's own role, said before what they look for", function()
        local tank = parse("Tank LFM SFK need heals")
        assertNil(tank.roles.tank)
        assertTrue(tank.roles.healer)

        local healer = parse("Healer LF2M RFK need tank and dps")
        assertNil(healer.roles.healer)
        assertTrue(healer.roles.tank)
        assertTrue(healer.roles.dps)
    end)

    it("leave out a role the group says it has no room for", function()
        local full = parse("LF1M DM tank, dps full")
        assertTrue(full.roles.tank)
        assertNil(full.roles.dps)

        local none = parse("LFM DM no dps need heals")
        assertTrue(none.roles.healer)
        assertNil(none.roles.dps)
    end)
end)

describe("links in a message", function()
    it("do not name a dungeon or a role by their item's name", function()
        local got = parse("LFM |cff1eff00|Hitem:2236::::::::20:::::::|h[Scarlet Kris]|h|r reserved WC")
        assertEqual("wc", got.activity.key)

        local robe = parse("LFM DM |cff1eff00|Hitem:7110::::::::20:::::::|h[Healer's Robe]|h|r need tank")
        assertTrue(robe.roles.tank)
        assertNil(robe.roles.healer)
    end)

    it("make a quest group when one is a quest", function()
        local got = parse("LF2M |cffffff00|Hquest:155:18|h[The Defias Brotherhood]|h|r")

        assertEqual("quest", got.kind)
    end)
end)

describe("Trade chatter", function()
    it("is not a group without a dungeon, a quest or an LFM", function()
        for _, text in ipairs({
            "I need all the gold I can get",
            "need all mats for Lesser Mana Oil",
            "anyone need tank gear? cheap",
            "need tank boe? pst",
            "need heals? priest LFG",
            "LF more linen cloth",
            "looking for more copper ore",
        }) do
            assertNil(parse(text), text)
        end
    end)
end)
