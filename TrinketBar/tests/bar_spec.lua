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
        -- away from running it. All four attributes, not just the left-click
        -- pair: a regression that cleared only those would leave a hidden
        -- button whose right-click still fires a stale macro.
        local ns, env = carrying({ "Hand of Justice", "Kiss of the Spider" })
        ns.Bar.Apply()

        env.__bags[0][2] = nil
        ns.Bar.Apply()

        local attrs = helpers.attrs(ns.Bar.Buttons()[2])
        assertNil(attrs.type1)
        assertNil(attrs.macrotext1)
        assertNil(attrs.type2)
        assertNil(attrs.macrotext2)
    end)

    it("keeps an apostrophe intact in the macro text", function()
        -- Real trinket names carry apostrophes -- Hakkar's Blood is one --
        -- and the macro is built by string concatenation, not escaping, so
        -- this is a case worth pinning down rather than assuming.
        local ns = carrying({ "Hakkar's Blood" })
        ns.Bar.Apply()

        assertEqual("/equipslot 13 Hakkar's Blood",
            helpers.attrs(ns.Bar.Buttons()[1]).macrotext1)
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

describe("laying the buttons out", function()
    local function carrying(count)
        local names = {}
        for index = 1, count do
            names[index] = string.format("Trinket %02d", index)
        end

        return loggedIn(function(_, env)
            for index, name in ipairs(names) do
                env.__carry(0, index, name)
            end
        end)
    end

    it("puts them in a row, left to right", function()
        local ns = carrying(3)
        ns.Bar.Apply()

        -- Fourth and fifth returns, not second: buttons are anchored to the
        -- bar with the explicit five-argument SetPoint (point, relativeTo,
        -- relativePoint, x, y), the same as the wrap test below reads. The
        -- second return is the relativeTo frame, not an offset -- reading it
        -- as one instead compares two frames and proves nothing about order.
        local _, _, _, firstX = ns.Bar.Buttons()[1]:GetPoint()
        local _, _, _, secondX = ns.Bar.Buttons()[2]:GetPoint()

        assertTrue(secondX > firstX)
    end)

    it("wraps onto a second row past the configured width", function()
        -- Sixteen in a line is wider than most screens.
        local ns = carrying(3)
        ns.db.bar.perRow = 2
        ns.Bar.Apply()

        local _, _, _, secondX, secondY = ns.Bar.Buttons()[2]:GetPoint()
        local _, _, _, thirdX, thirdY = ns.Bar.Buttons()[3]:GetPoint()

        assertTrue(thirdY < secondY, "the third button dropped a row")
        assertTrue(thirdX < secondX, "and went back to the left")
    end)

    it("sizes the buttons to the setting", function()
        local ns = carrying(1)
        ns.db.bar.iconSize = 40
        ns.Bar.Apply()

        assertEqual(40, ns.Bar.Buttons()[1]:GetWidth())
    end)

    it("sizes the anchor to the buttons it is actually holding", function()
        -- The anchor is the drag handle as well as the backdrop, so one
        -- sized for sixteen buttons would be a strip of empty air to grab.
        --
        -- Exact width, not a range: a two-sided inequality would still pass
        -- if the column count were off by one. BUTTON_GAP is not exposed by
        -- Bar.lua, so 4 here is that file's own BUTTON_GAP, written in by
        -- hand.
        local ns = carrying(2)
        ns.db.bar.perRow = 8
        ns.Bar.Apply()

        local gap = 4
        local buttonWidth = ns.Bar.Buttons()[1]:GetWidth()
        local width = ns.Bar.Anchor():GetWidth()

        assertEqual(2 * buttonWidth + 1 * gap, width)
    end)
end)

describe("the anchor", function()
    it("starts where the database says", function()
        local ns = loggedIn()
        assertEqual("CENTER", ns.db.anchor.point)
    end)

    it("takes the mouse and registers for the drag that would ever call OnDragStart", function()
        -- Every drag test below proves the handler's logic by calling
        -- OnDragStart/OnDragStop directly, which is the only way to test a
        -- handler -- but it never asks whether the client would call it at
        -- all. Deleting EnableMouse(true) or RegisterForDrag("LeftButton")
        -- leaves a bar that looks right and cannot be grabbed, and the
        -- suite would not notice without these two assertions.
        local ns = loggedIn()
        local anchor = ns.Bar.Anchor()

        assertTrue(anchor.mouseEnabled, "or nothing can grab it")

        local registered = {}
        for _, click in ipairs(anchor.dragRegistered or {}) do
            registered[click] = true
        end
        assertTrue(registered.LeftButton, "or the client never calls OnDragStart")
    end)

    it("does not move while locked", function()
        local ns = loggedIn()
        ns.db.bar.locked = true

        local frame = ns.Bar.Anchor()
        frame.scripts.OnDragStart(frame)

        assertFalse(frame.moving == true, "a locked bar stays put")
    end)

    it("moves while unlocked", function()
        local ns = loggedIn()
        ns.db.bar.locked = false

        local frame = ns.Bar.Anchor()
        frame.scripts.OnDragStart(frame)

        assertTrue(frame.moving)
    end)

    it("refuses to start moving in combat, and says why", function()
        -- Moving the anchor moves every secure button hanging off it.
        local ns, env = loggedIn()
        env.__setCombat(true)

        local frame = ns.Bar.Anchor()
        frame.scripts.OnDragStart(frame)

        assertFalse(frame.moving == true)
        assertMatch("combat", helpers.printed(env))
    end)

    it("lets the drag end safely if combat starts before the mouse is released", function()
        -- A drag can start out of combat and still be running when a mob
        -- pulls -- the release then runs on a frame every secure button
        -- hangs off. The release must never raise, and must not move the
        -- bar or write its position until combat actually ends.
        local ns, env = loggedIn()
        local frame = ns.Bar.Anchor()

        frame.scripts.OnDragStart(frame)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 200, -60)

        env.__setCombat(true)

        local ok = pcall(frame.scripts.OnDragStop, frame)
        assertTrue(ok, "the release itself must never raise")
        assertFalse(ns.db.anchor.x == 200, "not saved yet -- combat is still on")
        assertMatch("combat", helpers.printed(env))

        env.__setCombat(false)

        assertEqual(200, ns.db.anchor.x, "saved the instant combat ends")
        assertEqual(-60, ns.db.anchor.y)
    end)

    it("remembers where it was dropped", function()
        local ns, env = loggedIn()
        local frame = ns.Bar.Anchor()

        frame.scripts.OnDragStart(frame)
        frame:ClearAllPoints()
        -- The five-argument form, because that is what the client hands
        -- back from GetPoint after a real drag, and OnDragStop reads the
        -- fourth and fifth returns. A three-argument point would leave the
        -- offsets nil and the test would be proving nothing.
        frame:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 120, -40)
        frame.scripts.OnDragStop(frame)

        assertEqual("TOPLEFT", ns.db.anchor.point)
        assertEqual(120, ns.db.anchor.x)
    end)

    it("toggles the lock on /tb lock", function()
        local ns, env = loggedIn()
        assertFalse(ns.db.bar.locked)

        helpers.command(env, "lock")
        assertTrue(ns.db.bar.locked)
    end)

    it("puts the bar back in the middle on /tb reset", function()
        local ns, env = loggedIn()
        ns.db.anchor.point = "TOPLEFT"
        ns.db.anchor.x = 400

        helpers.command(env, "reset")

        assertEqual("CENTER", ns.db.anchor.point)
        assertEqual(0, ns.db.anchor.x)
    end)

    it("defers /tb reset in combat instead of moving the anchor", function()
        -- Moving the anchor moves every secure button hanging off it, so
        -- reset has to wait the same as a drag would.
        local ns, env = loggedIn()
        local frame = ns.Bar.Anchor()

        -- Put the anchor somewhere other than the default first, the same
        -- way a real drag would, so a reset that actually moved it would be
        -- visible in GetPoint rather than accidentally matching the target.
        frame.scripts.OnDragStart(frame)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 120, -40)
        frame.scripts.OnDragStop(frame)

        env.__setCombat(true)
        helpers.command(env, "reset")

        local point, _, _, x, y = frame:GetPoint()
        assertEqual("TOPLEFT", point, "the anchor did not move")
        assertEqual(120, x)
        assertEqual(-40, y)
        assertTrue(ns.Bar.Pending())
        assertMatch("combat", helpers.printed(env))
    end)
