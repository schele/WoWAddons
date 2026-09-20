# TrinketBar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A draggable bar of every trinket the character is carrying, where a left-click equips into trinket slot 1 and a right-click into slot 2.

**Architecture:** A fixed pool of Blizzard secure buttons, created once at login and re-pointed out of combat. Each button carries an `/equipslot` macro, so the player's click does the equipping and the addon never calls an equip function. Everything the client is asked about items lives in one file with no frames in it, so its answers can be tested without a client.

**Tech Stack:** Lua 5.1-flavoured (WoW runtime), Lua 5.4 for tests, the repo's own spec runner, PowerShell for packaging.

**Spec:** [docs/superpowers/specs/2026-09-20-trinketbar-design.md](../specs/2026-09-20-trinketbar-design.md)

## Global Constraints

- Runtime Lua is 5.1-flavoured: no `goto`, integer division, or `table.unpack` in addon files. Test files run under Lua 5.4 and may.
- `run-tests.ps1` and `package.ps1` are shared; neither is modified.
- No file outside `TrinketBar/` may be edited, except `README.md` at the repo root in the final task.
- Comments explain *why*. No comment that restates the line below it.
- Every secure write (`SetAttribute`, `SetPoint`, `SetSize`, `Show`, `Hide` on a secure button or anything holding one) happens out of combat or not at all.
- Every client read that could come back as a secret value goes through `ns.Guarded`.
- Target clients: Classic Era 1.15.x (`11509`) and the 1.60.x Classic beta (`16001`).
- `TrinketBar/icon.tga` and `TrinketBar/logo.tga` already exist. Do not regenerate them.

## File Structure

| File | Responsibility |
|---|---|
| `TrinketBar/TrinketBar.toc` | Manifest, load order, `SavedVariables: TrinketBarDB` |
| `TrinketBar/TrinketBar.lua` | Namespace, defaults, `ns.Print`, `ns.Guarded`, settings and command registries, slash handling, login dispatch |
| `TrinketBar/Items.lua` | What the client knows about items. No frames |
| `TrinketBar/Bar.lua` | The button pool, layout, drag anchor, combat queue, events |
| `TrinketBar/Settings.lua` | The options panel: three settings and a heading |
| `TrinketBar/README.md` | What it is, how to install, what it cannot do |
| `TrinketBar/tests/runner.lua` | Spec runner (copied unchanged) |
| `TrinketBar/tests/helpers.lua` | Load the addon into a stubbed environment |
| `TrinketBar/tests/wow_stub.lua` | The stubbed client |
| `TrinketBar/tests/*_spec.lua` | One spec per addon file |

---

### Task 1: Scaffolding that loads and answers a slash command

**Files:**
- Create: `TrinketBar/TrinketBar.toc`
- Create: `TrinketBar/TrinketBar.lua`
- Create: `TrinketBar/tests/runner.lua`
- Create: `TrinketBar/tests/helpers.lua`
- Create: `TrinketBar/tests/wow_stub.lua`
- Test: `TrinketBar/tests/addon_spec.lua`

**Interfaces:**
- Consumes: nothing.
- Produces: `ns.PREFIX`, `ns.Print(message)`, `ns.AddDefaults(table)`, `ns.applyDefaults(target, source)`, `ns.Guarded(fn, whenUnknown)`, `ns.RegisterSetting(table)`, `ns.RegisterCommand(name, help, handler)`, `ns.RegisterColumn(key, title)`, `ns.OnLogin(handler)`, `ns.settings`, `ns.db`, `ns.SettingValue(setting)`, `ns.SetSettingValue(setting, value)`, `ns.ShowHelp()`. Globals `SLASH_TRINKETBAR1 = "/trinketbar"`, `SLASH_TRINKETBAR2 = "/tb"`, `SlashCmdList.TRINKETBAR`.

- [ ] **Step 1: Copy the three files that are not TrinketBar's to write**

```bash
cd C:/src/WoWAddons
mkdir -p TrinketBar/tests
cp ClickHeal/tests/runner.lua TrinketBar/tests/runner.lua
cp ClickHeal/ClickHeal.lua TrinketBar/TrinketBar.lua
cp ClickHeal/tests/wow_stub.lua TrinketBar/tests/wow_stub.lua
```

`runner.lua` is copied unchanged and is not edited again. The other two are starting points, edited in the next steps.

- [ ] **Step 2: Strip TrinketBar.lua down to the core**

Open `TrinketBar/TrinketBar.lua` and make exactly these changes:

1. `ns.PREFIX = "|cffcc88ffTrinketBar|r"` (violet, matching the icon).
2. Replace every `/ch ` in help text with `/tb `.
3. `SLASH_CLICKHEAL1` → `SLASH_TRINKETBAR1 = "/trinketbar"`, `SLASH_CLICKHEAL2` → `SLASH_TRINKETBAR2 = "/tb"`, `SlashCmdList.CLICKHEAL` → `SlashCmdList.TRINKETBAR`.
4. In the comment above `runCommand`, change "the same as `/fp` and `/url` do. Three addons" to "the same as `/fp`, `/url` and `/ch` do. Four addons".
5. Change the saved-variables global from `ClickHealDB` to `TrinketBarDB` wherever it appears.

Leave `applyDefaults`, `ns.Guarded`, the settings registry, the command registry, `ns.OnLogin` and the event frame exactly as they are. They are the parts every addon in this repo shares, and they are already correct.

- [ ] **Step 3: Write the toc**

`TrinketBar/TrinketBar.toc`:

```
## Interface: 11509, 16001
## Title: TrinketBar
## Notes: Every trinket you are carrying, on a bar. Left-click to equip in slot 1, right-click for slot 2.
## IconTexture: Interface\AddOns\TrinketBar\icon
## Author: You
## Version: 0.1.0
## SavedVariables: TrinketBarDB

TrinketBar.lua
Items.lua
Bar.lua
Settings.lua
```

`Items.lua`, `Bar.lua` and `Settings.lua` do not exist yet. The toc lists them now because the load order is a decision, not an afterthought: `Items` before `Bar` because `Bar` asks it questions, `Settings` last because it renders what the others declared.

- [ ] **Step 4: Write the test helpers**

`TrinketBar/tests/helpers.lua`:

```lua
local stub = require("wow_stub")

local M = {}

M.FILES = {
    "TrinketBar.lua",
    "Items.lua",
    "Bar.lua",
    "Settings.lua",
}

--- Load the addon's files into a stubbed environment, the way WoW would:
-- in .toc order, each chunk receiving (addonName, privateTable).
-- Pass a shorter list while the later files do not exist yet.
function M.loadAddon(files)
    local env = stub.newEnv()
    local ns = {}

    for _, path in ipairs(files or M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("TrinketBar", ns)
    end

    return ns, env
end

function M.fire(env, event, ...)
    local frames = {}
    for index, frame in ipairs(env.__frames) do
        frames[index] = frame
    end

    for _, frame in ipairs(frames) do
        if frame.registeredEvents[event] then
            frame:Fire(event, ...)
        end
    end
end

function M.login(ns, env)
    M.fire(env, "ADDON_LOADED", "TrinketBar")
    M.fire(env, "PLAYER_LOGIN")
end

function M.command(env, text)
    env.SlashCmdList.TRINKETBAR(text)
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

--- A button's secure attributes, as a plain table.
function M.attrs(button)
    return button.attributes
end

return M
```

