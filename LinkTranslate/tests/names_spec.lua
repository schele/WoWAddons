local helpers = require("helpers")

describe("naming a link", function()
    it("names a quest by this client's title for it", function()
        local ns, env = helpers.loggedIn()
        env.__names.quest[2945] = "Bride of the Embalmer"
        assertEqual("Bride of the Embalmer", ns.Names.Get("quest", "2945:28"))
    end)

    it("names an item by the text of the link the client builds, suffix and all", function()
        local ns, env = helpers.loggedIn()
        env.__names.item[15210] = { "Raider Shortsword", "Raider Shortsword of the Tiger" }
        assertEqual("Raider Shortsword of the Tiger", ns.Names.Get("item", "15210:0:0:0:0:0:500:0"))
    end)

    it("names an item by its bare name when the client gives no link", function()
        local ns, env = helpers.loggedIn()
        env.C_Item.GetItemInfo = function() return "Linen Cloth" end
        assertEqual("Linen Cloth", ns.Names.Get("item", "2589::::::::"))
    end)

    it("names a spell", function()
        local ns, env = helpers.loggedIn()
        env.__names.spell[133] = "Fireball"
        assertEqual("Fireball", ns.Names.Get("spell", "133:0"))
    end)

    it("has nothing for a kind of link it does not name, and asks for nothing", function()
        local ns, env = helpers.loggedIn()
        assertNil(ns.Names.Get("player", "Tranzalorr-Firemaw:12:CHANNEL:1"))
        assertNil(ns.Names.Get("channel", "CHANNEL:1"))
        assertEqual(0, #env.__requests)
    end)

    it("has nothing for a link without an id", function()
        local ns = helpers.loggedIn()
        assertNil(ns.Names.Get("quest", "abc"))
    end)

    it("leaves an empty name alone", function()
        local ns, env = helpers.loggedIn()
        env.__names.quest[2945] = ""
        assertNil(ns.Names.Get("quest", "2945:28"))
    end)

    it("survives a client call that raises", function()
        local ns, env = helpers.loggedIn()
        env.C_Spell.GetSpellName = function() error("no") end
        assertNil(ns.Names.Get("spell", "133"))
    end)
end)

describe("a name the client has not loaded", function()
    it("is asked for, once while the load is on its way", function()
        local ns, env = helpers.loggedIn()
        assertNil(ns.Names.Get("quest", "2945:28"))
        assertNil(ns.Names.Get("quest", "2945:28"))
        assertEqual(1, #env.__requests)
        assertEqual("quest:2945", env.__requests[1])
    end)

    it("is asked for the client's way for each kind", function()
        local ns, env = helpers.loggedIn()
        ns.Names.Get("item", "19019:0")
        ns.Names.Get("spell", "133")
        assertEqual("item:19019", env.__requests[1])
        assertEqual("spell:133", env.__requests[2])
    end)

    it("tells the listeners when it arrives", function()
        local ns, env = helpers.loggedIn()
        local heard = {}
        ns.Names.OnLoaded(function(linkType, id) table.insert(heard, linkType .. ":" .. id) end)
        env.__loadable.quest[2945] = "Bride of the Embalmer"
        ns.Names.Get("quest", "2945:28")
        helpers.finishLoad(env, "quest", 2945)
        assertEqual(1, #heard)
        assertEqual("quest:2945", heard[1])
        assertEqual("Bride of the Embalmer", ns.Names.Get("quest", "2945:28"))
    end)

    it("hears an item arrive from either of the client's events", function()
        local ns, env = helpers.loggedIn()
        local heard = 0
        ns.Names.OnLoaded(function() heard = heard + 1 end)
        ns.Names.Get("item", "19019")
        helpers.fire(env, "GET_ITEM_INFO_RECEIVED", 19019, true)
        helpers.fire(env, "ITEM_DATA_LOAD_RESULT", 19019, true)
        assertEqual(1, heard, "once, by whichever comes first")
    end)

    it("tells nobody when the load fails, and can be asked for again", function()
        local ns, env = helpers.loggedIn()
        local heard = 0
        ns.Names.OnLoaded(function() heard = heard + 1 end)
        ns.Names.Get("quest", "99999")
        helpers.finishLoad(env, "quest", 99999, false)
        assertEqual(0, heard)
        ns.Names.Get("quest", "99999")
        assertEqual(2, #env.__requests)
    end)

    it("ignores loads it did not ask for", function()
        local ns, env = helpers.loggedIn()
        local heard = 0
        ns.Names.OnLoaded(function() heard = heard + 1 end)
        helpers.fire(env, "QUEST_DATA_LOAD_RESULT", 2945, true)
        assertEqual(0, heard)
    end)

    it("is not asked for on a client that cannot load quests by id", function()
        local ns, env = helpers.loggedIn(function(env)
            env.C_QuestLog = nil
        end)
        assertNil(ns.Names.Get("quest", "2945:28"))
        assertEqual(0, #env.__requests)
    end)
end)
