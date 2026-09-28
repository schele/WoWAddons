# GatherMap Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GatherMap pins only the places the player has mined or herbed; the vMaNGOS spawn database, fishing pools, chests, confirmed/dimmed pins and "not here" all go.

**Architecture:** The spawn index is built only from `GatherMapDB.gathered`. A gather is a `LOOT_OPENED` from a `GameObject` that is either a listed herb/ore entry (hand-kept `Data/Nodes.lua`) or comes within 3 s of a successful Mining / Herbalism cast. `Spawns.Node(spawn)` gives every drawn spawn its name, kind, skill and icon: from the list, or from the saved loot item for an unlisted entry. The maps, pins, filters and settings keep their shape, minus what the database needed.

**Tech Stack:** Lua 5.1 (client 1.60, interface 16001); specs on Lua 5.4 with the repo's runner (`.\run-tests.ps1 GatherMap`).

**Spec:** [docs/superpowers/specs/2026-09-28-gathermap-rewrite-design.md](../specs/2026-09-28-gathermap-rewrite-design.md)

## Global Constraints

- Kinds are exactly `"herb"` and `"ore"`; maps are exactly `"worldmap"` and `"minimap"`.
- Continents 0 and 1 only; spawn key `string.format("%d:%d:%.1f:%.1f", continent, entry, x, y)`, positions rounded to 0.1 yard.
- A gather: `GameObject` loot source whose entry is a listed herb/ore, or any `GameObject` loot within 3 seconds of a successful player cast whose spell name equals the game's name for spell 2575 (ore) or 2366 (herb).
- Same entry within 15 yards is the same point; the same point counts once per 60 seconds.
- Unlisted entry: name = the first loot item's name (`GetLootSlotLink(1)`), icon = that item's, no skill.
- Pins: icon with a gold edge, one per spot; Shift-right-click forgets the spot; left and plain right-click pass through as now.
- Every call into the client that could raise or return a secret goes through `ns.Guarded`.
- Commit on `main`, no push, trailer `Co-Authored-By: Claude <model> <noreply@anthropic.com>` naming the model that wrote it.

## Review Focus

1. **Old saved variables from the first GatherMap** (points with `new`, pool/chest entries, a `missing` table) — load without error, keep herb/ore points, drop the rest. Task 1 tests it.
2. **Mining one vein three times** (three loot windows, seconds apart) — one count. Task 1 tests it.
3. **Forgetting a spot while its tooltip is open** — the pin goes, the tooltip closes, nothing raises. Task 1 tests it.
4. **An unlisted node gathered on a client that will not give the loot link** — still recorded, named after its kind ("Herb" / "Ore"). Task 1 tests it.
5. **A loot window on a listed herb with no Herbalism cast seen** (the herb cast is unprobed) — still counts. Task 1 tests it.

---

### Task 1: Gathers only

**Files:**
- Delete: `GatherMap/tools/` (whole folder), `GatherMap/Data/EasternKingdoms1.lua`..`3.lua`, `GatherMap/Data/Kalimdor1.lua`..`3.lua`, `GatherMap/Data/Confirmed.lua`
- Rewrite: `GatherMap/Data/Nodes.lua` (hand-kept, herb and ore only)
- Modify: `GatherMap/GatherMap.toc`, `GatherMap/GatherMap.lua`, `GatherMap/Spawns.lua`, `GatherMap/Recorder.lua`, `GatherMap/Filter.lua`, `GatherMap/Pins.lua`, `GatherMap/Settings.lua`, `GatherMap/Debug.lua`
- Tests: rewrite `tests/fixture_data.lua`, extend `tests/helpers.lua` and `tests/wow_stub.lua`; rewrite `tests/spawns_spec.lua`, `tests/recorder_spec.lua`, `tests/filter_spec.lua`; update `tests/core_spec.lua`, `tests/worldmap_spec.lua`, `tests/minimappins_spec.lua`, `tests/settings_spec.lua`, `tests/debug_spec.lua`

**Interfaces:**
- Produces: `ns.Spawns.KINDS` (`{ herb = true, ore = true }`), `ns.Spawns.LABEL` (`{ herb = "Herb", ore = "Ore" }`), `ns.Spawns.Load()`, `ns.Spawns.AddPoint(continent, entry, x, y, point) -> spawn`, `ns.Spawns.Remove(spawn)`, `ns.Spawns.Clear()`, `ns.Spawns.Node(spawn) -> { kind, name, skill?, item? }`, `ns.Spawns.All/ByKey/Near/Nearest/Key/version` as now; a spawn is `{ continent, entry, x, y, key, point, stack }` where `point` is its `ns.db.gathered[key]` table.
- `ns.Recorder.SPELLS` (`{ [2575] = "ore", [2366] = "herb" }`), `SPELL_WINDOW` (3), `VISIT` (60), `REACH` (15), `ns.Recorder.SpellSucceeded(unit, spellID)`, `ns.Recorder.LootOpened()`, `ns.Recorder.Forget(members)`, `ns.Recorder.EntryFromGUID(guid)`.
- Removed: `ns.rawSpawns`, `ns.AddSpawns`, `ns.confirmed`, `ns.AddConfirmed`, `ns.db.missing`, `ns.Filter.Confirmed`, `ns.Recorder.ToggleMissing*`, `ns.Pins.DIM`, settings `onlyConfirmed`/`showMissing`, kinds `pool`/`chest`.

- [ ] **Step 1: Keep only the herb and ore nodes, and drop the build**

From the repo root, write the hand-kept list from the current generated one, then delete the build and its data:

```bash
cd /c/src/WoWAddons/GatherMap
{ printf -- '-- The herbs and veins GatherMap knows by name, from the vMaNGOS catalog\n-- (patch 1.12), kept by hand. A gather of an entry not listed here is\n-- still recorded, named after its loot.\nlocal _, ns = ...\n\nns.AddNodes({\n'; grep -E 'kind = "(herb|ore)"' Data/Nodes.lua; printf '})\n'; } > Data/Nodes.new && mv Data/Nodes.new Data/Nodes.lua
git rm -r -q tools Data/EasternKingdoms1.lua Data/EasternKingdoms2.lua Data/EasternKingdoms3.lua Data/Kalimdor1.lua Data/Kalimdor2.lua Data/Kalimdor3.lua Data/Confirmed.lua
grep -c 'kind =' Data/Nodes.lua
```