- [ ] **Step 5: Point the stub at this addon**

In `TrinketBar/tests/wow_stub.lua`, change `env.ClickHealDB` to `env.TrinketBarDB` if it appears, and delete the ClickHeal-specific fixtures that this addon has no use for: `env.__spells`, `env.__spellTextures`, `env.__spellCooldowns`, `env.__spellRanges`, `env.__spellHelpful`, `env.__spellIDs`, `env.__spellbook`, `env.__learnSpells`, `env.__learnSpellAt`, `env.C_Spell`, `env.C_SpellBook`, `env.Enum.SpellBookSpellBank`, `env.PlayerFrame`, `env.PartyFrame`, `env.__auras`, `env.C_UnitAuras`, `env.units`, and every `Unit*` function.

Keep everything else: the widget factory, `refuseInCombat`, `__setCombat`, `__frames`, `__printed`, `__timers`, `__runTimers`, `__tickers`, `__tick`, `__mouseOver`, `__cursorY`, `GetCursorPosition`, `__missingTemplates`, the Settings API stubs and `GameMenuFrame`. Those are client behaviour, not ClickHeal's fixtures, and every one of them was added because its absence hid a real defect.

- [ ] **Step 6: Write the failing test**

`TrinketBar/tests/addon_spec.lua`:

```lua
local helpers = require("helpers")

local ONLY_CORE = { "TrinketBar.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(ONLY_CORE)
    helpers.login(ns, env)
    return ns, env
end

describe("the database", function()
    it("exists once the player is logged in", function()
        local ns = loggedIn()
        assertTrue(ns.db ~= nil)
    end)

    it("keeps a value that was already saved", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        env.TrinketBarDB = { bar = { locked = true } }
        helpers.login(ns, env)

        assertTrue(ns.db.bar.locked)
    end)
end)

describe("the slash command", function()
    it("lists the commands for a bare /tb", function()
        -- The same as /fp, /url and /ch. Four addons whose login lines sit
        -- together must not disagree about what a bare command does.
        local ns, env = loggedIn()
        helpers.command(env, "")

        assertMatch("Commands:", helpers.printed(env))
    end)

    it("says so for a command it does not have", function()
        local ns, env = loggedIn()
        helpers.command(env, "nonsense")

        assertMatch("Unknown command: nonsense", helpers.printed(env))
    end)

    it("runs a registered command", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        local ran = false
        ns.RegisterCommand("poke", "pokes", function() ran = true end)
        helpers.login(ns, env)

        helpers.command(env, "poke")
        assertTrue(ran)
    end)
end)

describe("guarding a client read", function()
    it("returns what the call returned when nothing raises", function()
        local ns = loggedIn()
        assertEqual(7, ns.Guarded(function() return 7 end, 0))
    end)

    it("returns the fallback when the call raises", function()
        -- A secret value raises when it is inspected, not when it is
        -- fetched, so the branch has to be inside the guard too.
        local ns = loggedIn()
        assertEqual(0, ns.Guarded(function() error("secret value") end, 0))
    end)
end)
```

- [ ] **Step 7: Run it and watch it fail**

```powershell
cd C:\src\WoWAddons
.\run-tests.ps1 TrinketBar
```

Expected: failures, because `Items.lua` does not exist yet and `run-tests.ps1` runs every spec — `addon_spec.lua` itself should pass once the edits in Steps 2 and 5 are right. If `addon_spec.lua` fails, the core file or the stub is wrong; fix that before going on.

- [ ] **Step 8: Create the three empty files the toc names**

```bash
cd C:/src/WoWAddons/TrinketBar
printf 'local addonName, ns = ...\n' > Items.lua
printf 'local addonName, ns = ...\n' > Bar.lua
printf 'local addonName, ns = ...\n' > Settings.lua
```

An empty file that the toc lists is better than a toc that lies. Each gets its content in a later task.

- [ ] **Step 9: Run the tests and make sure they pass**

```powershell
.\run-tests.ps1 TrinketBar
```

Expected: all pass.

- [ ] **Step 10: Commit**

```bash
git add TrinketBar
git commit -m "Scaffold TrinketBar: core, slash command and test harness"
```

---

### Task 2: Finding the trinkets in the bags

**Files:**
- Modify: `TrinketBar/Items.lua`
- Modify: `TrinketBar/tests/wow_stub.lua`
- Test: `TrinketBar/tests/items_spec.lua`

**Interfaces:**
- Consumes: `ns.Guarded(fn, whenUnknown)` from Task 1.
- Produces: `ns.Items.Carried()` returning a list of `{ name, link, texture, bag, slot }` sorted by name.

- [ ] **Step 1: Teach the stub about bags**

Add to `TrinketBar/tests/wow_stub.lua`, beside the other fixtures:

```lua
    -- What is in the bags: env.__bags[bag][slot] = "item link". Bag 0 is the
    -- backpack, 1-4 the worn bags, which is the range the real API uses.
    env.__bags = { [0] = {}, {}, {}, {}, {} }

    -- What the client knows about an item, by link:
    --   env.__items["|cff...|Hitem:1|h[Card]|h|r"] =
    --       { name = "Card", equipLoc = "INVTYPE_TRINKET", texture = 133308 }
    env.__items = {}

    env.NUM_BAG_SLOTS = 4

    --- Test helper: put a trinket in a bag slot and register what it is.
    function env.__carry(bag, slot, name, equipLoc)
        local link = string.format("|Hitem:%s|h[%s]|h", name, name)
        env.__bags[bag] = env.__bags[bag] or {}
        env.__bags[bag][slot] = link
        env.__items[link] = {
            name = name,
            equipLoc = equipLoc or "INVTYPE_TRINKET",
            texture = 133308,
        }
        return link
    end

    -- Namespaced by default, which is the shape this client family has been
    -- moving towards. A test covering an older client deletes these and adds
    -- the globals itself, from the same __bags and __items tables.
    env.C_Container = {
        GetContainerNumSlots = function(bag)
            local contents = env.__bags[bag]
            if not contents then return 0 end
            local highest = 0
            for slot in pairs(contents) do
                if slot > highest then highest = slot end
            end
            return highest
        end,
        GetContainerItemLink = function(bag, slot)
            return env.__bags[bag] and env.__bags[bag][slot] or nil
        end,
    }

    env.C_Item = {
        GetItemInfo = function(link)
            local item = env.__items[link]
            if not item then return nil end
            -- name, link, quality, level, minLevel, type, subType,
            -- stackCount, equipLoc, texture -- the real call's shape, which
            -- is what Items.lua has to read positionally.
            return item.name, link, 1, 1, 1, "Armor", "Miscellaneous", 1,
                item.equipLoc, item.texture
        end,
    }
```

- [ ] **Step 2: Write the failing test**

`TrinketBar/tests/items_spec.lua`:

