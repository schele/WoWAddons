local helpers = require("helpers")

local POLE, STAFF = 6256, 1161

--- Logged in holding whatever is given in the main hand.
local function loggedIn(mainHand)
    local ns, env = helpers.loadAddon()
    env.__mainHand = mainHand
    helpers.login(ns, env)
    return ns, env
end

local function binding(env, key)
    return env.__bindings[key or "F"]
end

-- The event and the client's own answer move together, because in the game
-- they are two views of one fact: UnitChannelInfo reports the channel the
-- event announced. A test that fires the event alone is staging a state the
-- client cannot be in, and one that fires it for somebody else or for another
-- spell must leave the player's own channel alone.
local function castStart(env, spellID)
    local id = spellID or 7620
    local unit = "player"
    if env.__spellNames[id] == "Fishing" then
        env.__channelling = "Fishing"
    end
    helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_START", unit, "guid", id)
end

local function castStop(env, spellID)
    env.__channelling = nil
    helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", spellID or 7620)
end

describe("the cast button", function()
    it("is a secure button that casts Fishing by name", function()
        local ns = loggedIn(POLE)
        local button = ns.Fishing.castButton

        assertEqual("SecureActionButtonTemplate", button.template)
        assertEqual("spell", button:GetAttribute("type"))
        assertEqual("Fishing", button:GetAttribute("spell"))
    end)

    it("asks for both edges of a click, since this client acts on the press", function()
        local ns = loggedIn(POLE)

        assertEqual("AnyUp", ns.Fishing.castButton.clicks[1])
        assertEqual("AnyDown", ns.Fishing.castButton.clicks[2])
    end)
end)

describe("the fishing key", function()
    it("casts Fishing while a pole is equipped", function()
        local ns, env = loggedIn(POLE)

        assertEqual("FishScaleCastButton", binding(env).button)
        assertEqual("LeftButton", binding(env).mouseButton)
    end)

    it("is left alone without a pole", function()
        local ns, env = loggedIn(STAFF)

        assertNil(binding(env))
    end)

    it("is taken when a pole is put on, and given back when it comes off", function()
        local ns, env = loggedIn(STAFF)

        env.__mainHand = POLE
        helpers.fire(env, "PLAYER_EQUIPMENT_CHANGED", 16)
        assertEqual("FishScaleCastButton", binding(env).button, "pole on")

        env.__mainHand = STAFF
        helpers.fire(env, "PLAYER_EQUIPMENT_CHANGED", 16)
        assertNil(binding(env), "pole off")
    end)

    it("picks up the bobber while the line is out", function()
        local ns, env = loggedIn(POLE)

        castStart(env)

        assertEqual("INTERACTTARGET", binding(env).command)
    end)

    it("goes back to casting once the line is in", function()
        local ns, env = loggedIn(POLE)

        castStart(env)
        castStop(env)

        assertEqual("FishScaleCastButton", binding(env).button)
    end)

    it("recognises any rank of Fishing, by name", function()
        local ns, env = loggedIn(POLE)

        castStart(env, 7731)

        assertEqual("INTERACTTARGET", binding(env).command)
    end)

    it("ignores other channels, and other people's", function()
        local ns, env = loggedIn(POLE)

        castStart(env, 774)
        assertEqual("FishScaleCastButton", binding(env).button, "another spell")

        helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_START", "party1", "guid", 7620)
        assertEqual("FishScaleCastButton", binding(env).button, "someone else fishing")
    end)

    it("lets go while the loot window is open, so it cannot recast over the loot", function()
        local ns, env = loggedIn(POLE)

        helpers.fire(env, "LOOT_OPENED")
        assertNil(binding(env), "loot open")

        helpers.fire(env, "LOOT_CLOSED")
        assertEqual("FishScaleCastButton", binding(env).button, "loot closed")
    end)

    it("reels in even when the channel start event never arrives", function()
        -- Reported from the water: casting kept working, reeling in stopped,
        -- after a few good minutes. That is this -- the line is out, the
        -- event that says so went missing, and nothing was ever going to put
        -- the key right again, because only that event moved it.
        local ns, env = loggedIn(POLE)

        env.__channelling = "Fishing"
        helpers.elapse(env, 0.25)

        assertEqual("INTERACTTARGET", binding(env).command,
            "the client says the line is out, whatever the events said")
    end)

    it("casts again even when the channel stop event never arrives", function()
        -- The same fault the other way up, and worse: the key would be stuck
        -- on INTERACTTARGET and never cast again.
        local ns, env = loggedIn(POLE)

        castStart(env)
        assertEqual("INTERACTTARGET", binding(env).command, "line out")

        env.__channelling = nil
        helpers.elapse(env, 0.25)

        assertEqual("FishScaleCastButton", binding(env).button,
            "the line is in, so the key casts again")
    end)

    it("believes the client over a stale event", function()
        -- An event that arrives and is wrong, rather than one that never
        -- arrives. The client is the thing itself; the flag is a memory.
        local ns, env = loggedIn(POLE)

        env.__channelling = "Fishing"
        -- The raw event, not castStop, which would take the line in too --
        -- the disagreement is the whole point here.
        helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 7620)

        assertEqual("INTERACTTARGET", binding(env).command)
    end)

    it("falls back to the events on a client that will not say", function()
        -- Three answers, not two: a client without UnitChannelInfo must look
        -- like "will not say", not like a line that is never out.
        local ns, env = loggedIn(POLE)
        env.UnitChannelInfo = nil

        castStart(env)

        assertEqual("INTERACTTARGET", binding(env).command)
    end)

    it("does not poll the key back while a fight has it", function()
        local ns, env = loggedIn(POLE)

        helpers.fire(env, "PLAYER_REGEN_DISABLED")
        env.__inCombat = true

        env.__channelling = "Fishing"
        helpers.elapse(env, 0.5)

        assertNil(binding(env), "the fight keeps the key")
    end)

    it("gives the key back as a fight starts, and takes it again after", function()
        local ns, env = loggedIn(POLE)

        -- PLAYER_REGEN_DISABLED fires just before the lockdown, which is
        -- the last moment a binding can change.
        helpers.fire(env, "PLAYER_REGEN_DISABLED")
        env.__inCombat = true
        assertNil(binding(env), "fighting")

        -- Nothing may touch a binding in the fight itself.
        castStart(env)
        castStop(env)

        env.__inCombat = false
        helpers.fire(env, "PLAYER_REGEN_ENABLED")
        assertEqual("FishScaleCastButton", binding(env).button, "after the fight")
    end)

    it("can take the key without a pole, for a client that fishes without one", function()
        local ns, env = loggedIn(nil)

        helpers.command(env, "nopole")

        assertEqual("FishScaleCastButton", binding(env).button)
    end)

    it("moves to a new key, letting go of the old one", function()
        local ns, env = loggedIn(POLE)

        helpers.command(env, "key shift-g")

        assertNil(binding(env, "F"))
        assertEqual("FishScaleCastButton", binding(env, "SHIFT-G").button)
    end)

    it("gives the key back when turned off", function()
        local ns, env = loggedIn(POLE)

        helpers.command(env, "off")
        assertNil(binding(env), "off")

        helpers.command(env, "on")
        assertEqual("FishScaleCastButton", binding(env).button, "on again")
    end)
