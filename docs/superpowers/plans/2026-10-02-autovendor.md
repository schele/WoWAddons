# AutoVendor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a merchant opens, sell every grey item worth something that is not on the keep list, one per 0.2 seconds, then repair, then say in one chat line what was earned and spent.

**Architecture:** A core file (defaults, saved variables, chat, money words, a command registry), a file that only reads the bags, a file for the keep list and its commands, and a file for the merchant visit: a chain of timed steps, each of which counts the last sale if its slot emptied and sells the next junk slot, then repairs and reports. Every client call tries the namespaced API first and the old global second, and every read that could raise is guarded.

**Tech Stack:** Lua 5.1-flavoured (WoW runtime), Lua 5.4 for tests, the repo's spec runner (`run-tests.ps1`), Node for the icon (`tools/draw-icons.mjs`), PowerShell for packaging.

**Spec:** [docs/superpowers/specs/2026-10-02-autovendor-design.md](../specs/2026-10-02-autovendor-design.md)

## Global Constraints

- Target clients: `## Interface: 11509, 16001`.
- `## SavedVariables: AutoVendorDB`; the keep list is `AutoVendorDB.keep`, `{ [itemID] = name }`, shared by every character.
- Runtime Lua is 5.1-flavoured: no `goto`, no `//`, no `table.unpack` in addon files. Tests run under Lua 5.4 and may.
- `run-tests.ps1` and `package.ps1` are not modified.
- Files outside `AutoVendor/` that may change: `tools/draw-icons.mjs` and the root `README.md` (Task 5), the spec's "Checked in game" section (Task 5, last step).
- Comments explain *why*; none restates the line below it.
- Every client call tries the namespaced API first and the old global second: `C_Container.GetContainerNumSlots` / `GetContainerNumSlots`, `C_Container.GetContainerItemInfo` / `GetContainerItemInfo`, `C_Container.UseContainerItem` / `UseContainerItem`, `C_Item.GetItemInfo` / `GetItemInfo`, `C_Item.GetItemNameByID`.
- Every read that could raise goes through `ns.Guarded`, with the branch inside the guarded function.
- Junk is: quality 0 (Poor), a sell price above 0 and not `hasNoValue`, not on the keep list, not locked; bags 0 to `NUM_BAG_SLOTS` (4 where it is absent).
- One sale per `Vendor.PAUSE = 0.2` seconds. Repair only after the selling, never after the merchant closed.
- Words, verbatim (every chat line starts with `ns.PREFIX = "|cff66ccffAutoVendor|r"` and a space):
  - `Sold 7 items for 1g 23s 4c.` / `Sold 1 item for 15c.`
  - `Repaired for 45s.` / `Not enough gold to repair (costs 1g 2s).`
  - both halves in one line, sale first, joined by a space; nothing printed when neither happened
  - `Keeping [Broken Fang]: it will not be sold.` / `[Broken Fang] is already on the keep list.`
  - `No longer keeping [Broken Fang].` / `[Broken Fang] is not on the keep list.`
  - `Nothing is on the keep list.`; an item with no name from the client is `[item 3300]`