```lua
local helpers = require("helpers")

local FILES = { "TrinketBar.lua", "Items.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

describe("finding the trinkets in the bags", function()
    it("returns the ones that go in a trinket slot", function()
        local ns, env = loggedIn()
        env.__carry(0, 1, "Kiss of the Spider")
        env.__carry(0, 2, "Hand of Justice")

        local carried = ns.Items.Carried()

        assertEqual(2, #carried)
    end)

    it("leaves out everything that is not a trinket", function()
        -- A bag is mostly not trinkets. Reagents, food and the bags
        -- themselves share it.
        local ns, env = loggedIn()
        env.__carry(0, 1, "Kiss of the Spider")
        env.__carry(0, 2, "Runecloth Bag", "INVTYPE_BAG")
        env.__carry(0, 3, "Mageroyal", "")

        local carried = ns.Items.Carried()

        assertEqual(1, #carried)
        assertEqual("Kiss of the Spider", carried[1].name)
    end)

    it("sorts by name, so the bar only reshuffles when the set changes", function()
        -- Bag order changes every time the bags are tidied. A bar that
        -- reshuffles then is one no muscle memory can form on.
        local ns, env = loggedIn()
        env.__carry(0, 1, "Zandalarian Hero Charm")
        env.__carry(0, 2, "Hand of Justice")
        env.__carry(1, 1, "Mark of the Chosen")

        local carried = ns.Items.Carried()

        assertEqual("Hand of Justice", carried[1].name)
        assertEqual("Mark of the Chosen", carried[2].name)
        assertEqual("Zandalarian Hero Charm", carried[3].name)
    end)

    it("walks every bag, not just the backpack", function()
        local ns, env = loggedIn()
        env.__carry(4, 7, "Kiss of the Spider")

        assertEqual(1, #ns.Items.Carried())
    end)

    it("carries the icon and where it was found", function()
        local ns, env = loggedIn()
        env.__carry(2, 5, "Hand of Justice")

        local first = ns.Items.Carried()[1]

        assertEqual(133308, first.texture)
        assertEqual(2, first.bag)
        assertEqual(5, first.slot)
        assertTrue(first.link ~= nil)
    end)

    it("lists two of the same trinket once", function()
        -- /equipslot takes the first match by name, and two identical icons
        -- side by side say nothing that can be acted on.
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")
        env.__carry(0, 2, "Hand of Justice")

        assertEqual(1, #ns.Items.Carried())
    end)

    it("falls back to the old globals on a client that has them", function()
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")

        local container = env.C_Container
        local item = env.C_Item
        env.C_Container = nil
        env.C_Item = nil
        env.GetContainerNumSlots = container.GetContainerNumSlots
        env.GetContainerItemLink = container.GetContainerItemLink
        env.GetItemInfo = item.GetItemInfo

        assertEqual(1, #ns.Items.Carried())
    end)

    it("is empty, not broken, when the bags cannot be walked at all", function()
        local ns, env = loggedIn()
        env.C_Container = nil

        assertEqual(0, #ns.Items.Carried())
    end)

    it("says so when it cannot walk the bags", function()
        local ns, env = loggedIn()
        env.C_Container = nil

        ns.Items.Carried()

        assertMatch("bags", helpers.printed(env))
    end)

    it("says so exactly once, however often it is asked", function()
        -- Carried() runs on every bag change. A message that repeats then
        -- is worse than the fault it reports.
        local ns, env = loggedIn()
        env.C_Container = nil

        ns.Items.Carried()
        ns.Items.Carried()
        ns.Items.Carried()

        local _, count = helpers.printed(env):gsub("bags", "bags")
        assertEqual(1, count)
    end)

    it("is empty when a bag read raises", function()
        -- Every client read here goes through ns.Guarded, because a read
        -- this client refuses to let tainted code inspect raises rather
        -- than returning nothing.
        local ns, env = loggedIn()
        env.C_Container.GetContainerItemLink = function() error("secret value") end

        local ok, carried = pcall(ns.Items.Carried)
        assertTrue(ok, "a refused read must not take the bar down")
        assertEqual(0, #carried)
    end)
end)
```

- [ ] **Step 3: Run it and watch it fail**

```powershell
.\run-tests.ps1 TrinketBar
```

Expected: every test in `items_spec.lua` fails with "attempt to index a nil value (field 'Items')".

- [ ] **Step 4: Write Items.lua**

Replace `TrinketBar/Items.lua` with:

```lua
local addonName, ns = ...

-- What this client knows about items: what is in the bags, what is worn, and
-- which of it goes in a trinket slot. Everything here is a lookup against the
-- client's own APIs -- no frame, no layout -- which is what lets the answers
-- be tested without a client.

local Items = {}
ns.Items = Items

-- The two trinket slots. Named constants where the client has them, the
-- numbers otherwise: they have been 13 and 14 since the game shipped, but a
-- constant that exists is one fewer thing to be wrong about.
Items.TRINKET_SLOTS = {
    INVSLOT_TRINKET1 or 13,
    INVSLOT_TRINKET2 or 14,
}

-- What a trinket's equip location reads as. Every other slot in the game
-- answers with something else, which is the whole filter.
local TRINKET_LOCATION = "INVTYPE_TRINKET"

-- Said once per session, not once per bag change. Carried() runs on every
-- BAG_UPDATE_DELAYED, and a message repeating that often is worse than the
-- fault it reports.
local warnedAboutBags = false

local function warnOnce()
    if warnedAboutBags then
        return
    end
    warnedAboutBags = true
    ns.Print("This client will not let me read your bags, so the bar shows only what you are wearing.")
end

--- How many slots a bag has, through whichever API this client has.
local function bagSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end

    if GetContainerNumSlots then
        return GetContainerNumSlots(bag) or 0
    end

    return 0
end

--- The item link in a bag slot, or nil for an empty one.
local function bagLink(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bag, slot)
    end

    if GetContainerItemLink then
        return GetContainerItemLink(bag, slot)
    end

    return nil
end

--- An item's name, equip location and icon, by link.
--
-- Read positionally because that is how the call answers: name, link,
-- quality, level, minLevel, type, subType, stackCount, equipLoc, texture.
-- The two that matter are ninth and tenth.
local function itemFacts(link)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not info then
        return nil
    end

    local name, _, _, _, _, _, _, _, equipLoc, texture = info(link)
    if type(name) ~= "string" then
        return nil
    end

    return name, equipLoc, texture
end

--- Every trinket in the bags, by name, in alphabetical order.
--
-- Sorted rather than left in bag order: bag order changes every time the bags
-- are tidied, and a bar that reshuffles then is one no muscle memory can form
-- on. The set changing is the only thing that should move a button.
--
-- Guarded whole rather than per call: a client that refuses one of these
-- reads refuses them all, and a half-walked bag is not a better answer than
-- an empty one.
function Items.Carried()
    local canWalk = (C_Container and C_Container.GetContainerNumSlots)
        or GetContainerNumSlots
    if not canWalk then
        warnOnce()
        return {}
    end

    return ns.Guarded(function()
        local found, seen = {}, {}

        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for slot = 1, bagSlots(bag) do
                local link = bagLink(bag, slot)

                if link then
                    local name, equipLoc, texture = itemFacts(link)

                    -- Two of the same trinket collapse to one: /equipslot
                    -- takes the first match by name, so a second button for
                    -- the second copy would do exactly what the first does.
                    if name and equipLoc == TRINKET_LOCATION and not seen[name] then
                        seen[name] = true
                        found[#found + 1] = {
                            name = name,
                            link = link,
                            texture = texture,
                            bag = bag,
                            slot = slot,
                        }
                    end
                end
            end
        end

        table.sort(found, function(left, right)
            return left.name < right.name
        end)

        return found
    end, {})
end
```