Expected: 75 (41 herb + 34 ore entries).

In `GatherMap.toc`, replace the lines from `# BEGIN GENERATED DATA` to `# END GENERATED DATA` (inclusive) with the single line `Data\Nodes.lua`. The rest of the TOC stays in its order.

- [ ] **Step 2: Rewrite the test data and helpers**

`GatherMap/tests/fixture_data.lua` (replaces the whole file):

```lua
-- Test data in the shape of Data/Nodes.lua.
local _, ns = ...

ns.AddNodes({
    [1731] = { kind = "ore", name = "Copper Vein", skill = 1, item = 2770 },
    [3764] = { kind = "ore", name = "Tin Vein", skill = 65, item = 2771 },
    [1733] = { kind = "ore", name = "Silver Vein", skill = 75, item = 2775 },
    [1617] = { kind = "herb", name = "Silverleaf", skill = 1, item = 765 },
    [1618] = { kind = "herb", name = "Peacebloom", skill = 1, item = 2447 },
    [1619] = { kind = "herb", name = "Earthroot", skill = 15, item = 2449 },
    [2045] = { kind = "herb", name = "Stranglekelp", skill = 85, item = 3820 },
})
```

Append to `GatherMap/tests/helpers.lua`, before `return M`:

```lua
-- The player's saved gathers most specs start from, around the probe's spot
-- in Westfall (-10603.8, 1154.0), where the player stands.
M.A = "0:1731:-10603.8:1154.0"   -- Copper Vein under the player
M.B = "0:1731:-10000.0:1000.0"   -- Copper Vein 623 yards off, map 1436's corner
M.C = "0:3764:-10610.0:1160.0"   -- Tin Vein 8.6 yards off...
M.S = "0:1733:-10610.0:1160.0"   -- ...and Silver Vein at the same spot
M.D = "0:1617:-9000.0:500.0"     -- Silverleaf, off map 1436
M.E = "0:424242:-10700.0:1300.0" -- an ore the list does not know, 175 yards off
M.K = "1:1618:100.0:200.0"       -- Peacebloom on Kalimdor

--- A saved gather at `key`, gathered once, with `extra` fields merged in.
function M.point(key, extra)
    local continent, entry, x, y = key:match("^(%-?%d+):(%d+):(%-?[%d.]+):(%-?[%d.]+)$")
    local point = { continent = tonumber(continent), entry = tonumber(entry), x = tonumber(x), y = tonumber(y),
        count = 1, last = 1790000000 }
    for field, value in pairs(extra or {}) do point[field] = value end
    return point
end

--- The standard saved gathers, fresh each time.
function M.saved()
    local gathered = {}
    for _, key in ipairs({ M.A, M.B, M.C, M.S, M.D, M.K }) do
        gathered[key] = M.point(key)
    end
    gathered[M.E] = M.point(M.E, { kind = "ore", item = 9999, itemName = "Strange Ore" })
    return { gathered = gathered }
end

--- A setup for loggedIn: the standard saved gathers.
function M.withGathers(env)
    env.GatherMapDB = M.saved()
end
```

In `GatherMap/tests/wow_stub.lua`, inside `stub.newEnv` next to `env.__lootSource`, add the loot link and the spell names the client gives:

```lua
    -- The first loot slot's item link.
    env.__lootLink = nil
    function env.GetLootSlotLink() return env.__lootLink end
    -- Spell names, by ID, as this client gives them (probed 2026-09-28).
    env.__spellNames = { [2575] = "Mining", [2576] = "Mining", [2366] = "Herbalism", [2369] = "Herbalism", [133] = "Fireball" }
    env.C_Spell = { GetSpellName = function(id) return env.__spellNames[id] end }
```

- [ ] **Step 3: Write the failing specs for the index and the recorder**

`GatherMap/tests/spawns_spec.lua` (replaces the whole file):

