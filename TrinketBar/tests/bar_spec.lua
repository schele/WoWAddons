local helpers = require("helpers")

local FILES = { "TrinketBar.lua", "Items.lua", "Bar.lua" }

local function loggedIn(before)
    local ns, env = helpers.loadAddon(FILES)
    if before then before(ns, env) end
    helpers.login(ns, env)
    return ns, env
end

describe("building the bar", function()
    it("builds every button the maximum allows, not just the ones in use", function()
        -- A secure button cannot be created mid-fight, so a bar that grows
        -- when a trinket is looted is a bar that cannot grow when it matters.
        local ns = loggedIn()
        assertEqual(ns.Bar.MAX_BUTTONS, #ns.Bar.Buttons())
    end)

    it("makes every button a secure action button", function()
        local ns = loggedIn()
        assertEqual("SecureActionButtonTemplate", ns.Bar.Buttons()[1].template)
    end)

    it("asks for both click edges", function()
        -- This client acts on the press where others act on the release.
        local ns = loggedIn()

        local registered = {}
        for _, click in ipairs(ns.Bar.Buttons()[1].clickRegistrations or {}) do
            registered[click] = true
        end

        assertTrue(registered.AnyDown, "the press, which is what this client acts on")
        assertTrue(registered.AnyUp)
    end)

    it("builds once, however often it is asked", function()
        local ns, env = loggedIn()
        local before = #env.__frames

        ns.Bar.Build()
        assertEqual(before, #env.__frames, "no second pool")
    end)
end)

describe("what a button is told to do", function()
    local function carrying(names)
        return loggedIn(function(_, env)
            for index, name in ipairs(names) do
                env.__carry(0, index, name)
            end
        end)
    end

    it("equips into slot 1 on the left button", function()
        local ns = carrying({ "Hand of Justice" })
        ns.Bar.Apply()

        local attrs = helpers.attrs(ns.Bar.Buttons()[1])
        assertEqual("macro", attrs.type1)
        assertEqual("/equipslot 13 Hand of Justice", attrs.macrotext1)
    end)

    it("equips into slot 2 on the right button", function()
        local ns = carrying({ "Hand of Justice" })
        ns.Bar.Apply()

        local attrs = helpers.attrs(ns.Bar.Buttons()[1])
        assertEqual("macro", attrs.type2)
        assertEqual("/equipslot 14 Hand of Justice", attrs.macrotext2)
    end)

    it("gives each trinket its own button, in name order", function()
        local ns = carrying({ "Zandalarian Hero Charm", "Hand of Justice" })
        ns.Bar.Apply()

        assertEqual("/equipslot 13 Hand of Justice",
            helpers.attrs(ns.Bar.Buttons()[1]).macrotext1)
        assertEqual("/equipslot 13 Zandalarian Hero Charm",
            helpers.attrs(ns.Bar.Buttons()[2]).macrotext1)
    end)

    it("hides the buttons it has no trinket for", function()
        -- A button that looks pressable and does nothing is the worse
        -- failure.
        local ns = carrying({ "Hand of Justice" })
        ns.Bar.Apply()

        assertTrue(ns.Bar.Buttons()[1]:IsShown())
        assertFalse(ns.Bar.Buttons()[2]:IsShown())
    end)

    it("clears the macro of a button it stops using", function()
        -- A hidden button that still carries an instruction is one keybind
        -- away from running it.
        local ns, env = carrying({ "Hand of Justice", "Kiss of the Spider" })
        ns.Bar.Apply()

        env.__bags[0][2] = nil
        ns.Bar.Apply()

        assertNil(helpers.attrs(ns.Bar.Buttons()[2]).macrotext1)
    end)

    it("shows a worn trinket too, so the bar says what is on", function()
        local ns = loggedIn(function(_, env)
            env.__wear(13, "Mark of the Chosen")
        end)
        ns.Bar.Apply()

        assertEqual("/equipslot 13 Mark of the Chosen",
            helpers.attrs(ns.Bar.Buttons()[1]).macrotext1)
    end)
end)

describe("applying in combat", function()
    it("refuses, and says so by returning false", function()
        local ns, env = loggedIn()
        env.__setCombat(true)

        assertFalse(ns.Bar.Apply())
    end)

    it("writes nothing at all", function()
        -- The client blocks this, not us. Attempting it and being refused
        -- is an error in the player's face, so we do not attempt it.
        local ns, env = loggedIn(function(_, e)
            e.__carry(0, 1, "Hand of Justice")
        end)
        ns.Bar.Apply()

        env.__setCombat(true)
        env.__carry(0, 2, "Kiss of the Spider")
        ns.Bar.Apply()

        assertNil(helpers.attrs(ns.Bar.Buttons()[2]).macrotext1,
            "the looted trinket waits")
    end)

    it("holds the change", function()
        local ns, env = loggedIn()
        env.__setCombat(true)
        ns.Bar.Apply()

        assertTrue(ns.Bar.Pending())
    end)

    it("applies it the moment combat ends", function()
        local ns, env = loggedIn()
        env.__setCombat(true)
        env.__carry(0, 1, "Hand of Justice")
        ns.Bar.Apply()

        env.__setCombat(false)

        assertEqual("/equipslot 13 Hand of Justice",
            helpers.attrs(ns.Bar.Buttons()[1]).macrotext1)
        assertFalse(ns.Bar.Pending())
    end)

    it("holds the whole build when login lands mid-fight", function()
        -- PLAYER_LOGIN genuinely can fire in combat: a /reload during a
        -- pull, or reconnecting after a disconnect.
        local ns, env = helpers.loadAddon(FILES)
        env.__setCombat(true)
        helpers.login(ns, env)

        assertEqual(0, #ns.Bar.Buttons(), "creating a secure frame is refused too")
        assertTrue(ns.Bar.Pending())

        env.__setCombat(false)
        assertEqual(ns.Bar.MAX_BUTTONS, #ns.Bar.Buttons())
    end)
end)

describe("keeping up with the bags", function()
    it("re-points the buttons when a bag changes", function()
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")

        helpers.fire(env, "BAG_UPDATE_DELAYED")

        assertEqual("/equipslot 13 Hand of Justice",
            helpers.attrs(ns.Bar.Buttons()[1]).macrotext1)
    end)

    it("re-points when what is worn changes", function()
        local ns, env = loggedIn()
        env.__wear(14, "Mark of the Chosen")

        helpers.fire(env, "PLAYER_EQUIPMENT_CHANGED")

        assertEqual("/equipslot 13 Mark of the Chosen",
            helpers.attrs(ns.Bar.Buttons()[1]).macrotext1)
    end)

    it("re-points when the client finally learns what an item is", function()
        -- GetItemInfo answers with nothing for an item the client has not
        -- cached, so a cold-cache login can miss a trinket entirely. This
        -- event is the client saying it knows now.
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")

        helpers.fire(env, "GET_ITEM_INFO_RECEIVED")

        assertEqual("/equipslot 13 Hand of Justice",
            helpers.attrs(ns.Bar.Buttons()[1]).macrotext1)
    end)
end)