- [ ] **Step 5: Run the tests and make sure they pass**

```powershell
.\run-tests.ps1 TrinketBar
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add TrinketBar
git commit -m "Find the trinkets in the bags"
```

---

### Task 3: What is worn, and what is on cooldown

**Files:**
- Modify: `TrinketBar/Items.lua`
- Modify: `TrinketBar/tests/wow_stub.lua`
- Test: `TrinketBar/tests/items_spec.lua`

**Interfaces:**
- Consumes: `ns.Items.Carried()` and `ns.Guarded` from Tasks 1-2.
- Produces: `ns.Items.Worn()` returning `{ [13] = entry or nil, [14] = entry or nil }`; `ns.Items.All()` returning one name-sorted list where a worn entry carries `wornSlot`; `ns.Items.Cooldown(entry)` returning `start, duration, enabled` or nil.

- [ ] **Step 1: Teach the stub about worn slots and cooldowns**

Add to `TrinketBar/tests/wow_stub.lua`:

```lua
    -- What is in the trinket slots: env.__worn[13] = "item link".
    env.__worn = {}

    -- When something comes off cooldown, keyed the way each API is asked:
    --   env.__cooldowns["worn:13"]  = { start = 100, duration = 120 }
    --   env.__cooldowns["bag:0:1"]  = { start = 100, duration = 120 }
    env.__cooldowns = {}

    env.__now = 1000
    function env.GetTime() return env.__now end

    env.INVSLOT_TRINKET1 = 13
    env.INVSLOT_TRINKET2 = 14

    --- Test helper: put a trinket in a worn slot and register what it is.
    function env.__wear(slot, name)
        local link = string.format("|Hitem:%s|h[%s]|h", name, name)
        env.__worn[slot] = link
        env.__items[link] = {
            name = name,
            equipLoc = "INVTYPE_TRINKET",
            texture = 133308,
        }
        return link
    end

    function env.GetInventoryItemLink(unit, slot)
        return unit == "player" and env.__worn[slot] or nil
    end

    function env.GetInventoryItemCooldown(unit, slot)
        local entry = env.__cooldowns["worn:" .. tostring(slot)]
        if not entry then return 0, 0, 1 end
        return entry.start, entry.duration, 1
    end
```

And inside the existing `env.C_Container` table:

```lua
        GetContainerItemCooldown = function(bag, slot)
            local entry = env.__cooldowns[string.format("bag:%d:%d", bag, slot)]
            if not entry then return 0, 0, 1 end
            return entry.start, entry.duration, 1
        end,
```

- [ ] **Step 2: Write the failing test**

Append to `TrinketBar/tests/items_spec.lua`:

```lua
describe("what is worn", function()
    it("reads both trinket slots", function()
        local ns, env = loggedIn()
        env.__wear(13, "Hand of Justice")
        env.__wear(14, "Kiss of the Spider")

        local worn = ns.Items.Worn()

        assertEqual("Hand of Justice", worn[13].name)
        assertEqual("Kiss of the Spider", worn[14].name)
    end)

    it("says nothing for an empty slot", function()
        local ns, env = loggedIn()
        env.__wear(13, "Hand of Justice")

        assertNil(ns.Items.Worn()[14])
    end)

    it("is empty, not broken, when the read raises", function()
        local ns, env = loggedIn()
        env.GetInventoryItemLink = function() error("secret value") end

        local ok, worn = pcall(ns.Items.Worn)
        assertTrue(ok)
        assertNil(worn[13])
    end)
end)

describe("everything the bar shows", function()
    it("puts the worn and the carried in one list, sorted by name", function()
        local ns, env = loggedIn()
        env.__wear(13, "Mark of the Chosen")
        env.__carry(0, 1, "Zandalarian Hero Charm")
        env.__carry(0, 2, "Hand of Justice")

        local all = ns.Items.All()

        assertEqual(3, #all)
        assertEqual("Hand of Justice", all[1].name)
        assertEqual("Mark of the Chosen", all[2].name)
        assertEqual("Zandalarian Hero Charm", all[3].name)
    end)

    it("marks which slot a worn one is in", function()
        -- Without this the bar says what could go on but not what is on,
        -- and the swap is blind.
        local ns, env = loggedIn()
        env.__wear(14, "Mark of the Chosen")
        env.__carry(0, 1, "Hand of Justice")

        local all = ns.Items.All()

        assertNil(all[1].wornSlot, "the carried one is not worn")
        assertEqual(14, all[2].wornSlot)
    end)

    it("lists a trinket once even if a second copy is in the bags", function()
        local ns, env = loggedIn()
        env.__wear(13, "Hand of Justice")
        env.__carry(0, 1, "Hand of Justice")

        local all = ns.Items.All()

        assertEqual(1, #all)
        assertEqual(13, all[1].wornSlot, "the worn one wins, since it says more")
    end)
end)

describe("a trinket's cooldown", function()
    it("reads a worn one from its inventory slot", function()
        local ns, env = loggedIn()
        env.__wear(13, "Hand of Justice")
        env.__cooldowns["worn:13"] = { start = 100, duration = 120 }

        local start, duration = ns.Items.Cooldown(ns.Items.All()[1])

        assertEqual(100, start)
        assertEqual(120, duration)
    end)

    it("reads a carried one from its bag slot", function()
        local ns, env = loggedIn()
        env.__carry(2, 5, "Hand of Justice")
        env.__cooldowns["bag:2:5"] = { start = 100, duration = 90 }

        local start, duration = ns.Items.Cooldown(ns.Items.All()[1])

        assertEqual(100, start)
        assertEqual(90, duration)
    end)

    it("says nothing when there is no cooldown running", function()
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")

        assertNil(ns.Items.Cooldown(ns.Items.All()[1]))
    end)

    it("says nothing when the read raises", function()
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")
        env.C_Container.GetContainerItemCooldown = function() error("secret") end

        local ok, start = pcall(ns.Items.Cooldown, ns.Items.All()[1])
        assertTrue(ok)
        assertNil(start)
    end)
end)
```

- [ ] **Step 3: Run it and watch it fail**

```powershell
.\run-tests.ps1 TrinketBar
```

Expected: the new tests fail with "attempt to call a nil value (field 'Worn')".

- [ ] **Step 4: Append to Items.lua**

