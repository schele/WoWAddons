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

    it("returns nil rather than a number the client is withholding", function()
        -- Both comparisons belong inside this function's guard. A secret
        -- number reaches a caller looking exactly like a real one -- truthy,
        -- and unchanged by `or 0` -- so handing one out is handing out a
        -- crash that fires wherever the caller happens to test it.
        local ns, env = loggedIn()
        env.__spellCooldowns["Rejuvenation"] = {
            startTime = env.__secret(),
            duration = env.__secret(),
            isEnabled = true,
        }

        local ok, start = pcall(ns.Spells.Cooldown, "Rejuvenation")

        assertTrue(ok, "reading it must not raise: " .. tostring(start))
        assertNil(start, "and an unreadable cooldown is no cooldown")
    end)

    it("returns nil for a withheld cooldown from the old global too", function()
        local ns, env = loggedIn()
        env.C_Spell.GetSpellCooldown = nil
        env.GetSpellCooldown = function()
            return env.__secret(), env.__secret(), 1
        end

        local ok, start = pcall(ns.Spells.Cooldown, "Rejuvenation")

        assertTrue(ok, "reading it must not raise: " .. tostring(start))
        assertNil(start)
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

describe("reading the helpful buffs on a unit", function()
    it("collects them by name, with when each runs out", function()
        local ns, env = loggedIn()
        env.__auras.party1 = {
            { name = "Rejuvenation", expirationTime = 1012 },
            { name = "Mark of the Wild", expirationTime = 3280 },
        }

        local auras = ns.Spells.HelpfulAuras("party1")

        assertEqual(1012, auras.Rejuvenation.expires)
        assertEqual(3280, auras["Mark of the Wild"].expires)
    end)

    it("says which of them this player cast", function()
        local ns, env = loggedIn()
        env.__auras.party1 = {
            { name = "Rejuvenation", expirationTime = 1012 },
            { name = "Mark of the Wild", expirationTime = 3280, caster = "party2" },
        }

        local auras = ns.Spells.HelpfulAuras("party1")

        assertTrue(auras.Rejuvenation.mine)
        assertFalse(auras["Mark of the Wild"].mine)
    end)

    it("counts one it will not attribute as this player's", function()
        -- Every aura on your own unit, on 1.60.1. Read as somebody else's it
        -- would grey every number on the row beside your own frame.
        local ns, env = loggedIn()
        env.__auras.player =
            { { name = "Mark of the Wild", expirationTime = 3280, caster = false } }

        local aura = ns.Spells.HelpfulAuras("player")["Mark of the Wild"]

        assertEqual(3280, aura.expires)
        assertTrue(aura.mine)
    end)

    it("is empty rather than broken for a unit with nothing on it", function()
        local ns = loggedIn()
        assertNil(next(ns.Spells.HelpfulAuras("party1")))
    end)

    it("is empty when the client keeps its auras secret", function()
        local ns, env = loggedIn()
        env.C_UnitAuras.GetAuraDataByIndex = function() error("secret value") end

        local ok, auras = pcall(ns.Spells.HelpfulAuras, "party1")
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
        local gathered = { Rejuvenation = { expires = 1009, mine = true } }
        env.C_UnitAuras.GetAuraDataByIndex = function() error("must not be asked") end

        assertEqual(9, ns.Spells.AuraRemaining("party1", "Rejuvenation", gathered))
    end)

    it("says whose cast the number belongs to, alongside it", function()
        local ns, env = loggedIn()
        env.__now = 1000
        env.__auras.party1 =
            { { name = "Rejuvenation", expirationTime = 1009, caster = "party2" } }

        local remaining, mine = ns.Spells.AuraRemaining("party1", "Rejuvenation")

        assertEqual(9, remaining)
        assertFalse(mine, "somebody else's Rejuvenation is not a heal you have")
    end)

    it("says nothing for an expiry the client is withholding", function()
        -- HelpfulAuras guards the reading, but a secret expiry is truthy and
        -- rides out of that guard inside the table. The subtraction here is
        -- what raises -- the same defect as the cooldown crash, one path over.
        local ns, env = loggedIn()
        env.__now = 1000
        env.__auras.party1 =
            { { name = "Rejuvenation", expirationTime = env.__secret() } }

        local ok, remaining = pcall(ns.Spells.AuraRemaining, "party1", "Rejuvenation")

        assertTrue(ok, "an unreadable expiry must cost one timer, not the "
            .. "refresh: " .. tostring(remaining))
        assertNil(remaining)
    end)
end)

describe("reading the helpful buffs on a unit, by caster", function()
    it("keeps a buff somebody else cast, and says it is theirs", function()
        -- The number is worth having -- the buff is on them -- and so is
        -- knowing it is not yours.
        local ns, env = loggedIn()
        env.__auras.party1 = {
            { name = "Mark of the Wild", expirationTime = 3280, caster = "party2" },
            { name = "Rejuvenation", expirationTime = 1012 },
        }

        local auras = ns.Spells.HelpfulAuras("party1")

        assertFalse(auras["Mark of the Wild"].mine)
        assertTrue(auras.Rejuvenation.mine)
    end)
end)

describe("the aura report", function()
    local function report(ns, unit, spells)
        return table.concat(ns.Spells.Report(unit, spells), "\n")
    end

    it("names every aura it found and how long each has left", function()
        local ns, env = loggedIn()
        env.__now = 1000
        env.__auras.party1 = { { name = "Mark of the Wild", expirationTime = 1030 } }

        local printed = report(ns, "party1")

        assertMatch("Mark of the Wild", printed)
        assertMatch("30s", printed)
        assertMatch("1 aura", printed)
    end)

    it("says the expiry was withheld rather than going down with it", function()
        -- The case the timers cannot tell apart from an empty slot, and the
        -- whole reason this report exists: the aura is there, its name reads,
        -- and the number behind it is one tainted code may not do arithmetic
        -- on.
        local ns, env = loggedIn()
        env.__auras.party1 =
            { { name = "Mark of the Wild", expirationTime = env.__secret() } }

        local ok, lines = pcall(ns.Spells.Report, "party1")

        assertTrue(ok, "a diagnostic that throws is worse than none: "
            .. tostring(lines))
        local printed = table.concat(lines, "\n")
        assertMatch("Mark of the Wild", printed)
        assertMatch("WITHHELD", printed)
    end)

    it("shows what the unfiltered walk finds when ours comes back empty", function()
        -- Separates "nothing of ours is on them" from "asking only for ours
        -- is what emptied it", which look identical under an icon.
        local ns, env = loggedIn()
        env.__auras.party1 = {
            { name = "Mark of the Wild", expirationTime = 1030, caster = "party2" },
        }

        local printed = report(ns, "party1")

        assertMatch("HELPFUL|PLAYER: 0 aura", printed)
        assertMatch("HELPFUL: 1 aura", printed)
    end)

    it("says so, once, when the client raises on the read itself", function()
        local ns, env = loggedIn()
        env.C_UnitAuras.GetAuraDataByIndex = function() error("secret value") end

        local ok, lines = pcall(ns.Spells.Report, "party1")

        assertTrue(ok, "the report must survive the client it is reporting on")
        assertMatch("raised", table.concat(lines, "\n"))
    end)

    it("answers for each spell the row's buttons are holding", function()
        local ns, env = loggedIn()
        env.__now = 1000
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007 } }

        local printed = report(ns, "party1", { "Rejuvenation", "Mark of the Wild" })

        assertMatch("Rejuvenation: 7s", printed)
        assertMatch("Mark of the Wild: no number", printed)
    end)
