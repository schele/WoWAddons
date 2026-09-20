local helpers = require("helpers")

local FILES = { "ClickHeal.lua", "Anchors.lua", "Spells.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

describe("resolving a spell's icon", function()
    it("uses C_Spell.GetSpellTexture when it exists", function()
        local ns = loggedIn()
        assertEqual(136085, ns.Spells.Texture("Regrowth"))
    end)

    it("falls back to the old global GetSpellTexture when C_Spell lacks it", function()
        local ns, env = loggedIn()
        env.C_Spell.GetSpellTexture = nil
        env.GetSpellTexture = function(name) return env.__spellTextures[name] end

        assertEqual(136085, ns.Spells.Texture("Regrowth"))
    end)

    it("returns nil when neither API exists", function()
        local ns, env = loggedIn()
        env.C_Spell.GetSpellTexture = nil

        assertNil(ns.Spells.Texture("Regrowth"))
    end)

    it("returns nil for no spell at all", function()
        local ns = loggedIn()
        assertNil(ns.Spells.Texture(nil))
        assertNil(ns.Spells.Texture(""))
    end)
end)

describe("resolving what is on the cursor", function()
    it("returns nil when nothing is on the cursor", function()
        local ns, env = loggedIn()
        env.__cursor = nil

        assertNil(ns.Spells.CursorSpell())
    end)

    it("returns nil for a non-spell, such as an item, and never touches it", function()
        local ns, env = loggedIn()
        env.__cursor = { "item", 6948 }

        assertNil(ns.Spells.CursorSpell())
    end)

    it("resolves a spellID through C_Spell.GetSpellInfo", function()
        local ns, env = loggedIn()
        env.__cursor = { "spell", nil, nil, 8936, n = 4 }

        assertEqual("Rejuvenation", ns.Spells.CursorSpell())
    end)

    it("falls back to the old GetSpellInfo when C_Spell lacks GetSpellInfo", function()
        local ns, env = loggedIn()
        env.C_Spell.GetSpellInfo = nil
        env.GetSpellInfo = function(id) return env.__spellIDs[id] end
        env.__cursor = { "spell", nil, nil, 8936, n = 4 }

        assertEqual("Rejuvenation", ns.Spells.CursorSpell())
    end)

    it("resolves a spellbook index through C_SpellBook.GetSpellBookItemName", function()
        local ns, env = loggedIn()
        env.__cursor = { "spell", 5, "spell" }

        assertEqual("Regrowth", ns.Spells.CursorSpell())
    end)

    it("falls back to the old GetSpellBookItemName when C_SpellBook lacks it", function()
        local ns, env = loggedIn()
        env.C_SpellBook.GetSpellBookItemName = nil
        env.GetSpellBookItemName = function(index, bookType)
            return env.__spellbook[tostring(bookType) .. ":" .. tostring(index)]
        end
        env.__cursor = { "spell", 5, "spell" }

        assertEqual("Regrowth", ns.Spells.CursorSpell())
    end)

    it("returns nil, never a number or a table, when nothing resolves a name", function()
        local ns, env = loggedIn()
        env.__cursor = { "spell", 999, "spell" }

        assertNil(ns.Spells.CursorSpell())
    end)
end)

describe("knowing whether a spell is learned", function()
    -- Slots.Set asks this before warning about an unrecognised name, so it
    -- needs the same defensive chain as everything else here rather than its
    -- own, separate guess at what this client can answer.

    it("knows a learned spell through C_Spell.GetSpellInfo alone", function()
        -- No legacy global anywhere in this env -- this is the shape the
        -- spike found on the actual target client.
        local ns = loggedIn()
        assertTrue(ns.Spells.IsKnown("Regrowth"))
    end)

    it("does not know an unlearned spell through C_Spell.GetSpellInfo alone", function()
        local ns = loggedIn()
        assertFalse(ns.Spells.IsKnown("Tranquility"))
    end)

    it("falls back to the old GetSpellInfo when C_Spell lacks GetSpellInfo", function()
        local ns, env = loggedIn()
        env.C_Spell.GetSpellInfo = nil
        env.GetSpellInfo = function(name)
            return env.__spells[name] and name or nil
        end

        assertTrue(ns.Spells.IsKnown("Regrowth"))
        assertFalse(ns.Spells.IsKnown("Tranquility"))
    end)

    it("assumes known when neither API exists, rather than warn about something it cannot check", function()
        local ns, env = loggedIn()
        env.C_Spell.GetSpellInfo = nil

        assertTrue(ns.Spells.IsKnown("Tranquility"))
    end)

    it("is not fooled by an empty or missing name", function()
        local ns = loggedIn()
        assertFalse(ns.Spells.IsKnown(""))
        assertFalse(ns.Spells.IsKnown(nil))
    end)
end)

describe("reading a spell's cooldown", function()
    it("normalises C_Spell.GetSpellCooldown's table to loose values", function()
        local ns, env = loggedIn()
        env.__spellCooldowns["Rejuvenation"] =
            { startTime = 100, duration = 1.5, isEnabled = true }

        local start, duration, enabled = ns.Spells.Cooldown("Rejuvenation")

        assertEqual(100, start)
        assertEqual(1.5, duration)
        assertTrue(enabled)
    end)

    it("falls back to the old global, whose returns were never a table", function()
        local ns, env = loggedIn()
        env.C_Spell.GetSpellCooldown = nil
        env.GetSpellCooldown = function() return 100, 1.5, 1 end

        local start, duration, enabled = ns.Spells.Cooldown("Rejuvenation")

        assertEqual(100, start)
        assertEqual(1.5, duration)
        assertTrue(enabled, "the old API's 1 means enabled, and 1 is not a boolean")
    end)

    it("reports the old global's 0 as not enabled, rather than as truthy", function()
        -- 0 is truthy in Lua, so passing it through unconverted would draw a
        -- sweep over a spell the client is saying not to draw one for.
        local ns, env = loggedIn()
        env.C_Spell.GetSpellCooldown = nil
        env.GetSpellCooldown = function() return 100, 1.5, 0 end

        local _, _, enabled = ns.Spells.Cooldown("Rejuvenation")

        assertFalse(enabled)
    end)

    it("returns nil for a spell this client has nothing to say about", function()
        local ns = loggedIn()
        assertNil(ns.Spells.Cooldown("Rejuvenation"))
    end)

    it("returns nil when neither API exists", function()
        local ns, env = loggedIn()
        env.C_Spell.GetSpellCooldown = nil

        assertNil(ns.Spells.Cooldown("Rejuvenation"))
    end)

    it("returns nil for no spell at all", function()
        local ns = loggedIn()
        assertNil(ns.Spells.Cooldown(""))
        assertNil(ns.Spells.Cooldown(nil))
    end)
end)

describe("asking whether a spell can reach a unit", function()
    it("reports a spell in range", function()
        local ns, env = loggedIn()
        env.__spellRanges["Rejuvenation:party1"] = true
        assertTrue(ns.Spells.InRange("Rejuvenation", "party1"))
    end)

    it("reports a spell out of range", function()
        local ns, env = loggedIn()
        env.__spellRanges["Rejuvenation:party1"] = false
        assertFalse(ns.Spells.InRange("Rejuvenation", "party1"))
    end)

    it("falls back to the old global, which answered 1 and 0", function()
        local ns, env = loggedIn()
        env.C_Spell.IsSpellInRange = nil

        env.IsSpellInRange = function() return 1 end
        assertTrue(ns.Spells.InRange("Rejuvenation", "party1"))

        env.IsSpellInRange = function() return 0 end
        assertFalse(ns.Spells.InRange("Rejuvenation", "party1"),
            "0 is truthy in Lua, so passing it through would read as in range")
    end)

    it("says nothing, rather than out of range, when the client will not answer", function()
        -- nil is "cannot tell", and must never dim: telling a healer a spell
        -- is out of reach when it is not costs them a cast they had.
        local ns = loggedIn()
        assertNil(ns.Spells.InRange("Rejuvenation", "party1"))
    end)

    it("says nothing when neither API exists", function()
        local ns, env = loggedIn()
        env.C_Spell.IsSpellInRange = nil
        assertNil(ns.Spells.InRange("Rejuvenation", "party1"))
    end)

    it("says nothing when the client keeps the answer secret", function()
        -- UnitInRange already does exactly this, which is what took the
        -- original range dimming away. The per-spell call may well go the
        -- same way, so it is asked for behind the same guard.
        local ns, env = loggedIn()
        env.C_Spell.IsSpellInRange = function() error("secret boolean value") end
        assertNil(ns.Spells.InRange("Rejuvenation", "party1"))
    end)

    it("says nothing for a missing spell or unit", function()
        local ns = loggedIn()
        assertNil(ns.Spells.InRange("", "party1"))
        assertNil(ns.Spells.InRange("Rejuvenation", nil))
    end)
end)

describe("listing the spells a slot can be given", function()
    it("walks the spellbook until it runs out", function()
        local ns, env = loggedIn()
        env.__learnSpells({ "Rejuvenation", "Healing Touch", "Mark of the Wild" })

        local known = ns.Spells.Pickable()

        assertEqual(3, #known)
    end)

    it("sorts them, since a spellbook is in no order worth showing", function()
        local ns, env = loggedIn()
        env.__learnSpells({ "Rejuvenation", "Healing Touch", "Mark of the Wild" })

        local known = ns.Spells.Pickable()

        assertEqual("Healing Touch", known[1])
        assertEqual("Mark of the Wild", known[2])
        assertEqual("Rejuvenation", known[3])
    end)

    it("lists a spell once however many ranks of it there are", function()
        -- Classic gives every rank its own spellbook entry. A slot holds a
        -- name, and the name casts the best rank, so the others are noise.
        local ns, env = loggedIn()
        env.__learnSpells({
            "Healing Touch", "Healing Touch", "Healing Touch", "Rejuvenation",
        })

        local known = ns.Spells.Pickable()

        assertEqual(2, #known)
        assertEqual("Healing Touch", known[1])
    end)

    it("stops at the first gap rather than running to the cap", function()
        local ns, env = loggedIn()
        env.__learnSpells({ "Rejuvenation" })
        -- Something far down the book, past where the walk must have stopped.
        env.__learnSpellAt(500, "Tranquility")

        local known = ns.Spells.Pickable()

        assertEqual(1, #known)
    end)

    it("is empty, not broken, for a character with no spellbook", function()
        local ns = loggedIn()
        assertEqual(0, #ns.Spells.Pickable())
    end)

    it("falls back to the old global when C_SpellBook lacks the lookup", function()
        local ns, env = loggedIn()
        env.__learnSpells({ "Rejuvenation" })
        local book = env.__spellbook
        env.C_SpellBook.GetSpellBookItemName = nil
        env.GetSpellBookItemName = function(index, bookType)
            return book[tostring(bookType) .. ":" .. tostring(index)]
        end

        assertEqual(1, #ns.Spells.Pickable())
    end)
end)

describe("reading the player's own buffs on a unit", function()
    it("collects them by name, with when each runs out", function()
        local ns, env = loggedIn()
        env.__auras.party1 = {
            { name = "Rejuvenation", expirationTime = 1012 },
            { name = "Mark of the Wild", expirationTime = 3280 },
        }

        local auras = ns.Spells.PlayerAuras("party1")

        assertEqual(1012, auras.Rejuvenation)
        assertEqual(3280, auras["Mark of the Wild"])
    end)

    it("is empty rather than broken for a unit with nothing on it", function()
        local ns = loggedIn()
        assertEqual(0, #ns.Spells.PlayerAuras("party1"))
    end)

    it("is empty when the client keeps its auras secret", function()
        local ns, env = loggedIn()
        env.C_UnitAuras.GetAuraDataByIndex = function() error("secret value") end

        local ok, auras = pcall(ns.Spells.PlayerAuras, "party1")
        assertTrue(ok, "a secret aura must not take the row down with it")
        assertNil(auras.Rejuvenation)
    end)

    it("counts down from the clock the client keeps", function()
        local ns, env = loggedIn()
        env.__now = 1000
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1012 } }

        assertEqual(12, ns.Spells.AuraRemaining("party1", "Rejuvenation"))
    end)

    it("says nothing for a spell that is not on the unit", function()
        local ns, env = loggedIn()
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1012 } }

        assertNil(ns.Spells.AuraRemaining("party1", "Mark of the Wild"))
    end)

    it("says nothing for an aura that never runs out", function()
        -- The client writes a permanent aura as expiring at zero. Subtracting
        -- the clock from that would show a large negative countdown.
        local ns, env = loggedIn()
        env.__auras.party1 = { { name = "Mark of the Wild", expirationTime = 0 } }

        assertNil(ns.Spells.AuraRemaining("party1", "Mark of the Wild"))
    end)

    it("says nothing once the aura has run out", function()
        local ns, env = loggedIn()
        env.__now = 1020
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1012 } }

        assertNil(ns.Spells.AuraRemaining("party1", "Rejuvenation"))
    end)

    it("takes an already-gathered list rather than asking again", function()
        -- What lets a row ask once and answer for all eight of its buttons.
        local ns, env = loggedIn()
        env.__now = 1000
        local gathered = { Rejuvenation = 1009 }
        env.C_UnitAuras.GetAuraDataByIndex = function() error("must not be asked") end

        assertEqual(9, ns.Spells.AuraRemaining("party1", "Rejuvenation", gathered))
    end)
end)