end)

describe("settings changed while fishing", function()
    it("turns on soft targeting and auto loot while fishing", function()
        local ns, env = loggedIn(POLE)

        assertEqual("3", env.__cvars.SoftTargetInteract)
        assertEqual("45", env.__cvars.SoftTargetInteractRange)
        assertEqual("1", env.__cvars.autoLootDefault)
    end)

    it("reaches for the bobber whichever way the camera points", function()
        -- Range alone is not enough, and this is the half that was missing.
        -- The default arc is a cone in front of the player: a long cast
        -- drifts outside it and the key finds nothing however far it may
        -- reach, which is why short casts worked and long ones did not.
        local ns, env = loggedIn(POLE)

        assertEqual("2", env.__cvars.SoftTargetInteractArc)
    end)

    it("puts the arc back with everything else", function()
        local ns, env = loggedIn(POLE)

        env.__mainHand = STAFF
        helpers.fire(env, "PLAYER_EQUIPMENT_CHANGED", 16)

        assertEqual("0", env.__cvars.SoftTargetInteractArc)
    end)

    it("puts every one back as it was when fishing stops", function()
        local ns, env = loggedIn(POLE)

        env.__mainHand = STAFF
        helpers.fire(env, "PLAYER_EQUIPMENT_CHANGED", 16)

        assertEqual("0", env.__cvars.SoftTargetInteract)
        assertEqual("10", env.__cvars.SoftTargetInteractRange)
        assertEqual("0", env.__cvars.autoLootDefault)
    end)

    it("leaves auto loot alone when asked to", function()
        local ns, env = loggedIn(POLE)

        helpers.command(env, "autoloot")

        assertEqual("0", env.__cvars.autoLootDefault)
        assertEqual("3", env.__cvars.SoftTargetInteract, "soft targeting still on")
    end)

    it("does not invent a setting this client does not have", function()
        local ns, env = helpers.loadAddon()
        env.__cvars.SoftTargetInteractRange = nil
        env.__mainHand = POLE
        helpers.login(ns, env)

        assertNil(env.__cvars.SoftTargetInteractRange)
    end)

    it("asks for a reach a long cast can actually be reeled in from", function()
        -- Reported from the water: a cast that lands far away cannot be
        -- reeled in, while casting keeps working. The key is bound and
        -- correct; there is simply nothing within reach for it to interact
        -- with, and an interact key that reaches nothing does nothing.
        local ns, env = loggedIn(POLE)

        assertEqual(45, ns.Fishing.GrantedRange())
    end)

    it("takes a new reach from the range command", function()
        local ns, env = loggedIn(POLE)

        helpers.command(env, "range 60")

        assertEqual("60", env.__cvars.SoftTargetInteractRange)
        assertEqual(60, ns.Fishing.GrantedRange())
    end)

    it("still puts the player's own reach back after changing it twice", function()
        -- restoreCVars runs before the new value is asked for. Without that,
        -- the second change remembers the *fishing* reach as the player's
        -- own and hands that back when fishing stops.
        local ns, env = loggedIn(POLE)

        helpers.command(env, "range 60")
        helpers.command(env, "range 25")

        env.__mainHand = STAFF
        helpers.fire(env, "PLAYER_EQUIPMENT_CHANGED", 16)

        assertEqual("10", env.__cvars.SoftTargetInteractRange,
            "the reach the player had before FishScale touched it")
    end)

    it("says so when the client grants less reach than was asked for", function()
        -- The client clamps this setting silently rather than refusing, so
        -- the only way a player learns their casts are out of reach is if
        -- the addon reads back what it was actually given and says.
        local ns, env = loggedIn(POLE)

        -- A client that will not go past 20, whatever it is asked for.
        env.SetCVar = function(name, value)
            if name == "SoftTargetInteractRange" then
                value = math.min(20, tonumber(value) or 20)
            end
            env.__cvars[name] = tostring(value)
        end

        helpers.command(env, "range 60")
        helpers.command(env, "status")

        local said = helpers.printed(env)
        assertTrue(said:find("granted 20", 1, true) ~= nil,
            "status must report the reach actually granted, not the one asked for: " .. said)
    end)

    it("moves an existing player off the arc that was shipped by mistake", function()
        -- The reason this migration exists at all: a stored 1 is invisible to
        -- a changed default, and at 1 the key never acquires a far bobber.
        local ns, env = helpers.loadAddon()
        env.FishScaleDB = { version = 1, fishing = { arc = 1 } }
        env.__mainHand = POLE
        helpers.login(ns, env)

        assertEqual(2, ns.db.fishing.arc)
        assertEqual("2", env.__cvars.SoftTargetInteractArc)
    end)

    it("leaves an arc the player chose themselves alone", function()
        -- Undoing our mistake, not overruling their decision. 0 is a value
        -- nothing ever shipped as a default, so it can only have been chosen.
        local ns, env = helpers.loadAddon()
        env.FishScaleDB = { version = 1, fishing = { arc = 0 } }
        env.__mainHand = POLE
        helpers.login(ns, env)

        assertEqual(0, ns.db.fishing.arc)
    end)

    it("runs a migration once, not on every login", function()
        local ns, env = helpers.loadAddon()
        env.FishScaleDB = { version = 1, fishing = { arc = 1 } }
        env.__mainHand = POLE
        helpers.login(ns, env)

        -- Back to 1 deliberately: if the migration ran again it would undo
        -- this, and a player could never hold the value it once corrected.
        ns.db.fishing.arc = 1
        helpers.login(ns, env)

        assertEqual(1, ns.db.fishing.arc)
    end)

    it("takes a new arc from the arc command", function()
        -- The command exists because changing DEFAULT_ARC cannot reach a
        -- player who already has a value saved: applyDefaults fills in what
        -- is absent and leaves what is there. A shipped default change is
        -- invisible to everyone who has run the addon before, which is how a
        -- value I had already ruled out stayed in use for two rounds.
        local ns, env = loggedIn(POLE)

        helpers.command(env, "arc 2")

        assertEqual(2, ns.db.fishing.arc)
        assertEqual("2", env.__cvars.SoftTargetInteractArc)
    end)

    it("refuses an arc that is not a number", function()
        local ns, env = loggedIn(POLE)

        helpers.command(env, "arc wide")

        assertEqual(2, ns.db.fishing.arc, "unchanged")
    end)

    it("names a command that exists when it suggests one", function()
        -- The failure report said "Try /fs arc 0" before there was an arc
        -- command. Advice that names a command the addon does not have is
        -- worse than none: it sends the player off to type something that
        -- prints "Unknown command".
        local ns, env = loggedIn(POLE)
        castStart(env)
        helpers.fire(env, "UI_ERROR_MESSAGE", 50, "Too far.")

        -- Matched on "Try /fs", not on "/fs" alone: the login line mentions
        -- the command too, and a looser pattern reads that instead and
        -- asserts against the wrong sentence entirely.
        local suggested = helpers.printed(env):match("Try /fs (%a+)")
        assertTrue(ns.commands[suggested] ~= nil,
            "suggested /fs " .. tostring(suggested) .. ", which does not exist")
    end)

    it("survives an event carrying a value the client will not disclose", function()
        -- Live crash, six times over: the debug log did tostring() on every
        -- argument, which on a secret returns a secret *string* rather than
        -- raising -- so it sailed through and took table.concat down instead,
        -- one function away. Diagnostic code that crashes is worse than none:
        -- it fires exactly when someone is trying to help.
        local ns, env = loggedIn(POLE)
        helpers.command(env, "debug")

        -- An event the addon actually listens for: helpers.fire only reaches
        -- frames registered for it, so a made-up name would prove nothing
        -- by never arriving.
        local ok = pcall(helpers.fire, env, "LOOT_OPENED", env.__secret())

        assertTrue(ok, "logging a secret must not raise")
        assertMatch("<secret>", helpers.printed(env))
    end)

    it("does not log every nameplate's casts over the one being diagnosed", function()
        -- Every nameplate in sight reports through the same events. Six a
        -- second buries the cast actually being looked at.
        local ns, env = loggedIn(POLE)
        helpers.command(env, "debug")

        helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_STOP", "nameplate4", "guid", 7620)

        assertEqual("", helpers.printed(env):match("nameplate4") or "")
    end)

    it("traces what the key is aimed at while the line is out", function()
        -- The failure with no error at all: the key finds nothing, the game
        -- does not react, and there is no event to hang a report off. Only a
        -- trace while the bobber sits there can see it.
        local ns, env = loggedIn(POLE)
        helpers.command(env, "debug")
        castStart(env)

        env.__softInteract = "Murloc Tidehunter"
        helpers.elapse(env, 0.25)

        assertMatch("aimed at: Murloc Tidehunter", helpers.printed(env))
    end)

    it("traces the settings that decided it, on the same line", function()
        -- A reading of "nothing" cannot be interpreted without knowing the
        -- arc and reach it was taken at, and those are exactly what changes
        -- between readings. A screenshot of the trace has to stand alone.
        local ns, env = loggedIn(POLE)
        helpers.command(env, "debug")
        castStart(env)

        helpers.elapse(env, 0.25)

        assertMatch("arc 2", helpers.printed(env))
        assertMatch("reach 45", helpers.printed(env))
    end)

    it("traces the nothing, which is the case that makes no error", function()
        local ns, env = loggedIn(POLE)
        helpers.command(env, "debug")
        castStart(env)

        helpers.elapse(env, 0.25)

        assertMatch("aimed at: nothing", helpers.printed(env))
    end)

    it("traces on a change, not five times a second", function()
        local ns, env = loggedIn(POLE)
        helpers.command(env, "debug")
        castStart(env)

        helpers.elapse(env, 2, 0.25)

        local _, count = helpers.printed(env):gsub("aimed at", "")
        assertEqual(1, count)
    end)

    it("says what the key was aimed at when the client refuses the interact", function()
        -- Caught at the moment of failure. "You need to be closer" names no
        -- target, and asking afterwards asks about a state that has moved on.
        local ns, env = loggedIn(POLE)
        castStart(env)
        env.__softInteract = "Murloc Tidehunter"

        helpers.fire(env, "UI_ERROR_MESSAGE", 50,
            "You need to be closer to interact with that target.")

        assertMatch("aimed at: Murloc Tidehunter", helpers.printed(env))
    end)

    it("reads the message from a client that sends no error type", function()
        local ns, env = loggedIn(POLE)
        castStart(env)

        helpers.fire(env, "UI_ERROR_MESSAGE", "You need to be closer.")

        assertMatch("You need to be closer", helpers.printed(env))
    end)

    it("says it once per cast, not once per key press", function()
        -- The client repeats the refusal for as long as the key is held, and
        -- a diagnostic that buries the chat gets turned off before it has
        -- told anyone anything.
        local ns, env = loggedIn(POLE)
        castStart(env)

        for _ = 1, 5 do
            helpers.fire(env, "UI_ERROR_MESSAGE", 50, "Too far.")
        end

        local _, count = helpers.printed(env):gsub("It was aimed at", "")
        assertEqual(1, count)
    end)

    it("says it again on the next cast, which is a new bobber", function()
        local ns, env = loggedIn(POLE)
        castStart(env)
        helpers.fire(env, "UI_ERROR_MESSAGE", 50, "Too far.")
        castStop(env)

        castStart(env)
        helpers.fire(env, "UI_ERROR_MESSAGE", 50, "Too far.")

        local _, count = helpers.printed(env):gsub("It was aimed at", "")
        assertEqual(2, count)
    end)

    it("stays quiet about errors that have nothing to do with fishing", function()
        local ns, env = loggedIn(POLE)

        helpers.fire(env, "UI_ERROR_MESSAGE", 50, "Your bags are full.")

        assertEqual("", helpers.printed(env):match("It was aimed at") or "")
    end)

    it("says what the interact key is aimed at, which is what settles it", function()
        -- Reported from the water: "you need to be closer", while the bobber
        -- could still be clicked by hand. A click and an interact cannot
        -- disagree about range for the same object at the same distance, so
        -- the key was never aimed at the bobber -- and nothing about reach or
        -- arc was going to help until that was known.
        local ns, env = loggedIn(POLE)
        env.__softInteract = "Murloc Tidehunter"

        helpers.command(env, "status")

        assertMatch("aimed at: Murloc Tidehunter", helpers.printed(env))
    end)

    it("calls an unnamed soft target a game object, since the bobber is one", function()
        local ns, env = loggedIn(POLE)
        env.__softInteract = require("wow_stub").GAME_OBJECT

        helpers.command(env, "status")

        assertMatch("game object", helpers.printed(env))
    end)

    it("says that nothing to aim at during the wait is normal", function()
        -- A bobber is not interactable until the fish takes it, so "nothing"
        -- mid-channel is the right answer. Reading it as a fault is what sent
        -- four rounds of this chasing reach and arc settings that were never
        -- involved, and the addon now says so rather than leaving the next
        -- reader to make the same mistake.
        local ns, env = loggedIn(POLE)
        castStart(env)

        helpers.command(env, "status")

        assertMatch("only becomes interactable when it splashes", helpers.printed(env))
    end)

    it("does not say it when the line is not even out", function()
        local ns, env = loggedIn(POLE)

        helpers.command(env, "status")

        assertEqual("", helpers.printed(env):match("splashes") or "")
    end)

    it("says so when the key is aimed at nothing at all", function()
        -- Different fault, same symptom: the key does nothing because it
        -- found nothing, rather than because it found the wrong thing.
        local ns, env = loggedIn(POLE)

        helpers.command(env, "status")

        assertMatch("aimed at: nothing", helpers.printed(env))
    end)

    it("takes a new arc from the panel, clamped to what the client accepts", function()
        local ns, env = loggedIn(POLE)

        -- The registered setting, not one built here: a hand-made table has
        -- no onChange, so it would store the value and apply nothing, and
        -- the test would be asserting against its own stub of the wiring.
        local setting
        for _, candidate in ipairs(ns.settings) do
            if candidate.key == "arc" then
                setting = candidate
            end
        end

        ns.SetSettingValue(setting, 9)

        assertEqual("2", env.__cvars.SoftTargetInteractArc, "clamped to the maximum")
    end)

    it("refuses a reach that is not a number, rather than storing it", function()
        local ns, env = loggedIn(POLE)

        helpers.command(env, "range plenty")

        assertEqual("45", env.__cvars.SoftTargetInteractRange)
    end)
end)

describe("commands", function()
    it("says what the key is doing", function()
        local ns, env = loggedIn(POLE)

        helpers.command(env, "status")

        assertMatch("Key F: casts Fishing", helpers.printed(env))
    end)

    it("opens the panel for a bare /fs", function()
        -- Everything here can be set by pointing at it, so the window is the
        -- first thing a player wants from a bare command and the list is the
        -- second. The sibling addons list, because they were all commands
        -- first; this one was a panel from the moment it had one.
        local ns, env = loggedIn(POLE)

        helpers.command(env, "")

        assertEqual("category-id", env.__openedCategory)
    end)

    it("still lists the commands for /fs help", function()
        local ns, env = loggedIn(POLE)

        helpers.command(env, "help")

        assertMatch("/fs key", helpers.printed(env))
    end)
end)
