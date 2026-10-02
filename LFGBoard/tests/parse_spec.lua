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

    it("give the ids of the quests linked, in the order they are said", function()
        local got = parse("LF2M |cffffff00|Hquest:155:18|h[The Defias Brotherhood]|h|r and "
            .. "|cffffff00|Hquest:166:22|h[The Defias Brotherhood]|h|r")

        assertEqual(2, #got.quests)
        assertEqual(155, got.quests[1])
        assertEqual(166, got.quests[2])
    end)

    it("give no quest ids for a quest named only in words", function()
        assertNil(parse("LF2M quest Hogger").quests)
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

describe("how many are in a group", function()
    it("works out a group of five from the places it asks to fill", function()
        local cases = {
            ["LF1M DM need heals"] = 4,
            ["LF1 WC healer"] = 4,
            ["LF 2M SFK"] = 3,
            ["LFM DM need 1 more dps"] = 4,
            ["LFM SFK need one more"] = 4,
            ["looking for 2 more WC"] = 3,
            ["LF3M quest Hogger"] = 2,
        }
        for text, have in pairs(cases) do
            local got = parse(text)
            assertEqual(have, got.size and got.size.have, text)
            assertEqual(5, got.size and got.size.of, text)
        end
    end)

    it("takes 3/5 and 35/40 as written", function()
        assertEqual(3, parse("LFM quest Hogger 3/5 need dps").size.have)
        assertEqual(35, parse("LFM MC 35/40 need heals").size.have)
    end)

    it("gives no count for a raid unless it is written out", function()
        assertNil(parse("LF2M MC need heals").size)
        assertNil(parse("LFM ZG need 1 more").size)
    end)

    it("gives no count for a group the board cannot place, which may be a raid", function()
        assertNil(parse("LF2M Hogger need tank").size)
    end)

    it("does not take any two numbers with a slash for a size", function()
        assertNil(parse("LFM DM 1/2 price on summons").size)
        assertNil(parse("LFM DM 6/5 need tank").size)
    end)

    it("does not count a place asked for in an item's name", function()
        assertNil(parse("LFM DM |cff1eff00|Hitem:7110::::::::20:::::::|h[LF1M Robe]|h|r").size)
    end)
end)

describe("the roles a group asks for, said simply", function()
    it("are read from LF1M healer, need tank and LF dps", function()
        assertTrue(parse("LF1M healer DM").roles.healer)
        assertTrue(parse("LFM SFK need tank").roles.tank)
        assertTrue(parse("LF dps WC").roles.dps)
        assertTrue(parse("LF1M quest Hogger need heals").roles.healer)
    end)
end)

describe("the classes a group asks for", function()
    local function wants(text)
        local got = parse(text)
        return got and got.wantClasses or {}
    end

    it("are read from LF hunter, need a priest and LF1M mage", function()
        assertTrue(wants("LFM DM LF hunter").HUNTER)
        assertTrue(wants("LFM SFK need a priest").PRIEST)
        assertTrue(wants("LF1M mage WC").MAGE)
        assertTrue(wants("LF1M DM mage").MAGE)
    end)

    it("are read from plurals and the short names people type", function()
        local cases = {
            ["LFM DM need hunters"] = "HUNTER", ["LF1M DM need hunt"] = "HUNTER",
            ["LF1M SFK need lock"] = "WARLOCK", ["LF1M SFK need pally"] = "PALADIN",
            ["LF1M SFK need rogue"] = "ROGUE", ["LF1M SFK need sham"] = "SHAMAN",
            ["LF1M SFK need druid"] = "DRUID", ["LF1M SFK need warr"] = "WARRIOR",
            ["LF1M SFK need warlocks"] = "WARLOCK", ["LF2M SFK need mages"] = "MAGE",
        }
        for text, class in pairs(cases) do
            assertTrue(wants(text)[class], text)
        end
    end)

    it("are read from a list of them", function()
        local got = wants("LF1M DM need healer, priest or druid")
        assertTrue(got.PRIEST)
        assertTrue(got.DRUID)
    end)

    it("are read by the game's own name for the class", function()
        local ns, env = helpers.loadAddon(nil, function(env)
            env.LOCALIZED_CLASS_NAMES_MALE = { WARLOCK = "Hexenmeister" }
        end)
        assertTrue(ns.Parse.Message("LF1M DM need Hexenmeister").wantClasses.WARLOCK)
    end)

    it("leave out the poster's own class, said before what they look for", function()
        assertNil(parse("Mage LF2M SFK need tank").wantClasses)
    end)

    it("leave out the classes a group says it has", function()
        assertNil(parse("LF1M DM have hunter need heals").wantClasses)
        assertNil(parse("LF1M DM, hunter and priest in group").wantClasses)
    end)

    it("are not read from a link's name", function()
        assertNil(parse("LF2M |cffffff00|Hquest:155:18|h[Hunter's Charm]|h|r").wantClasses)
        assertNil(parse("LFM DM need |cff1eff00|Hitem:7110::::::::20:::::::|h[Priest's Robe]|h|r").wantClasses)
    end)

    it("are not read from a quest named in words", function()
        assertNil(parse("LF2M quest The Hunter's Way").wantClasses)
    end)
end)

describe("the classes a group turns away", function()
    local function refuses(text)
        local got = parse(text)
        return got and got.refuseClasses or {}
    end

    it("are read from no hunters, no more hunters and hunters full", function()
        assertTrue(refuses("LF2M DM no hunters").HUNTER)
        assertTrue(refuses("LF2M DM need dps no more hunters").HUNTER)
        assertTrue(refuses("LF2M DM hunters full").HUNTER)
        assertTrue(refuses("LF2M DM need dps, rogue full").ROGUE)
    end)

    it("are not asked for as well", function()
        local got = parse("LF2M DM need dps no hunters")
        assertNil(got.wantClasses)
        assertTrue(got.refuseClasses.HUNTER)
    end)

    it("are not read from a group that only has one", function()
        assertNil(parse("LF2M DM have hunter").refuseClasses)
    end)
end)
