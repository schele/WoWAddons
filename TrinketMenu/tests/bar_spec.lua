local helpers = require("helpers")

local FILES = { "TrinketMenu.lua", "Items.lua", "Bar.lua" }

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

    it("keeps the pool at sixteen, which the spec states outright", function()
        -- The test above compares MAX_BUTTONS against #Buttons(), which is
        -- self-referential and cannot catch the constant itself changing --
        -- both sides move together. Pin the literal the spec names.
        local ns = loggedIn()
        assertEqual(16, ns.Bar.MAX_BUTTONS)
    end)

    it("makes every button a secure action button", function()
        local ns = loggedIn()
        assertEqual("SecureActionButtonTemplate", ns.Bar.Buttons()[1].template)
    end)

    it("carries protection down to a button's own icon, worn marker and cooldown", function()
        -- A texture or cooldown frame created under a secure button is no
        -- less untouchable in combat than the button itself -- the real
        -- client's IsProtected() is inherited down the parent chain for
        -- exactly this reason. Without that inheritance in the fixture, an
        -- illegal combat write reachable only through one of these children
        -- (button.icon:Hide(), say, from RefreshCooldowns -- the one path
        -- deliberately allowed to run in combat) would go entirely unnoticed.
        local ns = loggedIn()
        local button = ns.Bar.Buttons()[1]

        assertTrue(button.icon:IsProtected())
        assertTrue(button.worn:IsProtected())
        assertTrue(button.cooldown:IsProtected())
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

    it("hides a button that had a trinket and lost it, not just one that never had one", function()
        -- A button that was never shown is hidden because Build() already
        -- guarantees that; the case worth proving is the transition, where
        -- a button that HAD a trinket loses it. Without the Hide() here it
        -- would stay on screen as an empty, still-clickable square.
        local ns, env = carrying({ "Hand of Justice", "Kiss of the Spider" })
        ns.Bar.Apply()
        assertTrue(ns.Bar.Buttons()[2]:IsShown())

        env.__bags[0][2] = nil
        ns.Bar.Apply()

        assertFalse(ns.Bar.Buttons()[2]:IsShown(),
            "an empty clickable square is worse than none")
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

    it("brings up the whole addon, settings panel included, when login lands mid-fight", function()
        -- The stub used to refuse every widget's combat-guarded calls, not
        -- just protected ones, which hid this: Settings.lua's panel is a
        -- plain, unprotected frame, and hiding it at login (register()
        -- calls panel:Hide()) is legal in the real client even mid-fight.
        -- The three-file test above only proves Bar.lua's own combat queue;
        -- avoiding a false refusal on the panel meant never loading
        -- Settings.lua alongside a mid-fight login at all -- so nothing
        -- covered the finished addon, all four files, logging in mid-fight.
        local ns, env = helpers.loadAddon()
        env.__setCombat(true)

        local ok = pcall(helpers.login, ns, env)

        assertTrue(ok, "logging in mid-fight must not raise")
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

    -- The backdrop ships switched off, so every test below that wants to see
    -- it has to ask. Showing is the interesting state to assert on, and a
    -- test that turned the setting on by accident would prove nothing.
    local function showingBackdrop(count)
        local ns, env = carrying(count)
        ns.db.bar.hideBackdrop = false
        ns.Bar.Apply()
        return ns, env
    end

    it("hides the backdrop while the bar is empty", function()
        -- Layout clamps the anchor to one icon (math.max(shown, 1)) so that
        -- an empty bar still leaves something to grab. That clamp is what
        -- makes hiding the backdrop necessary: without it, a player carrying
        -- no trinkets gets a bare pale square parked in the middle of the
        -- screen, holding nothing. Asserted with the setting off, or the
        -- setting alone would carry the test and the clamp rule would go
        -- unchecked.
        local ns = showingBackdrop(0)

        assertTrue(not ns.Bar.Anchor().background:IsShown(),
            "nothing to hold, so nothing to draw")
    end)

    it("shows the backdrop again once a trinket turns up", function()
        -- The other edge of the same rule: hiding on empty is only correct
        -- if picking one up brings it back, or the bar stays invisible for
        -- the rest of the session.
        local ns, env = showingBackdrop(0)

        env.__carry(0, 1, "Hand of Justice")
        ns.Bar.Apply()

        assertTrue(ns.Bar.Anchor().background:IsShown())
    end)

    it("keeps the backdrop off by default, trinkets or no trinkets", function()
        -- The setting ships on: the backdrop is an aid for placing the bar,
        -- not something to leave sitting on screen afterwards.
        local ns = carrying(2)
        ns.Bar.Apply()

        assertTrue(ns.db.bar.hideBackdrop, "on out of the box")
        assertTrue(not ns.Bar.Anchor().background:IsShown(),
            "so nothing is drawn behind a bar that is otherwise fine")
    end)

    it("draws the backdrop once the setting is turned off", function()
        local ns = showingBackdrop(2)

        assertTrue(ns.Bar.Anchor().background:IsShown())
    end)

    it("acts on the setting the moment it changes, without waiting for a bag event", function()
        -- Through SetSettingValue rather than the table, which is the path
        -- the checkbox takes: a setting whose onChange does not re-apply
        -- looks broken until the next time something else moves the bar.
        local ns = carrying(2)
        ns.Bar.Apply()

        local setting = ns.BackdropSetting
        ns.SetSettingValue(setting, false)
        assertTrue(ns.Bar.Anchor().background:IsShown(), "turned off, so drawn")

        ns.SetSettingValue(setting, true)
        assertTrue(not ns.Bar.Anchor().background:IsShown(), "turned on, so gone")
    end)

    it("clamps a hand-edited icon size instead of trusting the database", function()
        -- A hand-edited TrinketMenuDB is exactly the case the clamp in
        -- iconSize() exists for: nothing on the slider can produce an
        -- out-of-range value, but a saved variable edited by hand can.
        local ns = carrying(1)

        ns.db.bar.iconSize = 999
        ns.Bar.Apply()
        assertEqual(48, ns.Bar.Buttons()[1]:GetWidth(), "clamped to the max")

        ns.db.bar.iconSize = 0
        ns.Bar.Apply()
        assertEqual(12, ns.Bar.Buttons()[1]:GetWidth(), "clamped to the min")

        ns.db.bar.iconSize = -5
        ns.Bar.Apply()
        assertEqual(12, ns.Bar.Buttons()[1]:GetWidth(), "a negative value clamps too")
    end)

    it("clamps a hand-edited perRow instead of dividing by it unchecked", function()
        -- perRow = 0 reaches `placed % 0` in Layout -- the same hand-edited
        -- TrinketMenuDB case the icon-size clamp above exists for.
        local ns = carrying(3)

        ns.db.bar.perRow = 0
        local ok = pcall(ns.Bar.Apply)
        assertTrue(ok, "perRow = 0 must not reach placed % 0")

        local _, _, _, firstX, firstY = ns.Bar.Buttons()[1]:GetPoint()
        local _, _, _, secondX, secondY = ns.Bar.Buttons()[2]:GetPoint()
        assertTrue(secondY < firstY, "clamped to 1 per row, so each button wraps")
        assertEqual(firstX, secondX, "and stays in the same column")

        ns.db.bar.perRow = -3
        ok = pcall(ns.Bar.Apply)
        assertTrue(ok, "a negative perRow must not reach placed % perRow either")

        ns.db.bar.perRow = 999
        ns.Bar.Apply()
        local _, _, _, thirdX, thirdY = ns.Bar.Buttons()[3]:GetPoint()
        assertEqual(firstY, thirdY, "clamped to MAX_BUTTONS, so three still fit on one row")
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

    it("is protected, the way every button in the pool hanging off it is", function()
        -- The anchor's whole combat tripwire depends on the fixture knowing
        -- it is combat-sensitive. There is no real client call an addon can
        -- make to become protected (SetProtected is not a real Frame
        -- method -- only the read-only IsProtected is), so the fixture
        -- marks it by frame name in CreateFrame. Pinned here so that seam
        -- cannot be silently deleted the way the old SetProtected(true)
        -- call in Bar.lua was: removing it left the suite green with the
        -- anchor's combat guard quietly disarmed.
        local ns = loggedIn()
        assertTrue(ns.Bar.Anchor():IsProtected())
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

    it("does not announce a save after a refused drag that never started", function()
        -- The client fires OnDragStart and OnDragStop as a matched pair for
        -- one mouse gesture regardless of what OnDragStart's handler does,
        -- so a drag attempted in combat used to print both "Cannot move the
        -- bar in combat." (the refusal) and "Bar position will be saved
        -- once combat ends." (OnDragStop's now-removed deferral message) --
        -- contradicting itself in the same breath. OnDragStop no longer
        -- defers or announces anything at all, so this should stay true no
        -- matter what OnDragStop is later given to say.
        local ns, env = loggedIn()
        local frame = ns.Bar.Anchor()

        env.__setCombat(true)
        frame.scripts.OnDragStart(frame)
        frame.scripts.OnDragStop(frame)

        assertMatch("combat", helpers.printed(env))
        assertFalse(helpers.printed(env):find("will be saved") ~= nil,
            "a drag that never started must not announce a save")
    end)

    it("lets the drag end safely if combat starts before the mouse is released", function()
        -- A drag can start out of combat and still be running when a mob
        -- pulls -- the release then runs on a frame every secure button
        -- hangs off, so it must never raise. But saving the dropped
        -- position is a GetPoint (a read) and three writes to a plain Lua
        -- table, not a secure write -- nothing here is ever refused, so
        -- there is nothing to defer. The position is saved immediately,
        -- combat or not.
        local ns, env = loggedIn()
        local frame = ns.Bar.Anchor()

        frame.scripts.OnDragStart(frame)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 200, -60)

        env.__setCombat(true)

        local ok = pcall(frame.scripts.OnDragStop, frame)
        assertTrue(ok, "the release itself must never raise")
        assertEqual(200, ns.db.anchor.x, "saved immediately -- nothing here is a secure write")
        assertEqual(-60, ns.db.anchor.y)
    end)

    it("does not let a stale queued drag-save clobber a later /tm reset", function()
        -- Proved failure from an earlier, wrong fix: the drag's own write
        -- was deferred to PLAYER_REGEN_ENABLED the same as a reset's
        -- reposition. Both then ran inside the same runPending(), in a
        -- fixed order (save, then reposition) that had nothing to do with
        -- which one the player actually did last. Here the release happens
        -- BEFORE the reset -- reset is genuinely the last word -- but the
        -- old deferred save would still run at combat-end and overwrite the
        -- freshly-reset database with the stale, already-superseded drag
        -- position, breaking the "Bar will move back once combat ends."
        -- promise. Writing the drag's position immediately, at release time
        -- rather than batched later, means nothing queued can reach forward
        -- past a change that came after it.
        local ns, env = loggedIn()
        local frame = ns.Bar.Anchor()

        frame.scripts.OnDragStart(frame)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 300, -80)

        env.__setCombat(true)
        frame.scripts.OnDragStop(frame)
        helpers.command(env, "reset")

        env.__setCombat(false)

        assertEqual("CENTER", ns.db.anchor.point, "the reset is the last word, so it must win")
        assertEqual(0, ns.db.anchor.x)
        assertEqual(-160, ns.db.anchor.y)
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

    it("toggles the lock on /tm lock", function()
        local ns, env = loggedIn()
        assertFalse(ns.db.bar.locked)

        helpers.command(env, "lock")
        assertTrue(ns.db.bar.locked)
    end)

    it("puts the bar back in the middle on /tm reset", function()
        local ns, env = loggedIn()
        ns.db.anchor.point = "TOPLEFT"
        ns.db.anchor.x = 400

        helpers.command(env, "reset")

        assertEqual("CENTER", ns.db.anchor.point)
        assertEqual(0, ns.db.anchor.x)
    end)

    it("defers /tm reset in combat instead of moving the anchor", function()
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

    it("does not arm pending when a cooldown ticks over in combat", function()
        -- BAG_UPDATE_COOLDOWN redraws a sweep, nothing else. Handling it
        -- with a full Bar.Apply() instead of RefreshCooldowns() would
        -- attempt a secure write every time a cooldown starts -- refused
        -- mid-fight, which is exactly when cooldowns are being watched --
        -- and leave `pending` armed for the rest of any fight.
        local ns, env = carrying({ "Hand of Justice" })
        ns.Bar.Apply()

        env.__setCombat(true)
        env.__cooldowns["bag:0:1"] = { start = 100, duration = 120 }
        helpers.fire(env, "BAG_UPDATE_COOLDOWN")

        assertFalse(ns.Bar.Pending())
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