```lua
--- What is in each trinket slot: { [13] = entry, [14] = entry }, with a slot
-- missing where nothing is worn.
function Items.Worn()
    return ns.Guarded(function()
        local worn = {}

        for _, slot in ipairs(Items.TRINKET_SLOTS) do
            local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)

            if link then
                local name, _, texture = itemFacts(link)
                if name then
                    worn[slot] = {
                        name = name,
                        link = link,
                        texture = texture,
                        wornSlot = slot,
                    }
                end
            end
        end

        return worn
    end, {})
end

--- Everything the bar shows: the worn and the carried, as one list sorted by
-- name.
--
-- A trinket that is both worn and carried -- a second copy in the bags --
-- appears once, as the worn one. The worn entry says strictly more: it
-- carries which slot it is in, which is what the marker on the button needs.
function Items.All()
    local all, seen = {}, {}

    for _, entry in pairs(Items.Worn()) do
        if not seen[entry.name] then
            seen[entry.name] = true
            all[#all + 1] = entry
        end
    end

    for _, entry in ipairs(Items.Carried()) do
        if not seen[entry.name] then
            seen[entry.name] = true
            all[#all + 1] = entry
        end
    end

    table.sort(all, function(left, right)
        return left.name < right.name
    end)

    return all
end

--- When a trinket's cooldown started and how long it runs, or nil when there
-- is none to draw.
--
-- Which call answers depends on where the trinket is, which is why the entry
-- is passed rather than a name: a worn trinket is asked about by inventory
-- slot, a carried one by bag and slot, and nothing can turn one into the
-- other.
function Items.Cooldown(entry)
    if type(entry) ~= "table" then
        return nil
    end

    -- Gathered into a table before it leaves the guard, because ns.Guarded
    -- returns one value -- it is a pcall, and the second return of a pcall
    -- is the first return of what it called. Two loose values cannot come
    -- back through it, and asking the client twice to get them would be two
    -- reads where the answer must not disagree with itself.
    local reading = ns.Guarded(function()
        local start, duration

        if entry.wornSlot then
            if not GetInventoryItemCooldown then
                return nil
            end
            start, duration = GetInventoryItemCooldown("player", entry.wornSlot)
        else
            local read = (C_Container and C_Container.GetContainerItemCooldown)
                or GetContainerItemCooldown
            if not read then
                return nil
            end
            start, duration = read(entry.bag, entry.slot)
        end

        -- Zero duration is how the client says "not on cooldown", and it is
        -- the common answer. Returning it as a cooldown would draw a sweep
        -- of no length over every button.
        if not start or not duration or duration <= 0 then
            return nil
        end

        return { start = start, duration = duration }
    end, nil)

    if not reading then
        return nil
    end

    return reading.start, reading.duration
end
```

- [ ] **Step 5: Run the tests and make sure they pass**

```powershell
.\run-tests.ps1 TrinketBar
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add TrinketBar
git commit -m "Read the worn trinkets and their cooldowns"
```

---

### Task 4: The button pool and the macros it carries

**Files:**
- Modify: `TrinketBar/Bar.lua`
- Test: `TrinketBar/tests/bar_spec.lua`

**Interfaces:**
- Consumes: `ns.Items.All()`, `ns.Guarded`, `ns.OnLogin`, `ns.AddDefaults`.
- Produces: `ns.Bar.MAX_BUTTONS` (16), `ns.Bar.Build()` returning true when the pool exists, `ns.Bar.Apply()` returning true when it wrote, `ns.Bar.Buttons()` returning the pool as a list, `ns.Bar.Pending()` returning whether combat is holding a change, `ns.Bar.Anchor()` returning the frame.

- [ ] **Step 1: Write the failing test**

`TrinketBar/tests/bar_spec.lua`:

```lua
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
end)
```

- [ ] **Step 2: Run it and watch it fail**

```powershell
.\run-tests.ps1 TrinketBar
```

Expected: every test in `bar_spec.lua` fails with "attempt to index a nil value (field 'Bar')".

- [ ] **Step 3: Write Bar.lua**

Replace `TrinketBar/Bar.lua` with:

```lua
local addonName, ns = ...

-- The bar: a pool of secure buttons, each carrying an /equipslot macro, and
-- the queue that holds a change until combat ends.

local Bar = {}
ns.Bar = Bar

-- Every button the pool will ever have. Past what anyone carries, because a
-- secure button cannot be created mid-fight: a pool that grows on demand is
-- one that cannot grow at the moment a trinket is looted.
Bar.MAX_BUTTONS = 16

local BUTTON_SIZE = 24
local BUTTON_GAP = 4

local anchor
local buttons = {}

-- Nothing secure may be written in combat: not an attribute, not showing or
-- hiding a button, not moving the frame they sit in. Rather than attempt it
-- and put an error in the player's face, hold the change and do it the
-- moment the fight ends.
local pending = false
local buildPending = false

function Bar.Buttons()
    return buttons
end

function Bar.Anchor()
    return anchor
end

function Bar.Pending()
    return pending
end

local function createAnchor()
    anchor = CreateFrame("Frame", "TrinketBarAnchor", UIParent)
    anchor:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    anchor:SetPoint("CENTER", 0, -160)
end

--- Build the pool. Out of combat only: creating a secure button writes
-- attributes, which is refused mid-fight the same as anything else.
-- Returns true once the buttons exist, false when the build was held.
function Bar.Build()
    if anchor then
        return true
    end

    if InCombatLockdown and InCombatLockdown() then
        -- pending is armed here too, not left for the caller: the buttons
        -- this build will eventually create start with no macros at all, so
        -- whoever finishes the build later must also apply.
        buildPending = true
        pending = true
        return false
    end

    buildPending = false
    createAnchor()

    for index = 1, Bar.MAX_BUTTONS do
        local button = CreateFrame(
            "Button",
            string.format("TrinketBarButton%d", index),
            anchor,
            "SecureActionButtonTemplate"
        )
        button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        button:EnableMouse(true)
        -- Both edges. This client performs a secure action on the press
        -- where others act on the release, and a button registered for only
        -- one of them can be handed a pass it will not act on.
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:Hide()

        buttons[index] = button
    end

    return true
end

--- Point every button at a trinket, and hide the rest.
-- Returns true when it wrote, false when combat held it.
function Bar.Apply()
    if not anchor then
        return false
    end

    if InCombatLockdown and InCombatLockdown() then
        pending = true
        return false
    end

    pending = false

    local all = ns.Items.All()

    for index = 1, Bar.MAX_BUTTONS do
        local button = buttons[index]
        local entry = all[index]

        if entry then
            -- A macro rather than type="item": using an equippable item
            -- lets the game pick the slot, and this bar has to say which.
            button:SetAttribute("type1", "macro")
            button:SetAttribute("macrotext1", "/equipslot "
                .. ns.Items.TRINKET_SLOTS[1] .. " " .. entry.name)
            button:SetAttribute("type2", "macro")
            button:SetAttribute("macrotext2", "/equipslot "
                .. ns.Items.TRINKET_SLOTS[2] .. " " .. entry.name)

            button.entry = entry
            button:Show()
        else
            -- Cleared, not merely hidden. A hidden button still carrying an
            -- instruction is one keybind away from running it.
            button:SetAttribute("type1", nil)
            button:SetAttribute("macrotext1", nil)
            button:SetAttribute("type2", nil)
            button:SetAttribute("macrotext2", nil)

            button.entry = nil
            button:Hide()
        end
    end

    return true
end

--- Run whatever combat was holding.
local function runPending()
    if buildPending and Bar.Build() then
        pending = true
    end

    if pending then
        Bar.Apply()
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("BAG_UPDATE_DELAYED")
watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")

watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        runPending()
        return
    end

    -- BAG_UPDATE_DELAYED rather than BAG_UPDATE: the latter fires once per
    -- bag per change, and re-pointing sixteen secure buttons five times for
    -- one looted item is work nobody asked for.
    Bar.Apply()
end)

ns.OnLogin(function()
    Bar.Build()
    Bar.Apply()
end)
```