- Money words: `GetMoneyString(copper)` where the client has it, else `1g 23s 4c`, leaving out zero parts (`5s`, `1g`), and `0c` for nothing.
- Slash commands `/autovendor` and `/av`; `SlashCmdList.AUTOVENDOR`.
- Commit messages start `AutoVendor: ` and end with the trailer `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **Item info not loaded yet.** Right after login the client may not describe an item (`GetItemInfo` gives nothing). That grey is skipped this visit, not an error. Pinned in Task 2 ("an item the client has not described yet").
2. **Close and reopen quickly.** The old visit's queued step must not run in the new visit, or two chains sell at twice the pace and the server refuses sales. Pinned in Task 4 ("starts a fresh visit after a close").
3. **`MERCHANT_CLOSED` with no visit, or twice.** No error and no line. Pinned in Task 4 ("says nothing when it closes without a visit").
4. **A slot read that raises.** That slot is skipped, the rest are read. Pinned in Task 2 ("a slot the client will not read").
5. **A sale the merchant refused.** It is tried once, not counted, and not retried in a loop. Pinned in Task 4 ("does not count a sale the merchant refused").

## File Structure

| File | Responsibility |
|---|---|
| `AutoVendor/AutoVendor.toc` | Manifest and load order |
| `AutoVendor/AutoVendor.lua` | Namespace, defaults and `ns.db`, `ns.Print`, `ns.Guarded`, `ns.Money`, command registry, `ns.ShowHelp`, `/av`, login |
| `AutoVendor/Bags.lua` | Reading only: which slots hold junk, and what a slot holds now |
| `AutoVendor/Keep.lua` | The keep list, reading an item from a link or a number, `keep` / `unkeep` / `list` |
| `AutoVendor/Vendor.lua` | The visit: the selling steps, counting, stopping on close, repair, the line, the merchant events |
| `AutoVendor/icon.tga` | AddOns-list icon, drawn by `tools/draw-icons.mjs` |
| `AutoVendor/README.md` | What it does, the keep list, install |
| `AutoVendor/tests/runner.lua` | Copied unchanged from FishScale |
| `AutoVendor/tests/wow_stub.lua` | Stubbed client: frames, timers, bags, items, merchant, money |
| `AutoVendor/tests/helpers.lua` | Load, log in, reload, put items, open and close the merchant |
| `AutoVendor/tests/*_spec.lua` | One spec per addon file |

---

### Task 1: The core: saved variables, chat, money words, commands

**Files:**
- Create: `AutoVendor/AutoVendor.toc`
- Create: `AutoVendor/AutoVendor.lua`
- Create: `AutoVendor/tests/runner.lua` (copy)
- Create: `AutoVendor/tests/wow_stub.lua`
- Create: `AutoVendor/tests/helpers.lua`
- Test: `AutoVendor/tests/addon_spec.lua`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `ns.PREFIX`, `ns.Print(message)`, `ns.Guarded(fn, whenUnknown)`, `ns.Money(copper) -> string`, `ns.AddDefaults(table)`, `ns.db` (= `AutoVendorDB`, set at `ADDON_LOADED`/`PLAYER_LOGIN`), `ns.RegisterCommand(name, help, handler(rest))`, `ns.ShowHelp()`.
  - Globals `SLASH_AUTOVENDOR1 = "/autovendor"`, `SLASH_AUTOVENDOR2 = "/av"`, `SlashCmdList.AUTOVENDOR`.
  - Test helpers: `helpers.FILES`, `helpers.loadAddon(saved) -> ns, env`, `helpers.login(env)`, `helpers.reload(env) -> ns, env`, `helpers.legacy(env)`, `helpers.put(env, bag, slot, itemID, count, locked)`, `helpers.fire(env, event, ...)`, `helpers.openMerchant(env)`, `helpers.closeMerchant(env)`, `helpers.command(env, text)`, `helpers.printed(env)`.
  - Stub state: `env.__items[id] = { name, quality, price }`, `env.__uncached[id]`, `env.__link(id)`, `env.__bagSizes[bag]`, `env.__slots["bag:slot"] = { itemID, count, locked }`, `env.__raisingSlots["bag:slot"]`, `env.__merchantOpen`, `env.__money`, `env.__canRepair`, `env.__repairCost`, `env.__repairs`, `env.__refused[id]`, `env.__sales` (list of `"bag:slot"`), `env.__log` (list of `"sell bag:slot"` / `"repair"`), `env.__timers`, `env.__timerDelays`, `env.__runTimers()`, `env.__runAllTimers()`, `env.__printed`.

- [ ] **Step 1: Copy the spec runner**

```bash
mkdir -p AutoVendor/tests
cp FishScale/tests/runner.lua AutoVendor/tests/runner.lua
```

- [ ] **Step 2: Write the stubbed client**

Create `AutoVendor/tests/wow_stub.lua`. Written once with what every task needs; no later task edits it.

```lua
-- A minimal stand-in for the WoW API, enough to load AutoVendor outside the
-- game: frames, timers, bags, items, a merchant and money. It records what
-- was done so tests can assert on it.

local stub = {}

local function makeWidget(kind, parent)
    local widget = {
        kind = kind,
        parent = parent,
        scripts = {},
        registeredEvents = {},
    }

    function widget:SetScript(name, fn) self.scripts[name] = fn end
    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end

    -- Test helper: drive this widget's OnEvent handler.
    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then handler(self, event, ...) end
    end

    return widget
end

--- A fresh client. `saved` is AutoVendorDB as the client would load it from
-- SavedVariables, or nil for a first run.
function stub.newEnv(saved)
    local env = setmetatable({}, { __index = _G })

    env._G = env
    env.__frames = {}
    env.__printed = {}
    env.SlashCmdList = {}
    env.AutoVendorDB = saved

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do
            pieces[index] = tostring((select(index, ...)))
        end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    function env.CreateFrame(kind, name, parent)
        local frame = makeWidget(kind or "Frame", parent)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        return frame
    end

    -- The client runs a timer after the current chain of calls, not inside
    -- it: queued here with its delay, and run by __runTimers.
    env.__timers = {}
    env.__timerDelays = {}
    env.C_Timer = {
        After = function(delay, fn)
            table.insert(env.__timerDelays, delay)
            table.insert(env.__timers, fn)
        end,
    }
    --- One round: the timers queued so far, not the ones they queue.
    function env.__runTimers()
        local pending = env.__timers
        env.__timers = {}
        for _, fn in ipairs(pending) do fn() end
    end
    --- Every round until nothing is queued.
    function env.__runAllTimers()
        for _ = 1, 1000 do
            if #env.__timers == 0 then return end
            env.__runTimers()
        end
        error("timers never stopped queuing")
    end

    -- Items: name, quality (0 grey, 1 white) and sell price in copper.
    env.__items = {
        [3300] = { name = "Rabbit's Foot", quality = 0, price = 15 },
        [7073] = { name = "Broken Fang", quality = 0, price = 6 },
        [1411] = { name = "Withered Staff", quality = 0, price = 12345 },
        [9999] = { name = "Worthless Rock", quality = 0, price = 0 },
        [2589] = { name = "Linen Cloth", quality = 1, price = 13 },
        [6948] = { name = "Hearthstone", quality = 1, price = 0 },
    }
    -- Items the client has not described yet: asking about them gives nothing.
    env.__uncached = {}

    function env.__link(id)
        return "|cff9d9d9d|Hitem:" .. id .. "::::::::20:::::::|h[" .. env.__items[id].name .. "]|h|r"
    end

    -- Bags by number, and each slot's contents keyed "bag:slot":
    -- { itemID, count, locked }.
    env.__bagSizes = { [0] = 16, [1] = 6, [2] = 6, [3] = 6, [4] = 6 }
    env.__slots = {}
    -- Slots whose read raises, as the client does on a secret value.
    env.__raisingSlots = {}

    -- The merchant, the money, and what was done at it.
    env.__merchantOpen = false
    env.__money = 0
    env.__canRepair = true
    env.__repairCost = 0
    env.__repairs = 0
    -- Items the merchant will not take, without saying so.
    env.__refused = {}
    env.__sales = {}
    env.__log = {}

    local function slotKey(bag, slot)
        return bag .. ":" .. slot
    end

    env.C_Container = {
        GetContainerNumSlots = function(bag)
            return env.__bagSizes[bag] or 0
        end,
        GetContainerItemInfo = function(bag, slot)
            local key = slotKey(bag, slot)
            if env.__raisingSlots[key] then
                error("attempt to compare a secret value", 2)
            end
            local held = env.__slots[key]
            if not held then return nil end
            local item = env.__items[held.itemID]
            return {
                iconFileID = 1,
                stackCount = held.count,
                isLocked = held.locked == true,
                quality = item.quality,
                hasNoValue = item.price == 0,
                hyperlink = env.__link(held.itemID),
                itemID = held.itemID,
            }
        end,
        -- At an open merchant, using an item sells it.
        UseContainerItem = function(bag, slot)
            local key = slotKey(bag, slot)
            table.insert(env.__sales, key)
            table.insert(env.__log, "sell " .. key)
            local held = env.__slots[key]
            if not (env.__merchantOpen and held) or env.__refused[held.itemID] then
                return
            end
            env.__money = env.__money + env.__items[held.itemID].price * held.count
            env.__slots[key] = nil
        end,
    }

    env.C_Item = {
        GetItemInfo = function(id)
            local item = env.__items[id]
            if not item or env.__uncached[id] then return nil end
            return item.name, env.__link(id), item.quality, 1, 1, "Junk", "Junk", 1, "", 1, item.price
        end,
        GetItemNameByID = function(id)
            local item = env.__items[id]
            if item and not env.__uncached[id] then return item.name end
        end,
    }

    function env.GetMoney() return env.__money end
    function env.CanMerchantRepair() return env.__canRepair end
    function env.GetRepairAllCost() return env.__repairCost, env.__repairCost > 0 end
    function env.RepairAllItems()
        table.insert(env.__log, "repair")
        env.__repairs = env.__repairs + 1
        env.__money = env.__money - env.__repairCost
        env.__repairCost = 0
    end

    return env
end

--- The older client: no C_Container or C_Item, the old globals in their
-- place, answering the same way.
function stub.useLegacyAPI(env)
    local container, item = env.C_Container, env.C_Item
    env.C_Container, env.C_Item = nil, nil

    env.GetContainerNumSlots = container.GetContainerNumSlots
    function env.GetContainerItemInfo(bag, slot)
        local info = container.GetContainerItemInfo(bag, slot)
        if not info then return nil end
        return info.iconFileID, info.stackCount, info.isLocked, info.quality, false, false,
            info.hyperlink, false, info.hasNoValue, info.itemID
    end
    env.UseContainerItem = container.UseContainerItem
    env.GetItemInfo = item.GetItemInfo
end

return stub
```

- [ ] **Step 3: Write the test helpers**

Create `AutoVendor/tests/helpers.lua`:

```lua
local stub = require("wow_stub")

local M = {}

M.FILES = {
    "AutoVendor.lua",
}

--- Load the addon's files into a stubbed client, in .toc order, each chunk
-- receiving (addonName, privateTable). `saved` is AutoVendorDB as the
-- client would load it.
function M.loadAddon(saved)
    local env = stub.newEnv(saved)
    local ns = {}
    for _, path in ipairs(M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("AutoVendor", ns)
    end
    return ns, env
end

M.legacy = stub.useLegacyAPI

--- Fire an event on every frame registered for it.
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

function M.login(env)
    M.fire(env, "ADDON_LOADED", "AutoVendor")
    M.fire(env, "PLAYER_LOGIN")
end

--- A /reload: the same saved variables, a fresh addon, logged in.
function M.reload(env)
    local ns, fresh = M.loadAddon(env.AutoVendorDB)
    M.login(fresh)
    return ns, fresh
end

function M.put(env, bag, slot, itemID, count, locked)
    env.__slots[bag .. ":" .. slot] = { itemID = itemID, count = count or 1, locked = locked }
end

function M.openMerchant(env)
    env.__merchantOpen = true
    M.fire(env, "MERCHANT_SHOW")
end

function M.closeMerchant(env)
    env.__merchantOpen = false
    M.fire(env, "MERCHANT_CLOSED")
end

function M.command(env, text)
    env.SlashCmdList.AUTOVENDOR(text or "")
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

return M
```

- [ ] **Step 4: Write the manifest**

`run-tests.ps1` finds an addon by its `.toc`, so it comes before the first run. Create `AutoVendor/AutoVendor.toc`:

```
## Interface: 11509, 16001
## Title: AutoVendor
## Notes: Sells your grey items and repairs your gear whenever you open a merchant.
## Author: You
## Version: 0.1.0
## SavedVariables: AutoVendorDB

AutoVendor.lua
```

- [ ] **Step 5: Write the failing spec**

Create `AutoVendor/tests/addon_spec.lua`:

```lua
local helpers = require("helpers")

describe("the addon's chat lines", function()
    it("start with its name", function()
        local ns, env = helpers.loadAddon()

        ns.Print("hello")

        assertMatch("^|cff66ccffAutoVendor|r hello$", helpers.printed(env))
    end)
end)

describe("money words", function()
    it("spell out gold, silver and copper", function()
        local ns = helpers.loadAddon()

        assertEqual("1g 23s 45c", ns.Money(12345))
    end)

    it("leave out the parts that are zero", function()
        local ns = helpers.loadAddon()

        assertEqual("5s", ns.Money(500))
        assertEqual("1g", ns.Money(10000))
        assertEqual("1g 2s", ns.Money(10200))
    end)

    it("say 0c for nothing", function()
        local ns = helpers.loadAddon()

        assertEqual("0c", ns.Money(0))
    end)

    it("are the client's own, coin icons and all, where it has them", function()
        local ns, env = helpers.loadAddon()
        env.GetMoneyString = function(copper) return "MONEY:" .. copper end

        assertEqual("MONEY:5", ns.Money(5))
    end)
end)

describe("the saved variables", function()
    it("are made on the first login", function()
        local ns, env = helpers.loadAddon()

        helpers.login(env)

        assertEqual("table", type(env.AutoVendorDB))
        assertTrue(ns.db == env.AutoVendorDB)
    end)

    it("keep what an earlier session saved", function()
        local ns, env = helpers.loadAddon({ version = 1, custom = "kept" })

        helpers.login(env)

        assertEqual("kept", ns.db.custom)
    end)

    it("are filled in with the defaults a file registers", function()
        local ns, env = helpers.loadAddon()
        ns.AddDefaults({ things = { size = 3 } })

        helpers.login(env)

        assertEqual(3, ns.db.things.size)
    end)
end)

describe("/av", function()
    it("lists the registered commands", function()
        local ns, env = helpers.loadAddon()
        ns.RegisterCommand("test", "a test command", function() end)

        helpers.command(env, "")

        assertMatch("/av test %- a test command", helpers.printed(env))
    end)

    it("runs a command with what follows its name", function()
        local ns, env = helpers.loadAddon()
        local got
        ns.RegisterCommand("echo", "repeat", function(rest) got = rest end)

        helpers.command(env, "  ECHO Broken Fang  ")

        assertEqual("Broken Fang", got)
    end)

    it("gives the help for a command it does not know", function()
        local _, env = helpers.loadAddon()

        helpers.command(env, "dance")

        assertMatch("Unknown command: dance", helpers.printed(env))
        assertMatch("Commands:", helpers.printed(env))
    end)

    it("answers to /autovendor too", function()
        local _, env = helpers.loadAddon()

        assertEqual("/autovendor", env.SLASH_AUTOVENDOR1)
        assertEqual("/av", env.SLASH_AUTOVENDOR2)
    end)
end)
```

- [ ] **Step 6: Run it to see it fail**

Run: `.\run-tests.ps1 AutoVendor`
Expected: FAIL, every test, with `cannot open AutoVendor.lua`.

- [ ] **Step 7: Write the core**

Create `AutoVendor/AutoVendor.lua`:

```lua
local addonName, ns = ...

ns.PREFIX = "|cff66ccffAutoVendor|r"

-- Defaults are contributed by each file at load time, so every piece of
-- saved state lives next to the code that reads it.
local defaults = {
    version = 1,
}

--- Merge a defaults table into a saved one without clobbering stored values.
-- Recursive, so state added in a later version is filled in on upgrade.
local function applyDefaults(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            applyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

function ns.AddDefaults(extra)
    applyDefaults(defaults, extra)
end

function ns.Print(message)
    print(string.format("%s %s", ns.PREFIX, message))
end

--- Call `fn` and return what it returns, or `whenUnknown` if it raises.
-- This client hands addon code some values as secrets: the call succeeds,
-- but comparing or testing the result raises. The branch has to happen
-- inside `fn`, not on a value fetched through here and tested outside.
function ns.Guarded(fn, whenUnknown)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return whenUnknown
end

--- Copper as the game writes money, coin icons and all; "1g 23s 4c" on a
-- client without that.
function ns.Money(copper)
    if GetMoneyString then
        return GetMoneyString(copper)
    end

    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local rest = copper % 100

    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = gold .. "g"
    end
    if silver > 0 then
        parts[#parts + 1] = silver .. "s"
    end
    if rest > 0 or #parts == 0 then
        parts[#parts + 1] = rest .. "c"
    end
    return table.concat(parts, " ")
end

local function ensureDatabase()
    if type(AutoVendorDB) ~= "table" then
        AutoVendorDB = {}
    end

    applyDefaults(AutoVendorDB, defaults)
    ns.db = AutoVendorDB
end

-- Slash commands. Each file registers its own, so a feature owns its
-- commands and their help.
local commands = {}

function ns.RegisterCommand(name, help, handler)
    commands[name] = { help = help, handler = handler }
end

function ns.ShowHelp()
    ns.Print("Commands:")

    local names = {}
    for name in pairs(commands) do
        table.insert(names, name)
    end
    table.sort(names)

    for _, name in ipairs(names) do
        ns.Print(string.format("/av %s - %s", name, commands[name].help))
    end
end

local function runCommand(msg)
    local input = msg and msg:match("^%s*(.-)%s*$") or ""

    if input == "" or input == "help" then
        ns.ShowHelp()
        return
    end

    local name, rest = input:match("^(%S+)%s*(.-)$")
    name = name and name:lower() or ""

    local command = commands[name]
    if command then
        command.handler(rest)
        return
    end

    ns.Print(string.format("Unknown command: %s", name))
    ns.ShowHelp()
end

SLASH_AUTOVENDOR1 = "/autovendor"
SLASH_AUTOVENDOR2 = "/av"
SlashCmdList.AUTOVENDOR = runCommand

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ensureDatabase()
    elseif event == "PLAYER_LOGIN" then
        ensureDatabase()
    end
end)
```

- [ ] **Step 8: Run it and see it pass**

Run: `.\run-tests.ps1 AutoVendor`
Expected: `12 passed, 0 failed`.

- [ ] **Step 9: Commit**

```bash
git add AutoVendor
git commit -m "AutoVendor: the core -- saved variables, money words and /av" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Finding the junk in the bags

**Files:**
- Create: `AutoVendor/Bags.lua`
- Modify: `AutoVendor/AutoVendor.toc` (append `Bags.lua`)
- Modify: `AutoVendor/tests/helpers.lua` (`M.FILES` gains `"Bags.lua"`)
- Test: `AutoVendor/tests/bags_spec.lua`

**Interfaces:**
- Consumes: `ns.Guarded` (Task 1).
- Produces: `ns.Bags.Junk(keep) -> { { bag, slot, itemID, count, price }, ... }` in bag then slot order, where `keep` is a set `{ [itemID] = anything }` (nil means none); `ns.Bags.ItemAt(bag, slot) -> itemID | nil`.

- [ ] **Step 1: Write the failing spec**

Create `AutoVendor/tests/bags_spec.lua`:

```lua
local helpers = require("helpers")

describe("junk", function()
    it("is a grey item worth something, with where it is and what it fetches", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 3, 7073, 5)

        local junk = ns.Bags.Junk()

        assertEqual(1, #junk)
        assertEqual(0, junk[1].bag)
        assertEqual(3, junk[1].slot)
        assertEqual(7073, junk[1].itemID)
        assertEqual(5, junk[1].count)
        assertEqual(6, junk[1].price)
    end)

    it("is found in every bag, in bag order", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 4, 6, 3300)
        helpers.put(env, 0, 1, 7073)

        local junk = ns.Bags.Junk()

        assertEqual(2, #junk)
        assertEqual(0, junk[1].bag)
        assertEqual(4, junk[2].bag)
    end)
end)

describe("not junk", function()
    it("is a white item", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 1, 2589) -- Linen Cloth

        assertEqual(0, #ns.Bags.Junk())
    end)

    it("is a grey item no merchant will pay for", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 1, 9999) -- Worthless Rock

        assertEqual(0, #ns.Bags.Junk())
    end)

    it("is a grey item on the keep list", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 1, 7073)

        assertEqual(0, #ns.Bags.Junk({ [7073] = "Broken Fang" }))
    end)

    it("is a locked item", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 1, 7073, 1, true)

        assertEqual(0, #ns.Bags.Junk())
    end)

    it("is an item the client has not described yet", function()
        local ns, env = helpers.loadAddon()
        env.__uncached[7073] = true
        helpers.put(env, 0, 1, 7073)

        assertEqual(0, #ns.Bags.Junk())
    end)
end)

describe("a slot the client will not read", function()
    it("is skipped, and the slots after it are still read", function()
        local ns, env = helpers.loadAddon()
        env.__raisingSlots["0:1"] = true
        helpers.put(env, 0, 1, 7073)
        helpers.put(env, 0, 2, 3300)

        local junk = ns.Bags.Junk()

        assertEqual(1, #junk)
        assertEqual(2, junk[1].slot)
    end)
end)

describe("what a slot holds", function()
    it("is its item's ID", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 1, 2, 3300)

        assertEqual(3300, ns.Bags.ItemAt(1, 2))
    end)

    it("is nil when it is empty", function()
        local ns = helpers.loadAddon()

        assertNil(ns.Bags.ItemAt(1, 2))
    end)
end)

describe("the older client's calls", function()
    it("find the same junk", function()
        local ns, env = helpers.loadAddon()
        helpers.legacy(env)
        helpers.put(env, 0, 3, 7073, 5)
        helpers.put(env, 0, 4, 2589)

        local junk = ns.Bags.Junk()

        assertEqual(1, #junk)
        assertEqual(7073, junk[1].itemID)
        assertEqual(5, junk[1].count)
        assertEqual(6, junk[1].price)
    end)
end)
```

- [ ] **Step 2: Add the file to the load lists**

In `AutoVendor/tests/helpers.lua`, change `M.FILES` to:

```lua
M.FILES = {
    "AutoVendor.lua",
    "Bags.lua",
}
```

In `AutoVendor/AutoVendor.toc`, add `Bags.lua` as the last line.

- [ ] **Step 3: Run the tests to see them fail**

Run: `.\run-tests.ps1 AutoVendor`
Expected: every test fails, with `cannot open Bags.lua`.

- [ ] **Step 4: Write the reading**

Create `AutoVendor/Bags.lua`:

```lua
local addonName, ns = ...

-- Which bag slots hold junk: grey, worth something to a merchant, not kept
-- and not locked. Reading only, so it can be tested without a merchant.

local Bags = {}
ns.Bags = Bags

local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

local function lastBag()
    return NUM_BAG_SLOTS or 4
end

local function slotCount(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    if GetContainerNumSlots then
        return GetContainerNumSlots(bag) or 0
    end
    return 0
end

--- What a slot holds: { itemID, count, quality, locked, noValue }, or nil.
local function slotItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if type(info) ~= "table" or type(info.itemID) ~= "number" then
            return nil
        end
        return {
            itemID = info.itemID,
            count = info.stackCount or 1,
            quality = info.quality,
            locked = info.isLocked,
            noValue = info.hasNoValue,
        }
    end

    if GetContainerItemInfo then
        local _, count, locked, quality, _, _, _, _, noValue, itemID = GetContainerItemInfo(bag, slot)
        if type(itemID) ~= "number" then
            return nil
        end
        return { itemID = itemID, count = count or 1, quality = quality, locked = locked, noValue = noValue }
    end

    return nil
end

--- What a merchant pays for one, or nil when the client has not described
-- the item yet.
local function sellPrice(itemID)
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getItemInfo then
        return nil
    end
    local price = select(11, getItemInfo(itemID))
    return type(price) == "number" and price or nil
end

--- A slot's junk, { bag, slot, itemID, count, price }, or nil. One guarded
-- read, so a slot the client will not describe costs that slot and no other.
local function readSlot(bag, slot, keep)
    return ns.Guarded(function()
        local item = slotItem(bag, slot)
        if not item or item.quality ~= POOR or item.locked or item.noValue or keep[item.itemID] then
            return nil
        end

        local price = sellPrice(item.itemID)
        if not price or price <= 0 then
            return nil
        end
        return { bag = bag, slot = slot, itemID = item.itemID, count = item.count, price = price }
    end, nil)
end

function Bags.Junk(keep)
    keep = keep or {}
    local junk = {}

    for bag = 0, lastBag() do
        local slots = ns.Guarded(function()
            return slotCount(bag)
        end, 0)
        for slot = 1, slots do
            local found = readSlot(bag, slot, keep)
            if found then
                junk[#junk + 1] = found
            end
        end
    end

    return junk
end

--- The item ID in a slot, or nil when it is empty: how a sale is seen to
-- have gone through.
function Bags.ItemAt(bag, slot)
    return ns.Guarded(function()
        local item = slotItem(bag, slot)
        return item and item.itemID or nil
    end, nil)
end
```

- [ ] **Step 5: Run the tests and see them pass**

Run: `.\run-tests.ps1 AutoVendor`
Expected: `23 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add AutoVendor
git commit -m "AutoVendor: find the junk in the bags" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The keep list

**Files:**
- Create: `AutoVendor/Keep.lua`
- Modify: `AutoVendor/AutoVendor.toc` (append `Keep.lua`)
- Modify: `AutoVendor/tests/helpers.lua` (`M.FILES` gains `"Keep.lua"`)
- Test: `AutoVendor/tests/keep_spec.lua`

**Interfaces:**
- Consumes: `ns.AddDefaults`, `ns.db`, `ns.Print`, `ns.Guarded`, `ns.RegisterCommand`, `ns.ShowHelp` (Task 1).
- Produces: `ns.Keep.All() -> { [itemID] = name }` (the saved table itself), `ns.Keep.Has(itemID) -> boolean`; commands `keep`, `unkeep`, `list`.

- [ ] **Step 1: Write the failing spec**

Create `AutoVendor/tests/keep_spec.lua`:

```lua
local helpers = require("helpers")

local function ready()
    local ns, env = helpers.loadAddon()
    helpers.login(env)
    return ns, env
end

describe("/av keep", function()
    it("keeps an item from its Shift-clicked link", function()
        local ns, env = ready()

        helpers.command(env, "keep " .. env.__link(7073))

        assertTrue(ns.Keep.Has(7073))
        assertMatch("Keeping %[Broken Fang%]: it will not be sold%.", helpers.printed(env))
    end)

    it("keeps an item from its number", function()
        local ns, env = ready()

        helpers.command(env, "keep 3300")

        assertTrue(ns.Keep.Has(3300))
        assertMatch("Keeping %[Rabbit's Foot%]", helpers.printed(env))
    end)

    it("names an item the client has not described by its number", function()
        local ns, env = ready()
        env.__uncached[3300] = true

        helpers.command(env, "keep 3300")

        assertTrue(ns.Keep.Has(3300))
        assertMatch("Keeping %[item 3300%]", helpers.printed(env))
    end)

    it("says so when the item is kept already", function()
        local _, env = ready()
        helpers.command(env, "keep 7073")

        helpers.command(env, "keep " .. env.__link(7073))

        assertMatch("%[Broken Fang%] is already on the keep list%.", helpers.printed(env))
    end)

    it("gives the help for anything that is not an item", function()
        local ns, env = ready()

        helpers.command(env, "keep fang")

        assertMatch("Commands:", helpers.printed(env))
        assertEqual(nil, next(ns.Keep.All()))
    end)
end)

describe("/av unkeep", function()
    it("takes an item off the list", function()
        local ns, env = ready()
        helpers.command(env, "keep 7073")

        helpers.command(env, "unkeep " .. env.__link(7073))

        assertFalse(ns.Keep.Has(7073))
        assertMatch("No longer keeping %[Broken Fang%]%.", helpers.printed(env))
    end)

    it("says so when the item is not on the list", function()
        local _, env = ready()

        helpers.command(env, "unkeep 7073")

        assertMatch("%[Broken Fang%] is not on the keep list%.", helpers.printed(env))
    end)
end)

describe("/av list", function()
    it("says when the list is empty", function()
        local _, env = ready()

        helpers.command(env, "list")

        assertMatch("Nothing is on the keep list%.", helpers.printed(env))
    end)

    it("names every kept item, in name order", function()
        local _, env = ready()
        helpers.command(env, "keep 3300")
        helpers.command(env, "keep 7073")
        env.__printed = {}

        helpers.command(env, "list")

        local printed = helpers.printed(env)
        local fang = printed:find("[Broken Fang]", 1, true)
        local foot = printed:find("[Rabbit's Foot]", 1, true)
        assertTrue(fang and foot and fang < foot)
    end)
end)

describe("the keep list", function()
    it("is still there after a reload", function()
        local _, env = ready()
        helpers.command(env, "keep 7073")

        local ns = helpers.reload(env)

        assertTrue(ns.Keep.Has(7073))
    end)

    it("is in /av's help", function()
        local _, env = ready()

        helpers.command(env, "help")

        local printed = helpers.printed(env)
        assertMatch("/av keep", printed)
        assertMatch("/av unkeep", printed)
        assertMatch("/av list", printed)
    end)
end)
```

- [ ] **Step 2: Add the file to the load lists**

In `AutoVendor/tests/helpers.lua`, change `M.FILES` to:

```lua
M.FILES = {
    "AutoVendor.lua",
    "Bags.lua",
    "Keep.lua",
}
```

In `AutoVendor/AutoVendor.toc`, add `Keep.lua` as the last line.

- [ ] **Step 3: Run the tests to see them fail**

Run: `.\run-tests.ps1 AutoVendor`
Expected: every test fails, with `cannot open Keep.lua`.

- [ ] **Step 4: Write the keep list**

Create `AutoVendor/Keep.lua`:

```lua
local addonName, ns = ...

-- Items never sold, by item ID, with a name to show for each. One list for
-- every character: a grey worth keeping is worth keeping on any of them.

local Keep = {}
ns.Keep = Keep

ns.AddDefaults({
    keep = {},
})

function Keep.All()
    return ns.db.keep
end

function Keep.Has(itemID)
    return ns.db.keep[itemID] ~= nil
end

local function itemName(itemID)
    return ns.Guarded(function()
        if C_Item and C_Item.GetItemNameByID then
            local name = C_Item.GetItemNameByID(itemID)
            if type(name) == "string" then
                return name
            end
        end
        local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        local name = getItemInfo and getItemInfo(itemID)
        return type(name) == "string" and name or nil
    end, nil)
end

--- An item from what was typed: a Shift-clicked link, or a bare number.
-- Its ID and its name, or nil for anything else.
local function readItem(text)
    local id, name = text:match("|Hitem:(%d+)[^|]*|h%[(.-)%]|h")
    if id then
        return tonumber(id), name
    end

    id = text:match("^(%d+)$")
    if id then
        id = tonumber(id)
        return id, itemName(id) or ("item " .. id)
    end

    return nil
end

local function shown(name)
    return "[" .. name .. "]"
end

ns.RegisterCommand("keep", "never sell an item: Shift-click it after the command", function(rest)
    local id, name = readItem(rest)
    if not id then
        ns.ShowHelp()
        return
    end

    if Keep.Has(id) then
        ns.Print(string.format("%s is already on the keep list.", shown(ns.db.keep[id])))
        return
    end

    ns.db.keep[id] = name
    ns.Print(string.format("Keeping %s: it will not be sold.", shown(name)))
end)

ns.RegisterCommand("unkeep", "sell a kept item again: Shift-click it after the command", function(rest)
    local id, name = readItem(rest)
    if not id then
        ns.ShowHelp()
        return
    end

    if not Keep.Has(id) then
        ns.Print(string.format("%s is not on the keep list.", shown(name)))
        return
    end

    local kept = ns.db.keep[id]
    ns.db.keep[id] = nil
    ns.Print(string.format("No longer keeping %s.", shown(kept)))
end)

ns.RegisterCommand("list", "show the items that are never sold", function()
    local names = {}
    for _, name in pairs(ns.db.keep) do
        names[#names + 1] = name
    end

    if #names == 0 then
        ns.Print("Nothing is on the keep list.")
        return
    end

    table.sort(names)
    ns.Print("Never sold:")
    for _, name in ipairs(names) do
        ns.Print("  " .. shown(name))
    end
end)
```

- [ ] **Step 5: Run the tests and see them pass**

Run: `.\run-tests.ps1 AutoVendor`
Expected: `34 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add AutoVendor
git commit -m "AutoVendor: the keep list -- /av keep, unkeep and list" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The merchant visit

**Files:**
- Create: `AutoVendor/Vendor.lua`
- Modify: `AutoVendor/AutoVendor.toc` (append `Vendor.lua`)
- Modify: `AutoVendor/tests/helpers.lua` (`M.FILES` gains `"Vendor.lua"`)
- Test: `AutoVendor/tests/vendor_spec.lua`

**Interfaces:**
- Consumes: `ns.Bags.Junk(keep)`, `ns.Bags.ItemAt(bag, slot)` (Task 2), `ns.Keep.All()` (Task 3), `ns.Print`, `ns.Guarded`, `ns.Money` (Task 1).
- Produces: `ns.Vendor.PAUSE = 0.2`, `ns.Vendor.Open()`, `ns.Vendor.Close()`; listens to `MERCHANT_SHOW` and `MERCHANT_CLOSED`.

- [ ] **Step 1: Write the failing spec**

Create `AutoVendor/tests/vendor_spec.lua`:

```lua
local helpers = require("helpers")

local function ready()
    local ns, env = helpers.loadAddon()
    helpers.login(env)
    return ns, env
end

describe("opening a merchant", function()
    it("sells the first junk item at once, and the next after a pause", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)

        helpers.openMerchant(env)
        assertEqual(1, #env.__sales, "at once")
        assertEqual("0:1", env.__sales[1])

        env.__runTimers()
        assertEqual(2, #env.__sales, "after one pause")
        assertEqual("0:2", env.__sales[2])
    end)

    it("waits 0.2 seconds between sales", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)

        helpers.openMerchant(env)

        assertEqual(0.2, env.__timerDelays[1])
    end)

    it("sells every junk item and says what it earned", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300) -- 15c
        helpers.put(env, 0, 2, 7073, 5) -- 5 x 6c
        helpers.put(env, 1, 3, 1411) -- 1g 23s 45c

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertNil(env.__slots["0:1"])
        assertNil(env.__slots["0:2"])
        assertNil(env.__slots["1:3"])
        assertMatch("Sold 7 items for 1g 23s 90c%.", helpers.printed(env))
    end)

    it("says item for a single one", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertMatch("Sold 1 item for 15c%.", helpers.printed(env))
    end)

    it("leaves white, worthless and kept items alone", function()
        local ns, env = ready()
        helpers.put(env, 0, 1, 2589)
        helpers.put(env, 0, 2, 9999)
        helpers.put(env, 0, 3, 7073)
        ns.Keep.All()[7073] = "Broken Fang"

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(0, #env.__sales)
        assertEqual("", helpers.printed(env))
    end)

    it("sells loot that arrives during the visit", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)

        helpers.openMerchant(env)
        helpers.put(env, 0, 5, 7073)
        env.__runAllTimers()

        assertNil(env.__slots["0:5"])
        assertMatch("Sold 2 items for 21c%.", helpers.printed(env))
    end)

    it("does not count a sale the merchant refused, and tries it once", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)
        env.__refused[3300] = true

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(2, #env.__sales)
        assertMatch("Sold 1 item for 6c%.", helpers.printed(env))
    end)
end)

describe("closing the merchant", function()
    it("stops the selling and says what had sold", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)
        helpers.put(env, 0, 3, 1411)

        helpers.openMerchant(env)
        helpers.closeMerchant(env)
        env.__runAllTimers()

        assertEqual(1, #env.__sales)
        assertMatch("Sold 1 item for 15c%.", helpers.printed(env))
    end)

    it("does not repair", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)
        env.__money, env.__repairCost = 10000, 500

        helpers.openMerchant(env)
        helpers.closeMerchant(env)
        env.__runAllTimers()

        assertEqual(0, env.__repairs)
    end)

    it("says nothing when it closes without a visit", function()
        local _, env = ready()

        helpers.closeMerchant(env)
        helpers.closeMerchant(env)

        assertEqual("", helpers.printed(env))
    end)
end)

describe("opening again", function()
    it("ignores a second open signal during a visit", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)

        helpers.openMerchant(env)
        helpers.fire(env, "MERCHANT_SHOW")

        assertEqual(1, #env.__sales)
    end)

    it("starts a fresh visit after a close, without the old one's steps", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)
        helpers.put(env, 0, 3, 1411)
        helpers.put(env, 0, 4, 3300)

        helpers.openMerchant(env) -- sells 0:1
        helpers.closeMerchant(env)
        helpers.openMerchant(env) -- sells 0:2
        env.__runTimers()

        assertEqual(3, #env.__sales, "one sale per pause, not two")
    end)
end)

describe("repairing", function()
    it("comes after the selling", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)
        env.__money, env.__repairCost = 100, 50

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(1, env.__repairs)
        assertEqual("repair", env.__log[#env.__log])
        assertEqual("sell 0:2", env.__log[#env.__log - 1])
    end)

    it("is paid for with the junk's gold when your own falls short", function()
        local _, env = ready()
        helpers.put(env, 1, 1, 1411) -- 1g 23s 45c
        env.__money, env.__repairCost = 0, 10000

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(1, env.__repairs)
        assertMatch("Sold 1 item for 1g 23s 45c%. Repaired for 1g%.", helpers.printed(env))
    end)

    it("says what it cost", function()
        local _, env = ready()
        env.__money, env.__repairCost = 10000, 4500

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertMatch("^|cff66ccffAutoVendor|r Repaired for 45s%.$", helpers.printed(env))
    end)

    it("does not happen at a merchant that cannot repair", function()
        local _, env = ready()
        env.__money, env.__repairCost = 10000, 500
        env.__canRepair = false

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(0, env.__repairs)
        assertEqual("", helpers.printed(env))
    end)

    it("does not happen when nothing needs it", function()
        local _, env = ready()
        env.__money = 10000

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(0, env.__repairs)
        assertEqual("", helpers.printed(env))
    end)

    it("names the cost when the gold falls short, and repairs nothing", function()
        local _, env = ready()
        env.__money, env.__repairCost = 50, 10200

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(0, env.__repairs)
        assertMatch("Not enough gold to repair %(costs 1g 2s%)%.", helpers.printed(env))
    end)
end)

describe("the line", function()
    it("says nothing when there was nothing to do", function()
        local _, env = ready()

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual("", helpers.printed(env))
    end)

    it("puts the sale and the repair in one line", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)
        env.__money, env.__repairCost = 10000, 4500

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertMatch("^|cff66ccffAutoVendor|r Sold 2 items for 21c%. Repaired for 45s%.$", helpers.printed(env))
    end)
end)

describe("the older client's calls", function()
    it("sell the junk the same way", function()
        local _, env = ready()
        helpers.legacy(env)
        helpers.put(env, 0, 1, 3300)

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertNil(env.__slots["0:1"])
        assertMatch("Sold 1 item for 15c%.", helpers.printed(env))
    end)
end)
```

- [ ] **Step 2: Add the file to the load lists**

In `AutoVendor/tests/helpers.lua`, change `M.FILES` to:

```lua
M.FILES = {
    "AutoVendor.lua",
    "Bags.lua",
    "Keep.lua",
    "Vendor.lua",
}
```

In `AutoVendor/AutoVendor.toc`, add `Vendor.lua` as the last line.

- [ ] **Step 3: Run the tests to see them fail**

Run: `.\run-tests.ps1 AutoVendor`
Expected: every test fails, with `cannot open Vendor.lua`.

- [ ] **Step 4: Write the visit**

Create `AutoVendor/Vendor.lua`:

```lua
local addonName, ns = ...

-- A merchant visit: the junk sold one item at a time, then the repair, then
-- one line saying what happened.

local Vendor = {}
ns.Vendor = Vendor

-- Between sales. A server sent them faster refuses some ("That object is
-- busy") and leaves greys behind.
Vendor.PAUSE = 0.2

-- The visit under way, or nil. Each step is handed the visit it belongs to,
-- so one queued before a close does nothing in the visit after it.
local visit

local function sell(bag, slot)
    if C_Container and C_Container.UseContainerItem then
        C_Container.UseContainerItem(bag, slot)
    elseif UseContainerItem then
        UseContainerItem(bag, slot)
    end
end

-- A slot and what was in it: tried once per visit, so a sale the merchant
-- refused is not retried forever, while loot landing in a sold slot is new.
local function tried(entry)
    return entry.bag .. ":" .. entry.slot .. ":" .. entry.itemID
end

--- Count the last sale if its slot no longer holds the item.
local function settle(current)
    local last = current.pending
    current.pending = nil
    if last and ns.Bags.ItemAt(last.bag, last.slot) ~= last.itemID then
        current.items = current.items + last.count
        current.copper = current.copper + last.price * last.count
    end
end

local function nextJunk(current)
    for _, entry in ipairs(ns.Bags.Junk(ns.Keep.All())) do
        if not current.tried[tried(entry)] then
            return entry
        end
    end
    return nil
end

--- Repair if this merchant can and something needs it. The words for what
-- happened, or nil when nothing did.
local function repair()
    local canRepair = ns.Guarded(function()
        return CanMerchantRepair() and true or false
    end, false)
    if not canRepair then
        return nil
    end

    local cost = ns.Guarded(function()
        local amount, needed = GetRepairAllCost()
        if needed and type(amount) == "number" and amount > 0 then
            return amount
        end
        return 0
    end, 0)
    if cost == 0 then
        return nil
    end

    if GetMoney() < cost then
        return string.format("Not enough gold to repair (costs %s).", ns.Money(cost))
    end

    RepairAllItems()
    return string.format("Repaired for %s.", ns.Money(cost))
end

local function report(current, repaired)
    local parts = {}
    if current.items > 0 then
        parts[#parts + 1] = string.format("Sold %d %s for %s.",
            current.items, current.items == 1 and "item" or "items", ns.Money(current.copper))
    end
    if repaired then
        parts[#parts + 1] = repaired
    end
    if #parts > 0 then
        ns.Print(table.concat(parts, " "))
    end
end

--- End the visit. At the merchant it repairs first; after a close there is
-- nobody to repair at.
local function finish(current, atMerchant)
    settle(current)
    local repaired = atMerchant and repair() or nil
    report(current, repaired)
    visit = nil
end

local function step(current)
    if visit ~= current then
        return
    end

    settle(current)
    local entry = nextJunk(current)
    if not entry then
        finish(current, true)
        return
    end

    current.tried[tried(entry)] = true
    current.pending = entry
    sell(entry.bag, entry.slot)
    C_Timer.After(Vendor.PAUSE, function()
        step(current)
    end)
end

function Vendor.Open()
    -- Some clients say a merchant opened more than once per visit.
    if visit then
        return
    end
    visit = { items = 0, copper = 0, tried = {} }
    step(visit)
end

function Vendor.Close()
    if visit then
        finish(visit, false)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        Vendor.Open()
    else
        Vendor.Close()
    end
end)
```

- [ ] **Step 5: Run the tests and see them pass**

Run: `.\run-tests.ps1 AutoVendor`
Expected: `55 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add AutoVendor
git commit -m "AutoVendor: sell the junk one item at a time, then repair, then say so" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Icon, READMEs, package, and the game

**Files:**
- Modify: `tools/draw-icons.mjs` (a stack of silver coins for AutoVendor)
- Create: `AutoVendor/icon.tga` (generated)
- Modify: `AutoVendor/AutoVendor.toc` (`## IconTexture`)
- Create: `AutoVendor/README.md`
- Modify: `README.md` (root: a row in the addon table)
- Modify: `docs/superpowers/specs/2026-10-02-autovendor-design.md` ("Checked in game", after Carl's check)

**Interfaces:**
- Consumes: the finished addon (Tasks 1–4).
- Produces: `dist/AutoVendor-0.1.0.zip`, and the answers to the spec's "Checked in game".

- [ ] **Step 1: Draw the icon**

In `tools/draw-icons.mjs`, change the first comment line to:

```js
// Draws the 64x64 icons for BossLoot, FishScale, BankBags, GatherMap, RankUp and AutoVendor, and their minimap icons, in the style of
```

Before the line `const root = process.argv[2];`, add:

```js
// AutoVendor: a short stack of coins seen from the side, in silver.
const silver = {
  dark: [12, 14, 18], glow: [66, 74, 88], ring: [178, 188, 204],
  light: [246, 248, 252], mid: [170, 178, 194], outline: [46, 52, 62], detail: [92, 100, 116],
};
const coinStack = union(
  ellipse(32, 42, 18, 7), // the bottom coin's underside
  roundBox(32, 34, 18, 8, 0.5), // the stack's side
  ellipse(32, 26, 18, 7), // the top coin's face
);
const coinDetails = union(
  (x, y) => Math.abs(ellipse(32, 26, 18, 7)(x, y)) - 0.9, // the top face's rim
  (x, y) => Math.abs(ellipse(32, 26, 11, 4.2)(x, y)) - 0.8, // the face's inner ring
  (x, y) => Math.abs(y - 35) - 0.7 + (Math.abs(x - 32) > 17 ? 20 : 0), // the seam between two coins
);
const coinShine = ellipse(25, 24, 5, 1.4);
```

After the last `writeTga(...)` line, add:

```js
writeTga(path.join(root, 'AutoVendor', 'icon.tga'), draw(silver, coinStack, coinDetails, coinShine));
```

Run: `node tools/draw-icons.mjs .`
Then: `git status --short`
Expected: `AutoVendor/icon.tga` is new and `tools/draw-icons.mjs` modified; no other `.tga` changed.

Look at the icon: convert it to a PNG in the scratchpad and open it with the Read tool. Expected: a silver coin stack on a dark tile with a ring, like the other icons. If it reads badly, adjust the shapes (not the palette's role names) and redraw before going on.

- [ ] **Step 2: Point the manifest at it**

In `AutoVendor/AutoVendor.toc`, add after the `## Notes:` line:

```
## IconTexture: Interface\AddOns\AutoVendor\icon
```

- [ ] **Step 3: Write the README**

Create `AutoVendor/README.md`:

````markdown
# AutoVendor (World of Warcraft AddOn)

Open a merchant and your junk is sold and your gear repaired, without a
click. One chat line says what happened:

```
AutoVendor Sold 7 items for 1g 23s 4c. Repaired for 45s.
```

## What it sells

Grey (Poor quality) items in your bags that a merchant will pay for. Never
white items, trade goods or anything better, never an item with no sell
price (which spares most quest items), and never anything on your keep list.

Items go one at a time, a fifth of a second apart, because the server
refuses sales that come faster. Close the merchant partway and it stops, and
says what had sold.

## Repairs

After selling, so the junk's gold helps pay. If this merchant can repair and
something needs it, everything is repaired from your own gold. If you cannot
afford it, nothing is repaired and the line says what it would cost.

## The keep list

Items AutoVendor never sells, shared by all your characters.

| Command | Does |
|---|---|
| `/av keep` then Shift-click an item | Never sell it |
| `/av unkeep` then Shift-click an item | Sell it again |
| `/av list` | Show the list |

An item number works in place of a Shift-clicked link: `/av keep 7073`.
`/autovendor` is the same as `/av`.

## Worth knowing

The merchant's Buyback tab holds your last 12 sales. With more than 12 greys,
the earliest cannot be bought back, so put anything you might want on the
keep list before you visit.

There is no settings panel: everything happens on its own. To pause it,
disable AutoVendor in the AddOns list.

## Install

1. Copy this folder into your client's `Interface/AddOns` as `AutoVendor`,
   so the result is `.../Interface/AddOns/AutoVendor/AutoVendor.toc`.
2. Restart the client and enable AutoVendor from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 AutoVendor -Install

See the [repo README](../README.md) for packaging and test commands.
````

- [ ] **Step 4: Add AutoVendor to the root README's table**

In `README.md`, add after the RankUp row:

```markdown
| [AutoVendor](AutoVendor/) | Sells your grey items and repairs your gear whenever you open a merchant, with a keep list for greys you want |
```

- [ ] **Step 5: Run every suite and package**

Run: `.\run-tests.ps1`
Expected: every suite passes; AutoVendor shows `55 passed, 0 failed`.

Run: `.\package.ps1 AutoVendor`
Expected: `dist/AutoVendor-0.1.0.zip`, with no "listed but missing" error.

- [ ] **Step 6: Commit and push**

```bash
git add tools/draw-icons.mjs AutoVendor README.md
git commit -m "AutoVendor: icon and README" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push origin main
```

- [ ] **Step 7: Carl checks it in game, and the answers go into the spec**

On the machine Carl plays on: `git pull`, then `.\package.ps1 AutoVendor -Install`, restart, enable AutoVendor. Then ask Carl to, at a merchant on Forever:

1. Carry two or three greys, `/av keep` one of them, and open a merchant: the others sell one by one, the kept one stays, and the line names what sold.
2. Watch for "That object is busy" in chat: if it shows, `Vendor.PAUSE` goes up (to 0.3, then 0.5) and the check is repeated.
3. With damaged gear: the line says "Repaired for …" and the durability is full. With less gold than the cost: "Not enough gold to repair …".
4. Say whether the merchant window has its own "Sell All Junk" button (for the record).

Write the answers into "## Checked in game" in `docs/superpowers/specs/2026-10-02-autovendor-design.md`, dated, change its status line to `**Status:** approved, checked in game`, and commit:

```bash
git add docs/superpowers/specs/2026-10-02-autovendor-design.md
git commit -m "AutoVendor: what the game showed" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

If greys do not sell from addon code at all, stop and take it back to Carl: the selling approach changes.
