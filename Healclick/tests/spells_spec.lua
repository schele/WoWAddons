local helpers = require("helpers")

local FILES = { "Healclick.lua", "Spells.lua" }

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