```lua
local helpers = require("helpers")

describe("the index of gathered places", function()
    it("holds every saved gather, per continent, and nothing else", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        assertEqual(6, #ns.Spawns.All(0))
        assertEqual(1, #ns.Spawns.All(1))
    end)

    it("starts empty without saved gathers", function()
        local ns = helpers.loggedIn()
        assertEqual(0, #ns.Spawns.All(0))
    end)

    it("keeps the saved point on its spawn", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local spawn = ns.Spawns.ByKey(helpers.A)
        assertTrue(spawn.point == ns.db.gathered[helpers.A])
    end)

    it("puts places at one spot in one stack", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local tin = ns.Spawns.ByKey(helpers.C)
        assertEqual(2, #tin.stack)
        assertTrue(tin.stack == ns.Spawns.ByKey(helpers.S).stack)
    end)

    it("finds what is within reach, and the nearest of one entry", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local found = 0
        ns.Spawns.Near(0, -10603.8, 1154.0, 15, function() found = found + 1 end)
        assertEqual(3, found, "the copper under the player, and the tin and silver 8.6 yards off")
        assertEqual(helpers.A, ns.Spawns.Nearest(0, 1731, -10600, 1150, 15).key)
    end)

    it("adds a new place, rounded, for a saved point", function()
        local ns = helpers.loggedIn()
        local version = ns.Spawns.version
        local point = { continent = 0, entry = 1731, kind = "ore", count = 0 }
        local spawn = ns.Spawns.AddPoint(0, 1731, -10555.04, 1111.06, point)
        assertEqual("0:1731:-10555.0:1111.1", spawn.key)
        assertTrue(spawn.point == point)
        assertEqual(version + 1, ns.Spawns.version)
    end)

    it("takes a place out, and its spot with it when it was the last", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local tin, silver = ns.Spawns.ByKey(helpers.C), ns.Spawns.ByKey(helpers.S)
        ns.Spawns.Remove(tin)
        assertNil(ns.Spawns.ByKey(helpers.C))
        assertEqual(1, #silver.stack)
        assertEqual(5, #ns.Spawns.All(0))
        ns.Spawns.Remove(silver)
        local found = 0
        ns.Spawns.Near(0, -10610, 1160, 1, function() found = found + 1 end)
        assertEqual(0, found)
    end)

    it("clears everything", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        ns.Spawns.Clear()
        assertEqual(0, #ns.Spawns.All(0))
        assertNil(ns.Spawns.ByKey(helpers.A))
    end)
end)

describe("what a place is", function()
    it("comes from the node list when the entry is listed", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local node = ns.Spawns.Node(ns.Spawns.ByKey(helpers.A))
        assertEqual("Copper Vein", node.name)
        assertEqual("ore", node.kind)
        assertEqual(1, node.skill)
        assertEqual(2770, node.item)
    end)

    it("comes from its loot when the entry is not listed, with no skill", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local node = ns.Spawns.Node(ns.Spawns.ByKey(helpers.E))
        assertEqual("Strange Ore", node.name)
        assertEqual("ore", node.kind)
        assertNil(node.skill)
        assertEqual(9999, node.item)
    end)

    it("is named after its kind when even the loot was not known", function()
        local key = "0:555:1.0:2.0"
        local ns = helpers.loggedIn(function(env)
            env.GatherMapDB = { gathered = { [key] = helpers.point(key, { kind = "herb" }) } }
        end)
        assertEqual("Herb", ns.Spawns.Node(ns.Spawns.ByKey(key)).name)
    end)
end)

describe("gathers saved by the first GatherMap", function()
    it("keep herbs and ore, drop pools, chests and the unplaceable, and lose the not-here marks", function()
        local keep = "0:1731:-10500.0:1100.0"
        local pool = "0:180582:-10620.0:1170.0"
        local chest = "0:2843:-10700.0:1300.0"
        local ns = helpers.loggedIn(function(env)
            env.GatherMapDB = {
                gathered = {
                    [keep] = helpers.point(keep, { new = true }),
                    [pool] = helpers.point(pool),
                    [chest] = helpers.point(chest),
                    broken = { continent = 0, entry = 1731 },
                },
                missing = { [keep] = 1790000000 },
            }
        end)
        assertEqual(1, #ns.Spawns.All(0))
        assertEqual("ore", ns.db.gathered[keep].kind, "the kind comes from the list")
        assertNil(ns.db.gathered[keep].new)
        assertNil(ns.db.gathered[pool])
        assertNil(ns.db.gathered[chest])
        assertNil(ns.db.gathered.broken)
        assertNil(ns.db.missing)
    end)
end)
```

`GatherMap/tests/recorder_spec.lua` (replaces the whole file):

```lua
local helpers = require("helpers")

local function guid(entry)
    return string.format("GameObject-0-6782-0-79720-%d-00003A1A8E", entry)
end

local function cast(env, spellID)
    helpers.fire(env, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-0", spellID)
end

local function loot(env, entry, link)
    env.__lootSource = guid(entry)
    env.__lootLink = link
    helpers.fire(env, "LOOT_OPENED")
end

local HERE = "0:1731:-10603.8:1154.0"

describe("reading a loot window's source", function()
    it("takes the object's entry from its GUID", function()
        local ns = helpers.loggedIn()
        assertEqual(1731, ns.Recorder.EntryFromGUID("GameObject-0-6782-0-79720-1731-00003A1A8E"))
        assertNil(ns.Recorder.EntryFromGUID("Creature-0-6782-0-79720-1731-00003A1A8E"))
        assertNil(ns.Recorder.EntryFromGUID(nil))
    end)
end)

describe("a gather", function()
    it("of a listed vein makes a new place where the player stands", function()
        local ns, env = helpers.loggedIn()
        cast(env, 2576)
        loot(env, 1731)
        local point = ns.db.gathered[HERE]
        assertEqual(1, point.count)
        assertEqual("ore", point.kind)
        assertEqual(env.__time, point.last)
        assertEqual(HERE, ns.Spawns.ByKey(HERE).key, "and the maps can draw it")
    end)

    it("of a listed herb counts with no Herbalism cast seen", function()
        local ns, env = helpers.loggedIn()
        loot(env, 1617)
        assertEqual("herb", ns.db.gathered["0:1617:-10603.8:1154.0"].kind)
    end)

    it("of an unlisted object counts after Mining, named after its loot", function()
        local ns, env = helpers.loggedIn()
        cast(env, 2576)
        env.__now = env.__now + 2
        loot(env, 424242, "|cffffffff|Hitem:9999::::::::20:::::::|h[Strange Ore]|h|r")
        local point = ns.db.gathered["0:424242:-10603.8:1154.0"]
        assertEqual("ore", point.kind)
        assertEqual(9999, point.item)
        assertEqual("Strange Ore", point.itemName)
    end)

    it("of an unlisted object counts after Herbalism as a herb", function()
        local ns, env = helpers.loggedIn()
        cast(env, 2369)
        loot(env, 424243)
        assertEqual("herb", ns.db.gathered["0:424243:-10603.8:1154.0"].kind)
    end)

    it("of an unlisted object is recorded even when the client hides the loot link", function()
        local ns, env = helpers.loggedIn()
        env.GetLootSlotLink = function() error("secret") end
        cast(env, 2576)
        loot(env, 424242)
        local point = ns.db.gathered["0:424242:-10603.8:1154.0"]
        assertEqual("ore", point.kind)
        assertNil(point.itemName)
    end)

    it("is not an unlisted object with no gather cast, or one more than 3 seconds old", function()
        local ns, env = helpers.loggedIn()
        loot(env, 424242)
        cast(env, 133) -- Fireball
        loot(env, 424242)
        cast(env, 2576)
        env.__now = env.__now + 4
        loot(env, 424242)
        assertNil(next(ns.db.gathered))
    end)

    it("ignores another unit's cast", function()
        local ns, env = helpers.loggedIn()
        helpers.fire(env, "UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast", 2576)
        loot(env, 424242)
        assertNil(next(ns.db.gathered))
    end)

    it("counts one vein mined three times once", function()
        local ns, env = helpers.loggedIn()
        for _ = 1, 3 do
            cast(env, 2576)
            loot(env, 1731)
            env.__now = env.__now + 8
        end
        assertEqual(1, ns.db.gathered[HERE].count)
        env.__now = env.__now + 60
        cast(env, 2576)
        loot(env, 1731)
        assertEqual(2, ns.db.gathered[HERE].count, "the next visit counts")
    end)

    it("joins an earlier place of the same entry within 15 yards", function()
        local ns, env = helpers.loggedIn(helpers.withGathers)
        env.__position = { -10610.0, 1150.0, 0, 0 }
        loot(env, 1731)
        assertEqual(2, ns.db.gathered[helpers.A].count)
        assertEqual(7, #ns.Spawns.All(0) + #ns.Spawns.All(1), "no new place")
    end)

    it("ignores corpses, instances and a hidden position", function()
        local ns, env = helpers.loggedIn()
        env.__lootSource = "Creature-0-6782-0-79720-1731-00003A1A8E"
        helpers.fire(env, "LOOT_OPENED")
        env.__position = { -10603.8, 1154.0, 0, 36 }
        loot(env, 1731)
        env.__position = nil
        loot(env, 1731)
        env.GetLootSourceInfo = function() error("secret") end
        helpers.fire(env, "LOOT_OPENED")
        assertNil(next(ns.db.gathered))
    end)

    it("redraws the pins", function()
        local ns, env = helpers.loggedIn()
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        loot(env, 1731)
        assertEqual(1, count)
    end)
end)

describe("forgetting a spot", function()
    it("takes its places out of the saved gathers and the index, and redraws", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        local tin = ns.Spawns.ByKey(helpers.C)
        ns.Recorder.Forget({ tin, ns.Spawns.ByKey(helpers.S) })
        assertNil(ns.db.gathered[helpers.C])
        assertNil(ns.db.gathered[helpers.S])
        assertNil(ns.Spawns.ByKey(helpers.C))
        assertEqual(1, count)
    end)

    it("lets the next gather there count straight away", function()
        local ns, env = helpers.loggedIn()
        loot(env, 1731)
        ns.Recorder.Forget({ ns.Spawns.ByKey(HERE) })
        loot(env, 1731)
        assertEqual(1, ns.db.gathered[HERE].count)
    end)
end)

describe("/gmap reset gathered", function()
    it("asks first, then forgets everything on a second go within 10 seconds", function()
        local ns, env = helpers.loggedIn(helpers.withGathers)
        helpers.command(env, "reset gathered")
        assertTrue(ns.db.gathered[helpers.A] ~= nil, "not yet")
        assertMatch("again within 10 seconds", helpers.printed(env))
        env.__now = env.__now + 3
        helpers.command(env, "reset gathered")
        assertNil(next(ns.db.gathered))
        assertEqual(0, #ns.Spawns.All(0))
        assertMatch("Forgot every place", helpers.printed(env))
    end)

    it("asks again when the second go comes too late", function()
        local ns, env = helpers.loggedIn(helpers.withGathers)
        helpers.command(env, "reset gathered")
        env.__now = env.__now + 11
        helpers.command(env, "reset gathered")
        assertTrue(ns.db.gathered[helpers.A] ~= nil)
    end)

    it("says how to use it without 'gathered'", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "reset")
        assertMatch("/gmap reset gathered", helpers.printed(env))
    end)
end)
```