- [ ] **Step 4: Run the tests and make sure they pass**

```powershell
.\run-tests.ps1 TrinketBar
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add TrinketBar
git commit -m "Build the button pool and the macros it carries"
```

---

### Task 5: Laying the buttons out, and a bar you can drag

**Files:**
- Modify: `TrinketBar/Bar.lua`
- Test: `TrinketBar/tests/bar_spec.lua`

**Interfaces:**
- Consumes: everything from Task 4.
- Produces: `ns.Bar.Layout()`; defaults `ns.db.bar.iconSize` (24), `ns.db.bar.perRow` (8), `ns.db.bar.locked` (false), `ns.db.anchor = { point, x, y }`; commands `/tb lock` and `/tb reset`.

- [ ] **Step 1: Write the failing test**

Append to `TrinketBar/tests/bar_spec.lua`:

```lua
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

        local _, firstX = ns.Bar.Buttons()[1]:GetPoint()
        local _, secondX = ns.Bar.Buttons()[2]:GetPoint()

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
        local ns = carrying(2)
        ns.db.bar.perRow = 8
        ns.Bar.Apply()

        local width = ns.Bar.Anchor():GetWidth()
        local buttonWidth = ns.Bar.Buttons()[1]:GetWidth()

        assertTrue(width < buttonWidth * 8, "not sized for a full row")
        assertTrue(width >= buttonWidth * 2, "but wide enough for two")
    end)
end)

describe("the anchor", function()
    it("starts where the database says", function()
        local ns = loggedIn()
        assertEqual("CENTER", ns.db.anchor.point)
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
end)
```

- [ ] **Step 2: Run it and watch it fail**

```powershell
.\run-tests.ps1 TrinketBar
```

Expected: the new tests fail — `ns.db.bar` is nil and the anchor has no drag scripts.

- [ ] **Step 3: Add the defaults, the layout and the drag to Bar.lua**

Near the top of `Bar.lua`, under the constants:

```lua
local DEFAULT_ANCHOR = { point = "CENTER", x = 0, y = -160 }

ns.AddDefaults({
    anchor = {
        point = DEFAULT_ANCHOR.point,
        x = DEFAULT_ANCHOR.x,
        y = DEFAULT_ANCHOR.y,
    },
    bar = {
        iconSize = 24,
        -- Eight, because sixteen in a line is wider than most screens and
        -- nobody carries sixteen anyway.
        perRow = 8,
        locked = false,
    },
})

-- Faint enough not to compete with the icons over it, visible enough that
-- the drag region reads as a thing you can grab rather than empty air.
local BACKDROP_ALPHA = 0.12

--- The icon size in force, clamped where it is read rather than trusted from
-- the database: a slider cannot produce a bad value but a saved variable
-- edited by hand can, and a frame sized from a negative number is one the
-- client complains about.
local function iconSize()
    local size = math.floor(tonumber(ns.db and ns.db.bar and ns.db.bar.iconSize) or 24)
    if size < 12 then return 12 end
    if size > 48 then return 48 end
    return size
end

local function perRow()
    local count = math.floor(tonumber(ns.db and ns.db.bar and ns.db.bar.perRow) or 8)
    if count < 1 then return 1 end
    if count > Bar.MAX_BUTTONS then return Bar.MAX_BUTTONS end
    return count
end
```

Replace `createAnchor` with:

```lua
local function repositionAnchor()
    if anchor then
        anchor:ClearAllPoints()
        anchor:SetPoint(ns.db.anchor.point, ns.db.anchor.x, ns.db.anchor.y)
    end
end

local function createAnchor()
    anchor = CreateFrame("Frame", "TrinketBarAnchor", UIParent)
    anchor:SetSize(BUTTON_SIZE, BUTTON_SIZE)

    local background = anchor:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(1, 1, 1, BACKDROP_ALPHA)
    anchor.background = background

    repositionAnchor()
    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")

    anchor:SetScript("OnDragStart", function(self)
        if ns.db.bar.locked then
            return
        end

        if InCombatLockdown and InCombatLockdown() then
            -- StartMoving repositions every button hanging off this frame,
            -- which the client refuses in combat the same as any other
            -- secure change.
            ns.Print("Cannot move the bar in combat.")
            return
        end

        self:StartMoving()
    end)

    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        ns.db.anchor.point = point or DEFAULT_ANCHOR.point
        ns.db.anchor.x = x or DEFAULT_ANCHOR.x
        ns.db.anchor.y = y or DEFAULT_ANCHOR.y
    end)
end
```

Add `Bar.Layout`, and call it from `Bar.Apply` after the button loop:

```lua
--- Place the buttons that are showing, and size the anchor to hold them.
--
-- Placed by how many are showing rather than by index, so a gap never opens
-- where a hidden button would have been. Safe here because Apply only ever
-- runs out of combat, and moving a secure button is refused in it.
function Bar.Layout(shown)
    local size = iconSize()
    local columns = perRow()
    local placed = 0

    for index = 1, Bar.MAX_BUTTONS do
        local button = buttons[index]

        if index <= shown then
            local column = placed % columns
            local row = math.floor(placed / columns)

            button:SetSize(size, size)
            button:ClearAllPoints()
            button:SetPoint(
                "TOPLEFT", anchor, "TOPLEFT",
                column * (size + BUTTON_GAP),
                -row * (size + BUTTON_GAP)
            )
            placed = placed + 1
        end
    end

    local across = math.min(math.max(shown, 1), columns)
    local down = math.max(math.ceil(shown / columns), 1)

    anchor:SetSize(
        across * size + (across - 1) * BUTTON_GAP,
        down * size + (down - 1) * BUTTON_GAP
    )
end
```

In `Bar.Apply`, count the entries placed and end with the layout:

```lua
    local shown = 0
    -- ... inside the `if entry then` branch, after button:Show():
    shown = shown + 1
    -- ... after the loop:
    Bar.Layout(shown)
    return true
```

Add the commands at the foot of the file:

```lua
ns.RegisterCommand("lock", "Stop the bar being dragged", function()
    ns.db.bar.locked = not ns.db.bar.locked
    ns.Print(ns.db.bar.locked and "Bar locked." or "Bar unlocked.")
end)

ns.RegisterCommand("reset", "Put the bar back in the middle", function()
    ns.db.anchor.point = DEFAULT_ANCHOR.point
    ns.db.anchor.x = DEFAULT_ANCHOR.x
    ns.db.anchor.y = DEFAULT_ANCHOR.y

    if InCombatLockdown and InCombatLockdown() then
        pending = true
        ns.Print("Bar will move back once combat ends.")
        return
    end

    repositionAnchor()
    ns.Print("Bar back in the middle.")
end)
```