end)

describe("what a button looks like", function()
    local function carrying(names, before)
        return loggedIn(function(ns, env)
            for index, name in ipairs(names) do
                env.__carry(0, index, name)
            end
            if before then before(ns, env) end
        end)
    end

    it("shows the trinket's own icon", function()
        local ns = carrying({ "Hand of Justice" })
        ns.Bar.Apply()

        assertEqual(133308, ns.Bar.Buttons()[1].icon:GetTexture())
        assertTrue(ns.Bar.Buttons()[1].icon:IsShown())
    end)

    it("marks the ones being worn", function()
        -- Without this the bar says what could go on but not what is on,
        -- and the swap is blind.
        local ns = carrying({ "Hand of Justice" }, function(_, env)
            env.__wear(13, "Mark of the Chosen")
        end)
        ns.Bar.Apply()

        local buttons = ns.Bar.Buttons()

        -- "Hand of Justice" sorts before "Mark of the Chosen".
        assertFalse(buttons[1].worn:IsShown(), "carried, not worn")
        assertTrue(buttons[2].worn:IsShown(), "worn")
    end)

    it("stops marking one that has just come off", function()
        local ns, env = carrying({ "Hand of Justice" }, function(_, e)
            e.__wear(13, "Hand of Justice")
        end)
        ns.Bar.Apply()
        assertTrue(ns.Bar.Buttons()[1].worn:IsShown())

        env.__worn[13] = nil
        ns.Bar.Apply()

        assertFalse(ns.Bar.Buttons()[1].worn:IsShown())
    end)

    it("takes the mouse, or it shows no hover and takes no click", function()
        -- A Button made without a template does not arrive mouse-enabled,
        -- and one that is not looks entirely correct otherwise: right size,
        -- right place, right icon, and inert.
        local ns = loggedIn()
        assertTrue(ns.Bar.Buttons()[1].mouseEnabled)
    end)

    it("puts the hover art in the layer the client shows on mouseover", function()
        -- HIGHLIGHT is not decoration here: the client shows and hides that
        -- layer on mouseover by itself, so the layer is the whole of how a
        -- hover effect works.
        local ns = loggedIn()

        local found = false
        for _, child in ipairs(ns.Bar.Buttons()[1].children) do
            if child.drawLayer == "HIGHLIGHT" then
                found = true
            end
        end

        assertTrue(found, "something is drawn in the highlight layer")
    end)

    it("draws the cooldown the client reports", function()
        local ns, env = carrying({ "Hand of Justice" })
        ns.Bar.Apply()
        env.__cooldowns["bag:0:1"] = { start = 100, duration = 120 }

        ns.Bar.RefreshCooldowns()

        local start, duration = ns.Bar.Buttons()[1].cooldown:GetCooldownTimes()
        assertEqual(100, start)
        assertEqual(120, duration)
    end)

    it("clears a sweep that has finished rather than leaving it frozen", function()
        local ns, env = carrying({ "Hand of Justice" })
        ns.Bar.Apply()
        env.__cooldowns["bag:0:1"] = { start = 100, duration = 120 }
        ns.Bar.RefreshCooldowns()

        env.__cooldowns["bag:0:1"] = nil
        ns.Bar.RefreshCooldowns()

        local _, duration = ns.Bar.Buttons()[1].cooldown:GetCooldownTimes()
        assertEqual(0, duration)
    end)

    it("still builds a working button when the client has no cooldown template", function()
        -- The sweep is decoration; equipping is the point. An unknown
        -- template raises rather than returning nil.
        local ns, env = helpers.loadAddon(FILES)
        env.__missingTemplates["CooldownFrameTemplate"] = true
        helpers.login(ns, env)
        env.__carry(0, 1, "Hand of Justice")
        ns.Bar.Apply()

        assertNil(ns.Bar.Buttons()[1].cooldown)
        assertEqual("/equipslot 13 Hand of Justice",
            helpers.attrs(ns.Bar.Buttons()[1]).macrotext1)

        local ok = pcall(ns.Bar.RefreshCooldowns)
        assertTrue(ok, "and refreshing must not trip over its absence")
    end)

    it("redraws the sweeps when the client says a cooldown started", function()
        local ns, env = carrying({ "Hand of Justice" })
        ns.Bar.Apply()
        env.__cooldowns["bag:0:1"] = { start = 100, duration = 120 }

        helpers.fire(env, "BAG_UPDATE_COOLDOWN")

        local _, duration = ns.Bar.Buttons()[1].cooldown:GetCooldownTimes()
        assertEqual(120, duration)
    end)

    it("re-resolves a carried trinket's coordinates by name, not the bag slot Apply last saw", function()
        -- Click the button mid-fight: /equipslot pulls the trinket out of
        -- its bag slot and the trinket that comes off lands in that same
        -- slot. PLAYER_EQUIPMENT_CHANGED fires, but Apply is held by
        -- combat, so button.entry still says the old bag coordinates even
        -- though a different item sits there now. If RefreshCooldowns
        -- trusts those stale coordinates, it paints the new occupant's
        -- cooldown on a button whose macro still names the old trinket.
        local ns, env = carrying({ "Old Trinket" })
        ns.Bar.Apply()

        env.__setCombat(true)

        -- The equip: "Old Trinket" is now worn in slot 13, and whatever it
        -- displaced -- "New Occupant" -- is sitting in the bag slot Apply
        -- last recorded for button 1.
        env.__wear(13, "Old Trinket")
        env.__carry(0, 1, "New Occupant")

        -- The occupant's cooldown, at the stale coordinates button.entry
        -- still points at -- must not end up on button 1's sweep.
        env.__cooldowns["bag:0:1"] = { start = 999, duration = 999 }
        -- The trinket's own, correct cooldown, now that it is worn.
        env.__cooldowns["worn:13"] = { start = 500, duration = 30 }

        helpers.fire(env, "BAG_UPDATE_COOLDOWN")

        local start, duration = ns.Bar.Buttons()[1].cooldown:GetCooldownTimes()
        assertEqual(500, start, "the trinket's own cooldown, not the new occupant's")
        assertEqual(30, duration)

        -- The macro must still name the original trinket: only the
        -- cooldown lookup is re-resolved, never the secure attribute.
        assertEqual("/equipslot 13 Old Trinket",
            helpers.attrs(ns.Bar.Buttons()[1]).macrotext1)
    end)
end)