`GatherMap/tests/filter_spec.lua` (replaces the whole file):

```lua
local helpers = require("helpers")

local function shows(ns, where, key)
    return ns.Filter.Shows(where, ns.Spawns.ByKey(key))
end

describe("the filter", function()
    it("shows herbs and ore on both maps by default", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        for _, key in ipairs({ helpers.A, helpers.C, helpers.D, helpers.E }) do
            assertTrue(shows(ns, "worldmap", key), key)
            assertTrue(shows(ns, "minimap", key), key)
        end
    end)

    it("hides everything while pins are off", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        ns.SetEnabled(false)
        assertFalse(shows(ns, "worldmap", helpers.A))
    end)

    it("hides a kind on one map and not the other", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        ns.settings.minimap.kinds.herb = false
        assertFalse(shows(ns, "minimap", helpers.D))
        assertTrue(shows(ns, "worldmap", helpers.D))
    end)

    it("hides a node by name, listed or not", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        ns.settings.worldmap.hidden["Copper Vein"] = true
        ns.settings.worldmap.hidden["Strange Ore"] = true
        assertFalse(shows(ns, "worldmap", helpers.A))
        assertFalse(shows(ns, "worldmap", helpers.E))
        assertTrue(shows(ns, "worldmap", helpers.C))
    end)

    it("hides what the skill cannot gather yet, unless asked not to", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        assertFalse(shows(ns, "worldmap", helpers.S), "Silver needs 75, Mining is 70")
        ns.settings.worldmap.hideUngatherable = false
        assertTrue(shows(ns, "worldmap", helpers.S))
    end)

    it("hides grey nodes when asked", function()
        local ns = helpers.loggedIn(function(env)
            helpers.withGathers(env)
            env.__skills[3] = { "Mining", false, 150 }
        end)
        ns.settings.minimap.hideGrey = true
        assertFalse(shows(ns, "minimap", helpers.A), "Copper is grey at 150")
        assertTrue(shows(ns, "minimap", helpers.C), "Tin is green at 150")
    end)

    it("never hides an unlisted node for skill, having none", function()
        local ns = helpers.loggedIn(function(env)
            helpers.withGathers(env)
            env.__skills = { { "Professions", true } }
        end)
        ns.settings.worldmap.hideGrey = true
        assertTrue(shows(ns, "worldmap", helpers.E))
        assertFalse(shows(ns, "worldmap", helpers.A))
    end)

    it("gives the members of a spot it shows, in order", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local shown = ns.Filter.Shown("worldmap", ns.Spawns.ByKey(helpers.C).stack)
        assertEqual(1, #shown, "Silver is out of reach at Mining 70")
        assertEqual(helpers.C, shown[1].key)
    end)
end)
```

- [ ] **Step 4: Run them to see them fail**

Run: `.\run-tests.ps1 GatherMap`
Expected: FAIL — among others, `spawns_spec` counts 0 places (the index still loads `ns.rawSpawns`), `recorder_spec` finds no `UNIT_SPELLCAST_SUCCEEDED` handling and no `Forget`, `filter_spec` cannot name the unlisted ore.