end)

describe("your own buffs on your own unit", function()
    it("counts one this client will not attribute to anybody", function()
        -- The bug, exactly as /ch auras reported it on 1.60.1: the client
        -- hands back the Mark of the Wild on your own unit and answers the
        -- PLAYER half of the filter with nothing, so the row beside your own
        -- frame was the only one with no numbers on it.
        local ns, env = loggedIn()
        env.__auras.player =
            { { name = "Mark of the Wild", expirationTime = 3280, caster = false } }

        assertEqual(3280, ns.Spells.HelpfulAuras("player")["Mark of the Wild"].expires)
    end)

    it("still counts one the client does attribute to you", function()
        local ns, env = loggedIn()
        env.__auras.player = { { name = "Rejuvenation", expirationTime = 1012 } }

        assertEqual(1012, ns.Spells.HelpfulAuras("player").Rejuvenation.expires)
    end)

    it("takes both, however the client attributes each", function()
        -- The two answers arrive in one walk, so a buff it does name cannot
        -- crowd out one it does not.
        local ns, env = loggedIn()
        env.__auras.player = {
            { name = "Thorns", expirationTime = 1300 },
            { name = "Mark of the Wild", expirationTime = 3280, caster = false },
        }

        local auras = ns.Spells.HelpfulAuras("player")

        assertEqual(1300, auras.Thorns.expires)
        assertEqual(3280, auras["Mark of the Wild"].expires)
    end)

    it("keeps a buff the client says somebody else cast on you, as theirs", function()
        -- Kept, because re-casting over a Mark of the Wild that is already
        -- running buys nothing; marked, because it is not your doing.
        local ns, env = loggedIn()
        env.__auras.player =
            { { name = "Mark of the Wild", expirationTime = 3280, caster = "party1" } }

        local aura = ns.Spells.HelpfulAuras("player")["Mark of the Wild"]

        assertEqual(3280, aura.expires)
        assertFalse(aura.mine)
    end)
end)