And in `runPending`, reposition before applying, guarded the same way:

```lua
    if pending and not (InCombatLockdown and InCombatLockdown()) then
        repositionAnchor()
    end
```

- [ ] **Step 4: Run the tests and make sure they pass**

```powershell
.\run-tests.ps1 TrinketBar
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add TrinketBar
git commit -m "Lay the buttons out and let the bar be dragged"
```

---

### Task 6: What a button looks like

**Files:**
- Modify: `TrinketBar/Bar.lua`
- Test: `TrinketBar/tests/bar_spec.lua`

**Interfaces:**
- Consumes: everything from Tasks 4-5, plus `ns.Items.Cooldown(entry)`.
- Produces: `ns.Bar.RefreshCooldowns()`; each button carries `.icon`, `.cooldown` (or nil), `.worn`.

- [ ] **Step 1: Write the failing test**

Append to `TrinketBar/tests/bar_spec.lua`:

```lua
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

        local all = ns.Items.All()
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
end)
```

- [ ] **Step 2: Run it and watch it fail**

```powershell
.\run-tests.ps1 TrinketBar
```

Expected: the new tests fail — buttons have no `.icon`.

- [ ] **Step 3: Give the buttons their art**

In `Bar.Build`, inside the button loop, after `RegisterForClicks`:

```lua
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints(button)
        -- The standard action-bar crop: item icons carry their own border
        -- baked in, and without trimming it every button looks wrong next
        -- to the ones the game draws.
        button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        button.icon:Hide()

        -- A gold border on whichever trinkets are on. Drawn rather than
        -- taken from Blizzard's art: a texture path this client turns out
        -- not to have fails silently, drawing nothing and saying nothing
        -- about why.
        button.worn = button:CreateTexture(nil, "OVERLAY")
        button.worn:SetAllPoints(button)
        button.worn:SetColorTexture(1, 0.82, 0, 0.35)
        button.worn:Hide()

        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(button)
        highlight:SetColorTexture(1, 1, 1, 0.2)

        -- Blizzard's own cooldown widget, so the sweep is the one the
        -- action bars draw. Through pcall because a template is not
        -- something this client family can be trusted to have, and an
        -- unknown one raises rather than returning nil. The sweep is
        -- decoration; equipping is the point.
        local created, cooldown = pcall(
            CreateFrame, "Cooldown", nil, button, "CooldownFrameTemplate"
        )
        if created and cooldown then
            cooldown:SetAllPoints(button)
            button.cooldown = cooldown
        end
```

In `Bar.Apply`, inside the `if entry then` branch:

```lua
            if entry.texture then
                button.icon:SetTexture(entry.texture)
                button.icon:Show()
            else
                button.icon:Hide()
            end

            button.worn:SetShown(entry.wornSlot ~= nil)
```

and in the `else` branch:

```lua
            button.icon:Hide()
            button.worn:Hide()
```

Add `RefreshCooldowns`, and call it at the end of `Bar.Apply`:

```lua
--- Draw each button's cooldown sweep.
--
-- Separate from Apply because a cooldown starts without anything else
-- changing: the bar is right, only the sweeps are stale.
function Bar.RefreshCooldowns()
    for index = 1, Bar.MAX_BUTTONS do
        local button = buttons[index]
        local cooldown = button and button.cooldown

        if cooldown then
            local start, duration = ns.Items.Cooldown(button.entry)

            if start and duration and duration > 0 then
                cooldown:SetCooldown(start, duration)
            else
                -- A zero-length cooldown is how the widget is told to draw
                -- nothing. Without this an expired sweep would sit there
                -- for good, since nothing else ever clears one.
                cooldown:SetCooldown(0, 0)
            end
        end
    end
end
```

Register the event in the watcher:

```lua
watcher:RegisterEvent("BAG_UPDATE_COOLDOWN")
```

and handle it before the `Bar.Apply()` fall-through:

```lua
    if event == "BAG_UPDATE_COOLDOWN" then
        -- Nothing about the bar changed, only the sweeps over it. Re-pointing
        -- sixteen secure buttons for that would be a secure write for a
        -- purely cosmetic reason -- and refused outright mid-fight, which is
        -- exactly when trinket cooldowns are being watched.
        Bar.RefreshCooldowns()
        return
    end
```

- [ ] **Step 4: Run the tests and make sure they pass**

```powershell
.\run-tests.ps1 TrinketBar
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add TrinketBar
git commit -m "Give the buttons icons, a worn marker and cooldown sweeps"
```

---

### Task 7: The settings panel

**Files:**
- Modify: `TrinketBar/Settings.lua`
- Modify: `TrinketBar/Bar.lua`
- Test: `TrinketBar/tests/settings_spec.lua`

**Interfaces:**
- Consumes: `ns.settings`, `ns.SettingValue`, `ns.SetSettingValue`, `ns.RegisterSetting`, `ns.RegisterCommand`, `ns.OnLogin`, `ns.Bar.Apply()`.
- Produces: `ns.SettingsPanel.EnsureBuilt()`, `ns.SettingsPanel.Refresh()`, `ns.SettingsPanel.controls`, `ns.SettingsPanel.logo`, `ns.SettingsPanel.panel`, `ns.OpenSettings()`, command `/tb settings`.

- [ ] **Step 1: Register the three settings in Bar.lua**

At the foot of `Bar.lua`, beside the commands:

```lua
-- Declared next to the code that reads them. Settings.lua renders whatever
-- has been declared, so adding one here needs no edit there.
ns.RegisterSetting({
    store = "bar",
    key = "iconSize",
    type = "slider",
    name = "Icon size",
    tooltip = "How big each trinket icon is.",
    min = 12,
    max = 48,
    step = 1,
    onChange = function() Bar.Apply() end,
})

ns.RegisterSetting({
    store = "bar",
    key = "perRow",
    type = "slider",
    name = "Buttons per row",
    tooltip = "How many icons sit side by side before the bar wraps onto another row.",
    min = 1,
    max = Bar.MAX_BUTTONS,
    step = 1,
    onChange = function() Bar.Apply() end,
})

ns.RegisterSetting({
    store = "bar",
    key = "locked",
    type = "checkbox",
    name = "Lock the bar",
    tooltip = "Stops the bar being dragged around by accident.",
})
```

- [ ] **Step 2: Write the failing test**

`TrinketBar/tests/settings_spec.lua`:

```lua
local helpers = require("helpers")

local function loggedIn()
    local ns, env = helpers.loadAddon()
    helpers.login(ns, env)
    ns.SettingsPanel.EnsureBuilt()
    return ns, env
end

local function controlFor(ns, store, key)
    for _, control in ipairs(ns.SettingsPanel.controls) do
        if control.setting.store == store and control.setting.key == key then
            return control
        end
    end
end

describe("the declared settings", function()
    it("declares one for each thing the panel offers", function()
        local ns = loggedIn()

        assertTrue(controlFor(ns, "bar", "iconSize") ~= nil, "how big")
        assertTrue(controlFor(ns, "bar", "perRow") ~= nil, "how many across")
        assertTrue(controlFor(ns, "bar", "locked") ~= nil, "the lock")
    end)
end)

describe("the panel", function()
    it("registers itself with the game's options", function()
        local ns, env = loggedIn()
        assertTrue(env.__settingsCategory ~= nil)
    end)

    it("builds once, however often it is asked", function()
        local ns = loggedIn()
        local before = #ns.SettingsPanel.controls

        ns.SettingsPanel.EnsureBuilt()
        assertEqual(before, #ns.SettingsPanel.controls)
    end)

    it("opens from /tb settings", function()
        local ns, env = loggedIn()
        helpers.command(env, "settings")

        assertEqual("category-id", env.__openedCategory)
    end)

    it("shows the logo, not the AddOns list icon", function()
        -- The same glyph drawn twice. icon.tga carries the tile the AddOns
        -- list needs; logo.tga is the glyph alone on transparency, because
        -- a tile on a dark panel reads as a sticker pasted onto it.
        local ns = loggedIn()
        assertEqual(
            [[Interface\AddOns\TrinketBar\logo]],
            ns.SettingsPanel.logo:GetTexture()
        )
    end)
end)

describe("the sliders", function()
    it("writes through to the database", function()
        local ns = loggedIn()
        controlFor(ns, "bar", "iconSize").widget:SetValue(36)

        assertEqual(36, ns.db.bar.iconSize)
    end)

    it("applies the change to the buttons", function()
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")
        ns.Bar.Apply()

        controlFor(ns, "bar", "iconSize").widget:SetValue(36)

        assertEqual(36, ns.Bar.Buttons()[1]:GetWidth())
    end)

    it("shows the stored value when it refreshes", function()
        local ns = loggedIn()
        ns.db.bar.perRow = 5

        ns.SettingsPanel.Refresh()
        assertEqual(5, controlFor(ns, "bar", "perRow").widget:GetValue())
    end)
end)

describe("the checkbox", function()
    it("writes through to the database", function()
        local ns = loggedIn()
        local control = controlFor(ns, "bar", "locked")

        control.widget:SetChecked(true)
        control.widget.scripts.OnClick(control.widget)

        assertTrue(ns.db.bar.locked)
    end)
end)
```

- [ ] **Step 3: Run it and watch it fail**

```powershell
.\run-tests.ps1 TrinketBar
```

Expected: failures — `ns.SettingsPanel` is nil.

- [ ] **Step 4: Write Settings.lua**

Start from ClickHeal's, which already has the parts that are hard to get right — the canvas registration, and turning the game menu away when the panel closes:

```bash
cd C:/src/WoWAddons
cp ClickHeal/Settings.lua TrinketBar/Settings.lua
```

Then cut it down. Delete, in `TrinketBar/Settings.lua`:

- `addSpellTable` and everything it uses: `pickerEntries`, `refreshPicker`, `Panel.Choose`, `ensurePicker`, `openPicker`, `Panel.OpenPicker`, `cursorY`, `Panel.DropPosition`, `Panel.PreviewPositions`, and the constants `PICKER_ROWS`, `PICKER_WIDTH`, `CLEAR_ENTRY`, `Panel.ROW_PITCH`.
- The column machinery: `Panel.headings`, `COLUMN_WIDTH`'s second column, and the heading block inside `ensureBuilt`'s loop. Keep a single column at `PADDING`.
- The `spelltable` branch of the build loop.

Then change, in what remains:

- `"ClickHeal"` → `"TrinketBar"` in the title, `panel.name` and the category registration.
- The hint text to: `"The bar shows every trinket you are carrying. Left-click one to put it in trinket slot 1, right-click for slot 2. Changes take effect out of combat."`
- `PANEL_WIDTH` to `COLUMN_WIDTH` if the second column is gone; a single column needs no doubling.

Leave alone: the logo and title block, the version from metadata, `addCheckbox`, `addSlider`, `Panel.Refresh` with its re-entrance guard, `register`, the game-menu hook, `ns.OpenSettings` and the `settings` command.

- [ ] **Step 5: Run the tests and make sure they pass**

```powershell
.\run-tests.ps1 TrinketBar
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add TrinketBar
git commit -m "Add the settings panel"
```

---

### Task 8: The README, and installing it

**Files:**
- Create: `TrinketBar/README.md`
- Modify: `README.md` (repo root)

**Interfaces:**
- Consumes: everything.
- Produces: nothing code depends on.

- [ ] **Step 1: Write TrinketBar/README.md**

Cover, in this order: what it is and the one-line sketch; how a click maps to a slot; what it will not do (fire on-use effects, manage other slots) and why; what combat changes; installing; the commands; the settings; what the tests prove.

Follow `ClickHeal/README.md`'s shape and voice. Two things it must say plainly, because both will otherwise be reported as bugs:

- A trinket looted mid-fight does not get a button until the fight ends, because a secure button cannot be created or re-pointed in combat.
- The bar shows what you are *carrying*. Swap a trinket and the one that comes off appears on the bar, because it is now in your bags.

- [ ] **Step 2: Add it to the repo README**

In `README.md` at the repo root, add a row to the table:

```markdown
| [TrinketBar](TrinketBar/) | Every trinket you are carrying, on a bar: left-click to equip in slot 1, right-click for slot 2 |
```

- [ ] **Step 3: Package and install**

```powershell
cd C:\src\WoWAddons
.\package.ps1 TrinketBar -Install
```

Expected: "Packaged N files" naming `dist\TrinketBar-0.1.0.zip`, then "Installed ->" the client's AddOns folder. The count must include `icon.tga` and `logo.tga`; `package.ps1` finds art by globbing, since a `.toc` cannot list it.

- [ ] **Step 4: Run the whole repo's tests**

```powershell
.\run-tests.ps1
```

Expected: four suites, all passing. `run-tests.ps1` prints no combined total, so report the per-addon lines rather than inventing a sum.

- [ ] **Step 5: Commit**

```bash
git add TrinketBar README.md
git commit -m "Document TrinketBar and list it in the repo README"
```

---

## In-game verification

The tests prove the bar asks for the right thing. Only the client can say whether it honours it. After installing, restart the client and check:

1. The bar appears with one icon per trinket you are carrying, plus the two you are wearing.
2. The two you are wearing have a gold wash over them.
3. Left-clicking an unworn trinket puts it in slot 1; right-clicking puts it in slot 2. **This is the assumption the whole design rests on** — the probe at `Interface/AddOns/TrinketProbe` answers it in isolation if the bar does not.
4. The trinket that came off appears on the bar, because it is now in your bags.
5. Dragging moves the bar; `/tb lock` stops it; `/tb reset` recentres it.
6. `/tb settings` opens a panel with a gem beside the title and three settings that take effect as you move them.
7. In combat: clicking still equips, but a trinket looted mid-fight gets its button only when the fight ends.