- [ ] **Step 5: The shell — no spawns, no confirmed, no missing**

In `GatherMap/GatherMap.lua`:

- Delete `ns.rawSpawns = {}`, `ns.confirmed = {}` and their comments, and the functions `ns.AddConfirmed` and `ns.AddSpawns`. Keep `ns.Nodes` and `ns.AddNodes`, with the comment above them changed to: `-- The herbs and veins known by name, handed over by Data/Nodes.lua.`
- In `ensureDatabase`, replace the block that creates `GatherMapDB.missing` with:

```lua
    -- The first GatherMap's "not here" marks: nothing uses them now.
    GatherMapDB.missing = nil
```

- [ ] **Step 6: The index — gathered places only**

Replace the whole of `GatherMap/Spawns.lua` with:

```lua
local addonName, ns = ...

-- Every place the player has gathered, from GatherMapDB.gathered. Each is
-- { continent, entry, x, y, key, point, stack }: `point` is its saved
-- record, and `stack` every place at that same spot, this one included (one
-- table, shared by all of them). Filed in a grid of 200-yard cells per
-- continent, so the minimap and the recorder look only at the few cells
-- around the player.

local Spawns = {}
ns.Spawns = Spawns

local CELL = 200
Spawns.CELL = CELL
-- Bumped by every change, so a cache built from the index can tell it is
-- out of date.
Spawns.version = 0

Spawns.KINDS = { herb = true, ore = true }
-- The name of a place whose entry is not listed and whose loot was unknown.
Spawns.LABEL = { herb = "Herb", ore = "Ore" }

local lists, grids, byKey, stacks = {}, {}, {}, {}

function Spawns.Key(continent, entry, x, y)
    return string.format("%d:%d:%.1f:%.1f", continent, entry, x, y)
end

local function cellKey(x, y)
    return math.floor(x / CELL) .. ":" .. math.floor(y / CELL)
end

local function spotKey(continent, x, y)
    return string.format("%d:%.1f:%.1f", continent, x, y)
end

local function add(continent, entry, x, y, point)
    local key = Spawns.Key(continent, entry, x, y)
    if byKey[key] then
        return byKey[key]
    end

    local spawn = { continent = continent, entry = entry, x = x, y = y, key = key, point = point }
    byKey[key] = spawn

    -- Places at one spot (Tin, then Silver, where they alternate) are one
    -- stack, drawn as one pin.
    local spot = spotKey(continent, x, y)
    local stack = stacks[spot]
    if not stack then
        stack = {}
        stacks[spot] = stack
    end
    table.insert(stack, spawn)
    spawn.stack = stack

    lists[continent] = lists[continent] or {}
    table.insert(lists[continent], spawn)

    grids[continent] = grids[continent] or {}
    local cell = cellKey(x, y)
    grids[continent][cell] = grids[continent][cell] or {}
    table.insert(grids[continent][cell], spawn)

    Spawns.version = Spawns.version + 1
    return spawn
end

local function removeFrom(list, item)
    for index = #(list or {}), 1, -1 do
        if list[index] == item then
            table.remove(list, index)
        end
    end
end

local function round(value)
    return math.floor(value * 10 + 0.5) / 10
end

--- A saved point's kind: the list's for a listed entry, else what was
-- saved. Nil for anything neither herb nor ore (the first GatherMap's pools
-- and chests).
local function kindOf(point)
    local node = ns.Nodes[point.entry]
    local kind = node and node.kind or point.kind
    return Spawns.KINDS[kind] and kind or nil
end

--- Index the saved gathers, in key order. Once, at login. A point that
-- cannot be placed, or is no herb or ore, is dropped from the saved
-- variables.
function Spawns.Load()
    local keys = {}
    for key in pairs(ns.db.gathered) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    for _, key in ipairs(keys) do
        local point = ns.db.gathered[key]
        local kind = type(point) == "table" and type(point.entry) == "number" and kindOf(point)
        if kind and type(point.continent) == "number" and type(point.x) == "number" and type(point.y) == "number" then
            point.kind = kind
            point.new = nil
            add(point.continent, point.entry, round(point.x), round(point.y), point)
        else
            ns.db.gathered[key] = nil
        end
    end
end

--- A new place for the saved `point`, rounded to a tenth of a yard.
function Spawns.AddPoint(continent, entry, x, y, point)
    return add(continent, entry, round(x), round(y), point)
end

--- Take `spawn` out of the index. Its saved point is the caller's to delete.
function Spawns.Remove(spawn)
    if byKey[spawn.key] ~= spawn then
        return
    end
    byKey[spawn.key] = nil
    removeFrom(spawn.stack, spawn)
    if #spawn.stack == 0 then
        stacks[spotKey(spawn.continent, spawn.x, spawn.y)] = nil
    end
    removeFrom(lists[spawn.continent], spawn)
    removeFrom((grids[spawn.continent] or {})[cellKey(spawn.x, spawn.y)], spawn)
    Spawns.version = Spawns.version + 1
end

function Spawns.Clear()
    lists, grids, byKey, stacks = {}, {}, {}, {}
    Spawns.version = Spawns.version + 1
end

--- What a place is: the list's { kind, name, skill, item } for a listed
-- entry; else, from what was saved, its loot's name and item and no skill.
function Spawns.Node(spawn)
    local node = ns.Nodes[spawn.entry]
    if node then
        return node
    end
    local point = spawn.point or {}
    return { kind = point.kind, name = point.itemName or Spawns.LABEL[point.kind] or "?", item = point.item }
end

function Spawns.All(continent)
    return lists[continent] or {}
end

function Spawns.ByKey(key)
    return byKey[key]
end

--- Call fn(spawn) for every place within `radius` yards of (x, y).
function Spawns.Near(continent, x, y, radius, fn)
    local grid = grids[continent]
    if not grid then
        return
    end
    local limit = radius * radius
    for cx = math.floor((x - radius) / CELL), math.floor((x + radius) / CELL) do
        for cy = math.floor((y - radius) / CELL), math.floor((y + radius) / CELL) do
            for _, spawn in ipairs(grid[cx .. ":" .. cy] or {}) do
                local dx, dy = spawn.x - x, spawn.y - y
                if dx * dx + dy * dy <= limit then
                    fn(spawn)
                end
            end
        end
    end
end

--- The nearest place of `entry` within `radius` yards of (x, y), or nil.
function Spawns.Nearest(continent, entry, x, y, radius)
    local best, bestDistance
    Spawns.Near(continent, x, y, radius, function(spawn)
        if spawn.entry == entry then
            local distance = (spawn.x - x) ^ 2 + (spawn.y - y) ^ 2
            if not bestDistance or distance < bestDistance then
                best, bestDistance = spawn, distance
            end
        end
    end)
    return best
end

ns.OnLogin(Spawns.Load)
```

