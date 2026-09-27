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

local function castStart(env, spellID)
    helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_START", "player", "guid", spellID or 7620)
end

local function castStop(env, spellID)
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
        assertEqual("30", env.__cvars.SoftTargetInteractRange)
        assertEqual("1", env.__cvars.autoLootDefault)
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
end)

describe("commands", function()
    it("says what the key is doing", function()
        local ns, env = loggedIn(POLE)

        helpers.command(env, "status")

        assertMatch("Key F: casts Fishing", helpers.printed(env))
    end)

    it("lists the commands for a bare /fs", function()
        local ns, env = loggedIn(POLE)

        helpers.command(env, "")

        assertMatch("/fs key", helpers.printed(env))
    end)
end)