describe("the aura report naming who cast what", function()
    it("names the caster the client gave", function()
        local ns, env = loggedIn()
        env.__auras.party1 = { { name = "Thorns", expirationTime = 1300 } }

        assertMatch('source="player"',
            table.concat(ns.Spells.Report("party1"), "\n"))
    end)

    it("says nothing was named when the client would not say", function()
        -- The state the player's own unit is in on 1.60.1, and the one line
        -- that tells a later reader whether that is still true.
        local ns, env = loggedIn()
        env.__auras.player =
            { { name = "Mark of the Wild", expirationTime = 3280, caster = false } }

        assertMatch("source=nil", table.concat(ns.Spells.Report("player"), "\n"))
    end)
end)

describe("a client that will not say who cast an aura", function()
    it("keeps the aura, and the number under the icon with it", function()
        -- The whole walk went down on this: /ch auras on 1.60.1 answered
        -- "the client raised on the read" for every unit and every filter at
        -- index 1, and the bar lost every timer it had. One unreadable field
        -- may cost its own answer and nothing else.
        local ns, env = loggedIn()
        env.__auras.party1 =
            { { name = "Rejuvenation", expirationTime = 1012, caster = "secret" } }

        local auras = ns.Spells.HelpfulAuras("party1")

        assertEqual(1012, auras.Rejuvenation.expires)
    end)

    it("counts it as yours, which is how it is drawn", function()
        local ns, env = loggedIn()
        env.__auras.party1 =
            { { name = "Rejuvenation", expirationTime = 1012, caster = "secret" } }

        assertTrue(ns.Spells.HelpfulAuras("party1").Rejuvenation.mine)
    end)

    it("does not stop the walk reaching the auras behind it", function()
        local ns, env = loggedIn()
        env.__auras.party1 = {
            { name = "Rejuvenation", expirationTime = 1012, caster = "secret" },
            { name = "Mark of the Wild", expirationTime = 3280 },
        }

        assertEqual(3280, ns.Spells.HelpfulAuras("party1")["Mark of the Wild"].expires)
    end)

    it("reports the aura rather than only the raise", function()
        local ns, env = loggedIn()
        env.__auras.party1 =
            { { name = "Rejuvenation", expirationTime = 1012, caster = "secret" } }

        local printed = table.concat(ns.Spells.Report("party1"), "\n")

        assertMatch("Rejuvenation", printed)
        assertMatch("HELPFUL: 1 aura", printed)
    end)
end)