- [ ] **Step 7: The recorder — by what the player did**

Replace the whole of `GatherMap/Recorder.lua` with:

```lua
local addonName, ns = ...

-- Turns a gather into a place: a loot window from a GameObject that is a
-- listed herb or vein, or that opens just after the player's Mining or
-- Herbalism cast. The object's entry is the sixth field of the loot's source
-- GUID; the place is where the player stands.

local Recorder = {}
ns.Recorder = Recorder

-- The gather spells, by the ID whose name the game gives them: mining a vein
-- casts 2576, named "Mining" like 2575 (probed 2026-09-28). The herb cast is
-- expected to be named "Herbalism" like 2366; listed herbs count regardless.
Recorder.SPELLS = { [2575] = "ore", [2366] = "herb" }
-- How long after a gather cast its loot window can open, in seconds.
Recorder.SPELL_WINDOW = 3
-- A place gathered again within this many seconds is the same visit: a vein
-- is mined several times, each with its own loot window.
Recorder.VISIT = 60
-- How far from an earlier place of the same entry a gather joins it, in yards.
Recorder.REACH = 15

function Recorder.EntryFromGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local entry = guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return entry and tonumber(entry)
end

local function spellName(id)
    return ns.Guarded(function()
        if C_Spell and C_Spell.GetSpellName then
            return C_Spell.GetSpellName(id)
        end
        return (GetSpellInfo(id))
    end)
end

-- Spell name -> kind, read from the game the first time it has them.
local kindByName

local function kindOfSpell(spellID)
    if Recorder.SPELLS[spellID] then
        return Recorder.SPELLS[spellID]
    end
    if not kindByName then
        local names, any = {}, false
        for id, kind in pairs(Recorder.SPELLS) do
            local name = spellName(id)
            if name then
                names[name] = kind
                any = true
            end
        end
        kindByName = any and names or nil
    end
    local name = kindByName and spellName(spellID)
    return name and kindByName[name]
end

local lastKind, lastCast

function Recorder.SpellSucceeded(unit, spellID)
    if unit ~= "player" then
        return
    end
    local kind = kindOfSpell(spellID)
    if kind then
        lastKind, lastCast = kind, GetTime()
    end
end

--- The first loot slot's item: its ID and name, or nil if the client will not say.
local function lootItem()
    return ns.Guarded(function()
        local link = GetLootSlotLink(1)
        if type(link) ~= "string" then
            return nil
        end
        return { item = tonumber(link:match("item:(%d+)")), name = link:match("%[(.-)%]") }
    end)
end

-- Place key -> GetTime() of its last counted gather.
local lastSeen = {}

function Recorder.LootOpened()
    local entry = Recorder.EntryFromGUID(ns.Guarded(function()
        return (GetLootSourceInfo(1))
    end))
    if not entry then
        return
    end

    local now = GetTime()
    local listed = ns.Nodes[entry]
    local kind = listed and ns.Spawns.KINDS[listed.kind] and listed.kind or nil
    if not kind and lastCast and now - lastCast <= Recorder.SPELL_WINDOW then
        kind = lastKind
    end
    if not kind then
        return
    end

    local x, y, _, continent = UnitPosition("player")
    if type(x) ~= "number" or (continent ~= 0 and continent ~= 1) then
        return
    end

    local spawn = ns.Spawns.Nearest(continent, entry, x, y, Recorder.REACH)
    if spawn then
        if lastSeen[spawn.key] and now - lastSeen[spawn.key] < Recorder.VISIT then
            return
        end
    else
        local point = { continent = continent, entry = entry, kind = kind, count = 0 }
        if not listed then
            local loot = lootItem()
            if loot then
                point.item, point.itemName = loot.item, loot.name
            end
        end
        spawn = ns.Spawns.AddPoint(continent, entry, x, y, point)
        point.x, point.y = spawn.x, spawn.y
        ns.db.gathered[spawn.key] = point
    end

    lastSeen[spawn.key] = now
    spawn.point.count = (spawn.point.count or 0) + 1
    spawn.point.last = time()
    ns.Refresh()
end

--- Forget the places in `members` (a spot's, as a pin shows them): out of
-- the saved gathers and off both maps.
function Recorder.Forget(members)
    for _, spawn in ipairs(members) do
        ns.db.gathered[spawn.key] = nil
        lastSeen[spawn.key] = nil
        ns.Spawns.Remove(spawn)
    end
    ns.Refresh()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        ns.Guarded(function() Recorder.SpellSucceeded(unit, spellID) end)
    else
        ns.Guarded(Recorder.LootOpened)
    end
end)

local resetAsked

ns.RegisterCommand("reset", "Forget every place you have gathered: /gmap reset gathered", function(rest)
    if rest ~= "gathered" then
        ns.Print("To forget every place you have gathered: /gmap reset gathered")
        return
    end

    local now = GetTime()
    if resetAsked and now - resetAsked <= 10 then
        resetAsked = nil
        for key in pairs(ns.db.gathered) do
            ns.db.gathered[key] = nil
        end
        lastSeen = {}
        ns.Spawns.Clear()
        ns.Print("Forgot every place you have gathered.")
        ns.Refresh()
        return
    end

    resetAsked = now
    ns.Print("This forgets every place you have gathered, on every character. "
        .. "Type /gmap reset gathered again within 10 seconds to do it.")
end)
```

- [ ] **Step 8: The filter — herbs and ore, named by Spawns.Node**

Replace the whole of `GatherMap/Filter.lua` with:

```lua
local addonName, ns = ...

-- Whether a place is shown on the world map or the minimap. The one place
-- every filter is applied, so the two maps can never disagree about what a
-- setting means.

local Filter = {}
ns.Filter = Filter

local function filters(pinSize)
    return {
        kinds = { herb = true, ore = true },
        hidden = {},
        hideUngatherable = true,
        hideGrey = false,
        pinSize = pinSize,
    }
end

ns.AddDefaults({
    worldmap = filters(12),
    minimap = filters(10),
})

--- Whether `spawn` is shown on `where`: "worldmap" or "minimap".
function Filter.Shows(where, spawn)
    local settings = ns.settings
    if not settings.enabled then
        return false
    end

    local node = ns.Spawns.Node(spawn)
    local chosen = settings[where]
    if not node.kind or not chosen.kinds[node.kind] or chosen.hidden[node.name] then
        return false
    end

    if node.skill then
        local color = ns.Skills.Color(node.skill, ns.Skills.Get(node.kind))
        if chosen.hideUngatherable and color == "red" then
            return false
        end
        if chosen.hideGrey and color == "grey" then
            return false
        end
    end

    return true
end

--- The members of `stack` (a spot's places) shown on `where`, in its order.
function Filter.Shown(where, stack)
    local shown = {}
    for _, spawn in ipairs(stack) do
        if Filter.Shows(where, spawn) then
            shown[#shown + 1] = spawn
        end
    end
    return shown
end
```

- [ ] **Step 9: Pins — every pin is a gather; Shift-right-click forgets**

In `GatherMap/Pins.lua`:

- Header comment becomes: `-- A pin, the same on the world map and the minimap, one per spot however many places share it: the icon of what grows there with a gold edge, a tooltip, and a Shift-right-click to forget the spot.` (wrapped as the file's other comments).
- Delete `Pins.DIM` and its comment; `Pins.KIND_ICONS` keeps only `herb` and `ore`.
- Replace `Pins.ShowTooltip` with:

```lua
--- The tooltip for a pin's `members`, the places at its spot it shows:
-- their names, each one's skill, how often, and how to forget the spot.
function Pins.ShowTooltip(owner, members)
    if not GameTooltip or #members == 0 then
        return
    end
    local names, nodes, count = {}, {}, 0
    for _, spawn in ipairs(members) do
        local node = ns.Spawns.Node(spawn)
        nodes[#nodes + 1] = node
        names[#names + 1] = node.name
        count = count + ((spawn.point and spawn.point.count) or 0)
    end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(joinNames(names))
    for _, node in ipairs(nodes) do
        if node.skill then
            local rgb = ns.Skills.RGB[ns.Skills.Color(node.skill, ns.Skills.Get(node.kind))]
            GameTooltip:AddLine(string.format("%s %d", ns.Skills.LABEL[node.kind], node.skill), rgb[1], rgb[2], rgb[3])
        end
    end
    GameTooltip:AddLine(string.format("Gathered here %d %s", count, count == 1 and "time" or "times"), 1, 1, 1)
    GameTooltip:AddLine("Shift-right-click: forget this place", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end
```

- Replace the local `toggleMissing` with:

```lua
-- The pin under the cursor is gone once the maps redraw, and so is its
-- tooltip.
local function forget(pin)
    ns.Recorder.Forget(pin.members)
    if GameTooltip then
        GameTooltip:Hide()
    end
end
```

  and in `Pins.Create`'s `OnMouseUp`, call `forget(self)` where it called `toggleMissing(self)`. Update `Pins.Create`'s comment: Shift-right-click forgets the spot.
- Replace `Pins.Set` with:

```lua
--- Point `pin` at a spot's `members` shown (at least one), `size` pixels
-- across, drawn as the first, and show it.
function Pins.Set(pin, members, size)
    pin.spawn = members[1]
    pin.members = members
    pin:SetSize(size, size)
    pin.icon:SetTexture(Pins.Icon(ns.Spawns.Node(members[1])))
    pin.edge:Show()
    pin:Show()
end
```

- [ ] **Step 10: Settings and debug**

In `GatherMap/Settings.lua`:

- `KINDS = { "herb", "ore" }` and `KIND_LABEL = { herb = "Herbs", ore = "Ore" }`.
- `Panel.NodeNames(kind)` also lists the names of unlisted places the player gathered. Replace its first loop with:

```lua
    local seen, names = {}, {}
    local function take(node)
        if node.kind == kind and node.name and not seen[node.name] then
            seen[node.name] = true
            table.insert(names, { name = node.name, skill = node.skill })
        end
    end
    for _, node in pairs(ns.Nodes) do
        take(node)
    end
    for _, continent in ipairs({ 0, 1 }) do
        for _, spawn in ipairs(ns.Spawns.All(continent)) do
            take(ns.Spawns.Node(spawn))
        end
    end
```

  (the sort after it stays).
- Delete the `addFilter("onlyConfirmed", ...)` and `addFilter("showMissing", ...)` lines.
- The hint becomes: `"Each row has two boxes: the world map, then the minimap. Open a kind with + to pick its nodes one by one. Pins are the places you have mined or herbed; Shift-right-click a pin to forget it."`

In `GatherMap/Debug.lua`, the first line becomes:

```lua
    say("Data: %d node types listed; %d places gathered: %d Eastern Kingdoms, %d Kalimdor.",
        count(ns.Nodes), count(ns.db.gathered), #ns.Spawns.All(0), #ns.Spawns.All(1))
```

- [ ] **Step 11: Update the remaining specs**

- `tests/core_spec.lua`: delete the assertions on `ns.db.missing`, `ns.rawSpawns` and `ns.confirmed`; the data test asserts only `ns.Nodes[1731].name == "Copper Vein"`. Add:

```lua
    it("drop the first GatherMap's not-here marks", function()
        local ns = helpers.loggedIn(function(env) env.GatherMapDB = { gathered = {}, missing = { x = 1 } } end)
        assertNil(ns.db.missing)
    end)
```

- `tests/worldmap_spec.lua` and `tests/minimappins_spec.lua`: every test logs in with `helpers.withGathers` (compose with any other setup: `function(env) helpers.withGathers(env) ... end`). Delete the tests about dimmed pins, confirmed pins, "not here" marks and `showMissing`, and the `draws no more than its limit` / minimap `stop at their limit` tests keep working by adding points with `ns.Spawns.AddPoint(0, 1731, x, y, { continent = 0, entry = 1731, kind = "ore", count = 1 })`. Expected pins now:
  - world map on 1436 (default skills): one pin each for A, B, the Tin/Silver spot (showing Tin), and E — entries `1731,1731,3764,424242`;
  - minimap from the default position at zoom 0: A, the Tin/Silver spot, E — `1731,3764,424242`; at zoom 5 or indoors: `1731,3764`.
  Replace the old "not here" tests with:

```lua
    it("forgets a spot on a Shift-right-click, and the pin and tooltip go", function()
        local ns, env = opened()
        local pin = pinFor(ns, helpers.A)
        pin.scripts.OnEnter(pin)
        env.__modifiers.shift = true
        pin.scripts.OnMouseUp(pin, "RightButton")
        assertNil(ns.db.gathered[helpers.A])
        assertEqual("1731,3764,424242", shownEntries(ns))
        assertFalse(env.GameTooltip:IsShown())
    end)

    it("says how often and how to forget, and names an unlisted node after its loot", function()
        local ns, env = opened()
        local pin = pinFor(ns, helpers.E)
        pin.scripts.OnEnter(pin)
        assertEqual("Strange Ore", env.GameTooltip.text)
        assertEqual("Gathered here 1 time", env.GameTooltip.lines[1].text)
        assertEqual("Shift-right-click: forget this place", env.GameTooltip.lines[2].text)
        assertEqual(1000 + 9999, pin.icon:GetTexture())
        assertTrue(pin.edge:IsShown())
    end)
```

  (`opened` there logs in with `helpers.withGathers` and shows the world map.)
- `tests/settings_spec.lua`: drop `onlyConfirmed` / `showMissing` and the `pool` / `chest` kind rows from its tests; add that `Panel.NodeNames("ore")` includes `"Strange Ore"` after logging in with `helpers.withGathers`.
- `tests/debug_spec.lua`: the first expectation becomes `assertMatch("Data: 7 node types listed; 7 places gathered: 6 Eastern Kingdoms, 1 Kalimdor", printed)`, logging in with `helpers.withGathers`.

- [ ] **Step 12: Run the tests to see them pass**

Run: `.\run-tests.ps1 GatherMap`
Expected: PASS, every spec; no Node tests run (the `tools` folder is gone).
Also: `grep -rnE "confirmed|missing|\"pool\"|\"chest\"|rawSpawns|AddSpawns|DIM" GatherMap/*.lua` finds nothing but the `missing = nil` line and its comment in GatherMap.lua.

- [ ] **Step 13: Commit**

```bash
git add -A GatherMap
git commit -m "GatherMap: only the places you have mined or herbed

Co-Authored-By: Claude <model> <noreply@anthropic.com>"
```

---

### Task 2: Docs, package, in-game check

**Files:**
- Rewrite: `GatherMap/README.md`
- Modify: `README.md` (the GatherMap row), `GatherMap/GatherMap.toc` (the `## Notes:` line)

- [ ] **Step 1: The README**

`GatherMap/README.md`:

```markdown
# GatherMap (World of Warcraft AddOn)

Pins on the world map and the minimap for every vein you have mined and every
herb you have picked, so you can find your way back. Nothing else: no
database of spawns, no guesses.

## How it records

Mine or pick as usual. When a loot window opens from a herb or vein,
GatherMap saves the spot where you stand. It knows about 75 kinds of herb and
vein by name; anything else you gather straight after a Mining or Herbalism
cast is saved too, named after what it dropped. A vein you mine three times
counts once per visit. Saved per account, so every character adds to the
same map.

Hover a pin for what grows there, the skill it needs (in its skill-up
colour) and how often you have gathered there. **Shift-right-click** a pin to
forget that place. A left click or a plain right-click on a world map pin
does what it would on the map itself.

## Filters

Each has a box for the world map and one for the minimap, in `/gmap`:

- Herbs, ore; open a kind with **+** to pick its nodes one by one, or
  **All** / **None**.
- Hide nodes your skill cannot gather yet (on by default).
- Hide grey nodes, the ones that give no more skill-ups.
- Pin size.

If you have collapsed the Professions header in your skill list, GatherMap
keeps the skills it last saw until you open it again.

## Commands

| Command | What it does |
|---|---|
| `/gmap` | Open the settings |
| `/gmap toggle` | Show or hide every pin |
| `/gmap minimap` | Hide or show the minimap button |
| `/gmap where` | Where the game and GatherMap put you on the map |
| `/gmap debug` | What GatherMap has, step by step, if pins are missing |
| `/gmap reset gathered` | Forget every place you have gathered (asks first) |
| `/gmap help` | List the commands |

The minimap button: click to show or hide every pin, right-click for the
settings, drag to move it.

## Install

    .\package.ps1 GatherMap -Install

See the [repo README](../README.md) for packaging and test commands.
```

In the root `README.md`, the GatherMap row becomes:

```markdown
| [GatherMap](GatherMap/) | Pins on the world map and minimap for every vein you have mined and herb you have picked |
```

In `GatherMap/GatherMap.toc`, `## Notes:` becomes `## Notes: Pins for the veins you have mined and the herbs you have picked.`

- [ ] **Step 2: Test and install**

Run: `.\run-tests.ps1` (every addon) — expected all green.
Run: `.\package.ps1 GatherMap -Install` — expected `Installed -> ...\_classic_beta_\Interface\AddOns\GatherMap`.

- [ ] **Step 3: Commit**

```bash
git add GatherMap/README.md GatherMap/GatherMap.toc README.md
git commit -m "GatherMap: README for the gathers-only rewrite

Co-Authored-By: Claude <model> <noreply@anthropic.com>"
```

- [ ] **Step 4: In game (the user)**

1. `/reload`: no error. `/gmap debug`: "N places gathered" matches what you had (herbs and ore only).
2. Mine a vein three times: one pin appears on the minimap and the world map; the tooltip says "Gathered here 1 time".
3. Shift-right-click it: gone from both maps. A plain right-click on a world map pin zooms the map out; a left click on a zone still opens it.
4. `/gmap`: Herbs and Ore rows, the node checklists, skill filters, pin sizes.
