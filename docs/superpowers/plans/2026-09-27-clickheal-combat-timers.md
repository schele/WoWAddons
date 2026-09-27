# ClickHeal combat timers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the buff timers under ClickHeal's spell icons keep counting in combat, by having the game draw them through Blizzard's aura container.

**Architecture:** A new file, `ClickHeal/AuraSlots.lua`, gives each row an aura container on the row's unit, with two slots under every button. One slot takes only your own casts and draws a white number on a dark plate, on top. The other takes anyone else's and draws a grey number. The game writes the countdown into labels the slots own. `Row.lua` attaches the container when a row is built, points the slots at each button's spell when spells are applied, and skips its own timer text on rows the game draws. On a client without the container, nothing changes.

**Tech Stack:** Lua 5.1 in game (WoW Forever client `_classic_beta_` 1.60.1, build 70009). Tests run in Lua 5.4 with the repo's own runner: `.\run-tests.ps1 ClickHeal`, run from `C:\src\wow` in PowerShell.

**Spec:** `docs/superpowers/specs/2026-09-27-clickheal-combat-timers-design.md`

## Global Constraints

- The code must run in Lua 5.1: no `goto`, no `//`, no `table.unpack`, no reliance on `unpack`. The tests run it under 5.4.
- Anything that moves, sizes, shows or hides a frame runs out of combat only. The test stub raises for `SetPoint`, `SetSize`, `SetWidth`, `SetHeight`, `Show` and `Hide` while `env.__inCombat` is true, as the client does for protected frames.
- `ClickHeal.toc` keeps `## Interface: 11509, 16001`. The new file is listed after `Slots.lua` and before `Row.lua`.
- The slots' filter string is `"HELPFUL"`. Yours is `isFromPlayerOrPlayerPet = true`, anyone else's is `false`.
- Each slot's frame is anchored `"TOP", button, "BOTTOM", 0, -3` and sized `Row.TIMER_WIDTH` × `Row.TIMER_HEIGHT` (40 × 14). Its label is the same size.
- Your own number is white `(1, 1, 1)` on a plate `SetColorTexture(0, 0, 0, 0.85)`, 26 × 13, centred. Anyone else's is `Row.OTHERS_DIM` (0.55) grey.
- The number style matches `Row.FormatDuration`: "7s", "8m", "2h".
- Learned spell IDs last the session only. No new saved variables.
- Comments explain why, in the voice of the surrounding code, as the existing files do.

## Review Focus

1. **A button whose spell has no numeric spell ID**, such as a spell the spellbook lookup can't resolve. Both its slots should be switched off, not left matching every buff. Test in Task 2.
2. **A container the game refuses partway through**, for example `AddAuraSlot` raising, or `SetDurationText` refusing the label inside `initializeFrame`. The row should fall back to ClickHeal's own timers, with nothing of the half-built container on screen. Tests in Task 1.
3. **A secret spell ID on an aura** while learning. It should be skipped, not raise again on every refresh as a table key. Test in Task 3.
4. **An ID learned in combat.** Nothing should touch the slot filters until combat ends, and then the filters should widen. Test in Task 3.
5. **Changing the icon size.** The slots should follow the button, because they're anchored to it and never placed at absolute coordinates. Test in Task 1.

## Before starting

The working tree already holds uncommitted work from 2026-09-27: BossLoot and BankBags in the Options-style frame, and ClickHeal's gold border, label size fix, fuller `/ch auras` report and `/ch probe`. Ask Carl whether to commit it first, and on which branch this plan's work goes. The repo so far commits straight to `main`. Don't commit without that answer.

---

### Task 1: A container per row, with two slots under every button

**Files:**
- Create: `ClickHeal/AuraSlots.lua`
- Modify: `ClickHeal/Row.lua` (export three constants near the top; call `AuraSlots.Attach` at the end of `Row.Create`)
- Modify: `ClickHeal/tests/wow_stub.lua` (model the container, off by default)
- Test: `ClickHeal/tests/auraslots_spec.lua` (new)

**Interfaces:**
- Consumes: `ns.Guarded(fn, whenUnknown)` from `ClickHeal.lua`; `row.unit` and `row.buttons` from `Row.Create`.
- Produces:
  - `ns.AuraSlots.Attach(row) -> boolean`, which sets `row.auraContainer` (container widget) and `row.auraSlots[index] = { own = slot, other = slot }`. Each `slot = { key = "own1", frame = <slot frame>, label = <font string>, plate = <texture or nil>, ready = true }`.
  - `ns.AuraSlots.Drawn(row) -> boolean`.
  - `Row.TIMER_WIDTH`, `Row.TIMER_HEIGHT` and `Row.OTHERS_DIM` exported.

- [ ] **Step 1: Model the aura container in the test stub**

In `ClickHeal/tests/wow_stub.lua`, replace the whole `function env.CreateFrame(kind, name, parent, template) ... end` block (it starts right after the `env.__missingTemplates = {}` line) with:

```lua
    -- Blizzard's aura container (Blizzard_AuraContainer), which 1.60.1 has
    -- and older clients do not: off unless a test turns it on with
    --   env.__auraContainer = true
    -- Modelled on what /ch probe found in game on 2026-09-27. The slot's
    -- frame runs initializeFrame as it is made -- through securecallfunction
    -- in the client, so an error there is reported, not raised to the caller
    -- -- and SetDurationText refuses a label that is not that frame or one of
    -- its descendants. A test stages a refused AddAuraSlot with
    --   env.__auraSlotError = "the client's words"
    env.__auraContainer = false

    local function isDescendant(object, owner)
        local parent = object and object.parent
        while parent do
            if parent == owner then
                return true
            end
            parent = parent.parent
        end
        return false
    end

    -- The client copies what it is handed (securecopy), so a test can never
    -- see a later change to a table the addon keeps.
    local function copy(source)
        if type(source) ~= "table" then
            return source
        end
        local result = {}
        for key, value in pairs(source) do
            result[key] = copy(value)
        end
        return result
    end

    local function makeAuraContainer(parent, template)
        local container = makeWidget("AuraContainer", parent, template, env)
        container.slots = {}
        container.filterWrites = 0

        function container:SetUnit(unit) self.unit = unit end

        function container:AddAuraSlot(key, filterString, options)
            if env.__auraSlotError then
                error(env.__auraSlotError, 2)
            end
            options = options or {}

            local slot = makeWidget("AuraButton", self, "CustomAuraButtonTemplate", env)
            slot.key, slot.filterString = key, filterString
            slot.candidateFilters = copy(options.candidateFilters)
            slot.enabled = true

            function slot:SetDurationText(label, textOptions)
                if label ~= self and not isDescendant(label, self) then
                    error("bad object in function call (must be the owner or "
                        .. "a direct or indirect descendant of owner)", 2)
                end
                self.durationText, self.durationOptions = label, textOptions
            end

            self.slots[key] = slot
            if options.initializeFrame then
                pcall(options.initializeFrame, slot)
            end
            return slot
        end

        function container:GetAuraSlotFrame(key) return self.slots[key] end

        function container:SetAuraSlotEnabled(key, enabled)
            self.slots[key].enabled = enabled and true or false
        end

        function container:SetAuraSlotCandidateFilters(key, filters)
            self.filterWrites = self.filterWrites + 1
            self.slots[key].candidateFilters = copy(filters)
        end

        table.insert(env.__frames, container)
        return container
    end

    function env.CreateFrame(kind, name, parent, template)
        if template and env.__missingTemplates[template] then
            error(string.format("Couldn't find inherited node '%s'", template), 2)
        end

        if kind == "AuraContainer" then
            if not env.__auraContainer then
                error("CreateFrame: Unknown frame type 'AuraContainer'", 2)
            end
            return makeAuraContainer(parent, template)
        end

        local frame = makeWidget(kind or "Frame", parent, template, env)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        return frame
    end
```

- [ ] **Step 2: Write the failing tests**

Create `ClickHeal/tests/auraslots_spec.lua`:

```lua
local helpers = require("helpers")

local FILES = { "ClickHeal.lua", "Anchors.lua", "Spells.lua", "Slots.lua", "AuraSlots.lua", "Row.lua" }

--- Logged in on a client with the aura container, as 1.60.1 is.
local function loggedIn(setup)
    local ns, env = helpers.loadAddon(FILES)
    env.__auraContainer = true
    if setup then setup(env) end
    helpers.login(ns, env)
    return ns, env
end

--- A row for `unit` holding `spells` in its first slots, applied.
local function rowWith(ns, env, unit, spells)
    ns.db.bar.slots = #spells
    for index, spell in ipairs(spells) do
        ns.Slots.Set(index, spell)
    end
    local row = ns.Row.Create(unit, env.UIParent)
    ns.Row.ApplySpells(row)
    return row
end

describe("the game drawing a row's timers", function()
    it("gives a row one container, on the row's unit", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        assertTrue(ns.AuraSlots.Drawn(row))
        assertEqual("CustomAuraContainerTemplate", row.auraContainer.template)
        assertEqual("party1", row.auraContainer.unit)
        assertEqual(row, row.auraContainer:GetParent(), "shows, hides and fades with the row")
    end)

    it("puts two slots under every button: yours, and anyone else's", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        for index = 1, ns.Slots.MAX do
            local slots = row.auraSlots[index]
            assertEqual("HELPFUL", slots.own.frame.filterString)
            assertEqual("HELPFUL", slots.other.frame.filterString)
            assertEqual(true, slots.own.frame.candidateFilters.isFromPlayerOrPlayerPet)
            assertEqual(false, slots.other.frame.candidateFilters.isFromPlayerOrPlayerPet)
            assertFalse(slots.own.frame.enabled, "off until the button has a spell")
            assertFalse(slots.other.frame.enabled)
        end
    end)

    it("writes each number on its slot's own frame, just under the button", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        for index = 1, ns.Slots.MAX do
            for _, slot in pairs(row.auraSlots[index]) do
                assertEqual(slot.frame, slot.label:GetParent(), "the game refuses any other label")
                assertEqual(slot.label, slot.frame.durationText)
                local point, relativeTo, relativePoint, x, y = slot.frame:GetPoint(1)
                assertEqual("TOP", point)
                assertEqual(row.buttons[index], relativeTo, "follows the button when it is resized")
                assertEqual("BOTTOM", relativePoint)
                assertEqual(0, x)
                assertEqual(-3, y)
                assertEqual(40, slot.label.width)
                assertEqual(14, slot.label.height)
            end
        end
    end)

    it("draws yours white on a dark plate, above anyone else's grey", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)
        local slots = row.auraSlots[1]

        assertEqual(1, slots.own.label.textColor[1])
        assertEqual(0.85, slots.own.plate.colorTexture[4])
        assertEqual(slots.own.frame, slots.own.plate:GetParent())
        assertEqual(0.55, slots.other.label.textColor[1])
        assertNil(slots.other.plate)
        assertTrue(slots.own.frame:GetFrameLevel() > slots.other.frame:GetFrameLevel(),
            "your plate covers the grey number when both are there")
    end)

    it("leaves a row to ClickHeal's own timers on a client without the container", function()
        local ns, env = loggedIn(function(e) e.__auraContainer = false end)
        env.__now = 1000
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007 } }
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        assertFalse(ns.AuraSlots.Drawn(row))
        ns.Row.Refresh(row)
        assertEqual("7s", row.buttons[1].timer:GetText())
    end)

    it("falls back to ClickHeal's own timers when the game refuses a slot", function()
        local ns, env = loggedIn(function(e) e.__auraSlotError = "refused" end)
        local row = ns.Row.Create("party1", env.UIParent)

        assertFalse(ns.AuraSlots.Drawn(row))
        assertNil(row.auraSlots)
    end)

    it("falls back, and puts the half-built container away, when the game refuses a label", function()
        local ns, env = loggedIn()
        local created = env.CreateFrame
        env.CreateFrame = function(kind, name, parent, template)
            local made = created(kind, name, parent, template)
            if kind == "AuraContainer" then
                local add = made.AddAuraSlot
                function made:AddAuraSlot(key, filterString, options)
                    local slot = add(self, key, filterString, {
                        candidateFilters = options.candidateFilters,
                        initializeFrame = function(frame)
                            frame.SetDurationText = function() error("refused", 0) end
                            options.initializeFrame(frame)
                        end,
                    })
                    return slot
                end
            end
            return made
        end
        local row = ns.Row.Create("party1", env.UIParent)

        assertFalse(ns.AuraSlots.Drawn(row))
        local container
        for _, frame in ipairs(env.__frames) do
            if frame.kind == "AuraContainer" then container = frame end
        end
        assertFalse(container:IsShown(), "nothing half-built left on screen")
    end)
end)
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `.\run-tests.ps1 ClickHeal`
Expected: all seven `the game drawing a row's timers` tests FAIL, the fallback one included. `AuraSlots.lua` doesn't exist yet, so `helpers.loadAddon` raises a `cannot open AuraSlots.lua` error in each of them. All other tests still pass.

- [ ] **Step 4: Export the constants from `Row.lua`**

In `ClickHeal/Row.lua`, directly after `local TIMER_HEIGHT = 14`, add:

```lua

-- Read by AuraSlots, which lays the game's numbers out in the same box.
Row.TIMER_WIDTH = TIMER_WIDTH
Row.TIMER_HEIGHT = TIMER_HEIGHT
```

Directly after `local OTHERS_DIM = 0.55`, add:

```lua
Row.OTHERS_DIM = OTHERS_DIM
```

- [ ] **Step 5: Create `ClickHeal/AuraSlots.lua`**

```lua
local addonName, ns = ...

-- Buff timers the game draws. In combat 1.60.1 refuses ClickHeal every aura
-- read ("Auras cannot be accessed when secret while tainted by 'ClickHeal'"),
-- by index and by instance ID alike, so the numbers ClickHeal worked out
-- itself went blank the moment a fight began. Blizzard's aura container is a
-- frame an addon may create and the game fills from its own protected code,
-- which may read secret auras: one per row, on the row's unit, with two slots
-- under every button that the game shows, hides and counts down. See
-- docs/superpowers/specs/2026-09-27-clickheal-combat-timers-design.md.

local AuraSlots = {}
ns.AuraSlots = AuraSlots

-- The dark plate behind your own number. It covers someone else's copy of
-- the same buff, drawn underneath -- two druids' Rejuvenations stack -- and
-- reads better over bright ground.
local PLATE_WIDTH = 26
local PLATE_HEIGHT = 13
local PLATE_ALPHA = 0.85

--- What a slot takes: the buff's spell IDs, and whose cast.
local function filtersFor(ids, own)
    return { includeSpellIDs = ids, isFromPlayerOrPlayerPet = own }
end

--- One slot under `button`: yours (white on the plate, drawn on top) or
-- anyone else's (grey). Everything its frame needs is done in
-- initializeFrame, which the game runs on the new frame before it locks the
-- frame down. The label has to be that frame's own: SetDurationText refuses
-- any other ("must be the owner or a direct or indirect descendant of
-- owner"). The client runs initializeFrame through securecallfunction, so a
-- refusal in it never reaches this code; `ready` is how it is noticed.
local function addSlot(container, button, key, own)
    local slot = { key = key }

    local function initializeFrame(frame)
        frame:SetSize(ns.Row.TIMER_WIDTH, ns.Row.TIMER_HEIGHT)
        frame:SetPoint("TOP", button, "BOTTOM", 0, -3)
        frame:SetFrameLevel(container:GetFrameLevel() + (own and 2 or 1))

        if own then
            local plate = frame:CreateTexture(nil, "BACKGROUND")
            plate:SetColorTexture(0, 0, 0, PLATE_ALPHA)
            plate:SetSize(PLATE_WIDTH, PLATE_HEIGHT)
            plate:SetPoint("CENTER", frame, "CENTER")
            slot.plate = plate
        end

        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetSize(ns.Row.TIMER_WIDTH, ns.Row.TIMER_HEIGHT)
        label:SetPoint("CENTER", frame, "CENTER")
        if own then
            label:SetTextColor(1, 1, 1)
        else
            label:SetTextColor(ns.Row.OTHERS_DIM, ns.Row.OTHERS_DIM, ns.Row.OTHERS_DIM)
        end
        slot.label = label

        frame:SetDurationText(label)
        slot.ready = true
    end

    -- An empty map matches nothing, so the slot shows nothing until
    -- SetSpell gives it a spell; switched off as well, for good measure.
    slot.frame = container:AddAuraSlot(key, "HELPFUL", {
        candidateFilters = filtersFor({}, own),
        initializeFrame = initializeFrame,
    })
    if not slot.ready then
        error("slot " .. key .. " was not set up", 0)
    end
    container:SetAuraSlotEnabled(key, false)

    return slot
end

--- Give `row` a container on its unit and two slots under every button.
-- True if the game will draw this row's timers. False on a client without
-- the container, or if the game refuses any step -- and then the row keeps
-- ClickHeal's own timers, with nothing half-built left on screen. Called
-- once per row, from Row.Create, out of combat.
function AuraSlots.Attach(row)
    local container
    local built = pcall(function()
        container = CreateFrame("AuraContainer", nil, row, "CustomAuraContainerTemplate")
        container:SetUnit(row.unit)

        local slots = {}
        for index, button in ipairs(row.buttons) do
            slots[index] = {
                own = addSlot(container, button, "own" .. index, true),
                other = addSlot(container, button, "other" .. index, false),
            }
        end
        row.auraSlots = slots
    end)

    if not built then
        if container then
            pcall(container.Hide, container)
        end
        row.auraContainer, row.auraSlots = nil, nil
        return false
    end

    row.auraContainer = container
    return true
end

--- Whether the game draws this row's timers, rather than ClickHeal.
function AuraSlots.Drawn(row)
    return row.auraContainer ~= nil
end
```

- [ ] **Step 6: Call it from `Row.Create`**

In `ClickHeal/Row.lua`, in `Row.Create`, replace the final:

```lua
        button:Hide()
        row.buttons[index] = button
    end

    return row
end
```

with:

```lua
        button:Hide()
        row.buttons[index] = button
    end

    -- The game draws this row's timers where it can, which is what keeps
    -- them counting in combat: see AuraSlots.lua. Where it cannot, the row
    -- keeps button.timer, written by RefreshAuras.
    if ns.AuraSlots then
        ns.AuraSlots.Attach(row)
    end

    return row
end
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `.\run-tests.ps1 ClickHeal`
Expected: all seven `the game drawing a row's timers` tests PASS. All earlier ClickHeal tests still pass; they don't load `AuraSlots.lua`.

- [ ] **Step 8: Commit** (on the branch agreed under "Before starting")

```bash
git add ClickHeal/AuraSlots.lua ClickHeal/Row.lua ClickHeal/tests/wow_stub.lua ClickHeal/tests/auraslots_spec.lua
git commit -m "ClickHeal: a container per row for the game to draw the timers in

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Point each button's slots at its spell

**Files:**
- Modify: `ClickHeal/Spells.lua` (add `Spells.SpellID`, after `Spells.IsKnown`)
- Modify: `ClickHeal/AuraSlots.lua` (add `idsFor`, `applyFilters`, `AuraSlots.SetSpell`)
- Modify: `ClickHeal/Row.lua` (call `AuraSlots.SetSpell` from `Row.ApplySpells`)
- Modify: `ClickHeal/tests/wow_stub.lua` (spell IDs by name)
- Test: `ClickHeal/tests/spells_spec.lua`, `ClickHeal/tests/auraslots_spec.lua`

**Interfaces:**
- Consumes: `row.auraContainer` and `row.auraSlots` from Task 1.
- Produces:
  - `ns.Spells.SpellID(spellName) -> number or nil`.
  - `ns.AuraSlots.SetSpell(row, index, spell)`, which sets `row.auraSlots[index].spell`.
  - A local `applyFilters(row, slots)` in `AuraSlots.lua`, which Task 3 reuses.
  - A local `learned` table in `AuraSlots.lua`: `learned[spellName][spellId] = true`. Task 3 fills it.

- [ ] **Step 1: Give the stub spell IDs by name**

In `ClickHeal/tests/wow_stub.lua`, directly before `env.C_Spell = {`, add:

```lua
    -- The spell ID a name looks up to, for a test that needs a number: the
    -- aura container matches buffs by ID. Empty by default, which leaves a
    -- lookup by name answering with the name, as it always has here.
    --   env.__spellIDsByName["Rejuvenation"] = 774
    env.__spellIDsByName = {}
```

In `C_Spell.GetSpellInfo` in the same file, replace:

```lua
            return { name = name, spellID = identifier }
```

with:

```lua
            return { name = name, spellID = env.__spellIDsByName[identifier] or identifier }
```

- [ ] **Step 2: Write the failing tests**

In `ClickHeal/tests/spells_spec.lua`, add at the end of the file:

```lua
describe("a spell's ID", function()
    it("is the one the spellbook gives its name", function()
        local ns, env = loggedIn()
        env.__spellIDsByName["Rejuvenation"] = 774

        assertEqual(774, ns.Spells.SpellID("Rejuvenation"))
    end)

    it("is nil when the lookup gives no number", function()
        local ns = loggedIn()

        assertNil(ns.Spells.SpellID("Rejuvenation"), "the stub answers with the name")
        assertNil(ns.Spells.SpellID("Nothing Anyone Knows"))
        assertNil(ns.Spells.SpellID(nil))
        assertNil(ns.Spells.SpellID(""))
    end)
end)
```

In `ClickHeal/tests/auraslots_spec.lua`, add at the end of the file:

```lua
describe("pointing a button's slots at its spell", function()
    local function withIDs(e)
        e.__spellIDsByName["Rejuvenation"] = 774
        e.__spellIDsByName["Mark of the Wild"] = 1126
    end

    it("matches both slots to the button's spell by its ID, and switches them on", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })
        local slots = row.auraSlots[1]

        assertTrue(slots.own.frame.candidateFilters.includeSpellIDs[774])
        assertTrue(slots.other.frame.candidateFilters.includeSpellIDs[774])
        assertEqual(true, slots.own.frame.candidateFilters.isFromPlayerOrPlayerPet)
        assertEqual(false, slots.other.frame.candidateFilters.isFromPlayerOrPlayerPet)
        assertTrue(slots.own.frame.enabled)
        assertTrue(slots.other.frame.enabled)
    end)

    it("keeps the slots of a button with no spell switched off", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        assertFalse(row.auraSlots[2].own.frame.enabled)
        assertFalse(row.auraSlots[2].other.frame.enabled)
    end)

    it("switches a button's slots off when its spell has no ID, rather than matching every buff", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Healing Touch" })

        assertFalse(row.auraSlots[1].own.frame.enabled)
        assertFalse(row.auraSlots[1].other.frame.enabled)
    end)

    it("follows a change of spell", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        ns.Slots.Set(1, "Mark of the Wild")
        ns.Row.ApplySpells(row)

        local ids = row.auraSlots[1].own.frame.candidateFilters.includeSpellIDs
        assertTrue(ids[1126])
        assertNil(ids[774])
    end)

    it("takes its slots with it when a button is emptied", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })

        -- Emptied, not counted away: Slots.Count never goes below 1.
        ns.Slots.Set(1, "")
        ns.Row.ApplySpells(row)

        assertFalse(row.auraSlots[1].own.frame.enabled)
    end)
end)
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `.\run-tests.ps1 ClickHeal`
Expected:
- `a spell's ID` FAILS with `attempt to call a nil value (field 'SpellID')`.
- `matches both slots to the button's spell…` and `follows a change of spell` FAIL: `includeSpellIDs[774]` is nil and the slots are still disabled. The three tests that expect disabled slots already pass, because Task 1 leaves every slot off.

- [ ] **Step 4: Add `Spells.SpellID`**

In `ClickHeal/Spells.lua`, directly after the `end` that closes `function Spells.IsKnown(spellName)`, add:

```lua

--- The spell ID the spellbook gives `spellName`, or nil. The highest rank
-- known, which is the one a button casting by name casts. Only a number
-- counts: the aura container matches buffs by ID, and anything else would
-- match nothing while looking as if it matched.
function Spells.SpellID(spellName)
    if type(spellName) ~= "string" or spellName == "" then
        return nil
    end

    return ns.Guarded(function()
        local id
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spellName)
            id = type(info) == "table" and info.spellID or nil
        elseif GetSpellInfo then
            id = select(7, GetSpellInfo(spellName))
        end
        return type(id) == "number" and id or nil
    end, nil)
end
```

- [ ] **Step 5: Add `SetSpell` to `AuraSlots.lua`**

In `ClickHeal/AuraSlots.lua`, directly after `local PLATE_ALPHA = 0.85`, add:

```lua

-- Spell IDs seen on buffs out of combat, by the buff's name: other ranks,
-- and other casters' copies, that the spellbook knows nothing about. Kept
-- for the session only. Filled by AuraSlots.Learn.
local learned = {}
```

Directly after the `end` that closes `local function filtersFor(ids, own)`, add:

```lua

--- Every spell ID `spell` is known by, as the map a slot's filter wants:
-- the spellbook's, and any learned. Nil when there are none, and then the
-- button's slots are switched off rather than left to match every buff.
local function idsFor(spell)
    if not spell then
        return nil
    end

    local ids, any = {}, false
    local fromBook = ns.Spells.SpellID(spell)
    if fromBook then
        ids[fromBook] = true
        any = true
    end
    for id in pairs(learned[spell] or {}) do
        ids[id] = true
        any = true
    end

    return any and ids or nil
end

--- Point a button's two slots at its spell's IDs, or switch them off.
-- Guarded: a refusal here costs this button its number, never the caller
-- -- Row.ApplySpells, which the whole bar goes through.
local function applyFilters(row, slots)
    ns.Guarded(function()
        local ids = idsFor(slots.spell)
        for _, slot in ipairs({ slots.own, slots.other }) do
            if ids then
                row.auraContainer:SetAuraSlotCandidateFilters(slot.key, filtersFor(ids, slot == slots.own))
            end
            row.auraContainer:SetAuraSlotEnabled(slot.key, ids ~= nil)
        end
    end)
end
```

At the end of the file, add:

```lua

--- Point the slots under button `index` at `spell`, or at nothing. Out of
-- combat only, like every other change to a button: Row.ApplySpells calls
-- it for every button, every time.
function AuraSlots.SetSpell(row, index, spell)
    local slots = row.auraSlots and row.auraSlots[index]
    if not slots then
        return
    end

    slots.spell = spell
    applyFilters(row, slots)
end
```

- [ ] **Step 6: Call it from `Row.ApplySpells`**

In `ClickHeal/Row.lua`, in `Row.ApplySpells`, replace:

```lua
            button:SetAttribute("spell", nil)
            button.icon:Hide()
            button:Hide()
        end
    end

    -- Narrowed to what is actually on it
```

with:

```lua
            button:SetAttribute("spell", nil)
            button.icon:Hide()
            button:Hide()
        end

        -- Read back off the button, so the slots follow exactly the spell
        -- it will cast: a resurrection left off your own row takes its
        -- slots with it.
        if ns.AuraSlots then
            ns.AuraSlots.SetSpell(row, index, button:GetAttribute("spell"))
        end
    end

    -- Narrowed to what is actually on it
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `.\run-tests.ps1 ClickHeal`
Expected: all ClickHeal tests PASS.

- [ ] **Step 8: Commit**

```bash
git add ClickHeal/Spells.lua ClickHeal/AuraSlots.lua ClickHeal/Row.lua ClickHeal/tests/wow_stub.lua ClickHeal/tests/spells_spec.lua ClickHeal/tests/auraslots_spec.lua
git commit -m "ClickHeal: each button's slots match its spell by ID

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Learn other ranks' IDs out of combat; draw nothing itself on those rows

**Files:**
- Modify: `ClickHeal/Spells.lua` (`Spells.HelpfulAuras` records `spellId`)
- Modify: `ClickHeal/AuraSlots.lua` (add `attached`, `pending` and `AuraSlots.Learn`; record the row in `Attach`)
- Modify: `ClickHeal/Row.lua` (`Row.RefreshAuras`)
- Modify: `ClickHeal/tests/wow_stub.lua` (auras carry `spellId`)
- Test: `ClickHeal/tests/spells_spec.lua`, `ClickHeal/tests/auraslots_spec.lua`

**Interfaces:**
- Consumes: `applyFilters(row, slots)` and `learned` from Task 2; `row.auraSlots[index].spell`.
- Produces:
  - `ns.AuraSlots.Learn(auras)`, where `auras` is `Spells.HelpfulAuras`' table: `auras[name] = { expires = n, mine = bool, spellId = number or nil }`.
  - `Spells.HelpfulAuras` entries gain `spellId`.

- [ ] **Step 1: Let the stub's auras carry a spell ID**

In `ClickHeal/tests/wow_stub.lua`, in `local function auraData(aura)`, replace:

```lua
                { name = aura.name, expirationTime = aura.expirationTime },
```

with:

```lua
                { name = aura.name, expirationTime = aura.expirationTime, spellId = aura.spellId },
```

and replace:

```lua
        return {
            name = aura.name,
            expirationTime = aura.expirationTime,
            sourceUnit = auraCaster(aura),
        }
```

with:

```lua
        return {
            name = aura.name,
            expirationTime = aura.expirationTime,
            sourceUnit = auraCaster(aura),
            spellId = aura.spellId,
        }
```

- [ ] **Step 2: Write the failing tests**

In `ClickHeal/tests/spells_spec.lua`, add at the end of the file:

```lua
describe("the spell ID of a buff on someone", function()
    it("is kept with the buff", function()
        local ns, env = loggedIn()
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007, spellId = 1430 } }

        assertEqual(1430, ns.Spells.HelpfulAuras("party1").Rejuvenation.spellId)
    end)

    it("is left out when the client will not let us use it", function()
        -- A secret ID would raise again later, as a table key, on every
        -- refresh; left out, it costs only the learning.
        local ns, env = loggedIn()
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007, spellId = env.__secret() } }

        local aura = ns.Spells.HelpfulAuras("party1").Rejuvenation
        assertTrue(aura ~= nil, "the buff itself is still there")
        assertNil(aura.spellId)
    end)
end)
```

In `ClickHeal/tests/auraslots_spec.lua`, add at the end of the file:

```lua
describe("learning other ranks' IDs", function()
    local function withIDs(e)
        e.__spellIDsByName["Rejuvenation"] = 774
    end

    it("widens both slots with an ID seen on a buff out of combat", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007, spellId = 1430 } }

        ns.Row.Refresh(row)

        local slots = row.auraSlots[1]
        assertTrue(slots.own.frame.candidateFilters.includeSpellIDs[774], "the spellbook's still")
        assertTrue(slots.own.frame.candidateFilters.includeSpellIDs[1430])
        assertTrue(slots.other.frame.candidateFilters.includeSpellIDs[1430])
    end)

    it("waits for combat to end before touching the slots", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007, spellId = 1430 } }
        local writes = row.auraContainer.filterWrites

        env.__inCombat = true
        ns.Row.RefreshAuras(row)
        assertEqual(writes, row.auraContainer.filterWrites, "no filter changes in combat")

        env.__inCombat = false
        ns.Row.RefreshAuras(row)
        assertTrue(row.auraSlots[1].own.frame.candidateFilters.includeSpellIDs[1430])
    end)

    it("widens every row holding the spell, not just the one it was seen on", function()
        local ns, env = loggedIn(withIDs)
        local first = rowWith(ns, env, "party1", { "Rejuvenation" })
        local second = rowWith(ns, env, "party2", { "Rejuvenation" })
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007, spellId = 1430 } }

        ns.Row.Refresh(first)

        assertTrue(second.auraSlots[1].own.frame.candidateFilters.includeSpellIDs[1430])
    end)

    it("writes no number of its own on a row the game draws", function()
        local ns, env = loggedIn(withIDs)
        local row = rowWith(ns, env, "party1", { "Rejuvenation" })
        env.__now = 1000
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007, spellId = 774 } }

        ns.Row.Refresh(row)

        assertEqual("", row.buttons[1].timer:GetText(), "the game's number is the only one")
    end)
end)
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `.\run-tests.ps1 ClickHeal`
Expected:
- `the spell ID of a buff on someone > is kept with the buff` FAILS: `expected [1430], got [nil]`.
- The `learning other ranks' IDs` tests FAIL: `includeSpellIDs[1430]` is nil.
- `writes no number of its own on a row the game draws` FAILS: `expected [], got [7s]`.
- `is left out when the client will not let us use it` already passes.

- [ ] **Step 4: Record `spellId` in `Spells.HelpfulAuras`**

In `ClickHeal/Spells.lua`, in `Spells.HelpfulAuras`, make five replacements.

1. Replace `local name, expires, source` with:

```lua
            local name, expires, source, spellId
```

2. In the `C_UnitAuras` branch, replace:

```lua
                name, expires = data.name, data.expirationTime
```

with:

```lua
                name, expires, spellId = data.name, data.expirationTime, data.spellId
```

3. In the `UnitAura` branch, replace:

```lua
                -- name, icon, count, dispelType, duration, expirationTime, caster
                local found, _, _, _, _, expirationTime, caster =
                    UnitAura(unit, index, AURA_FILTER)
```

with:

```lua
                -- name, icon, count, dispelType, duration, expirationTime,
                -- caster, isStealable, nameplateShowPersonal, spellId
                local found, _, _, _, _, expirationTime, caster, _, _, id =
                    UnitAura(unit, index, AURA_FILTER)
```

4. In the same branch, replace:

```lua
                name, expires = found, expirationTime
```

with:

```lua
                name, expires, spellId = found, expirationTime, id
```

5. Replace the `auras[name] = { ... }` table with:

```lua
                auras[name] = {
                    expires = expires or 0,
                    -- Judged here, where the source is still in reach: a
                    -- caller holding the gathered table has no way back to
                    -- it.
                    mine = castByPlayer(source),
                    -- Only a number the client lets us do sums on. A secret
                    -- one would raise again as a table key, on every
                    -- refresh, in AuraSlots.Learn.
                    spellId = ns.Guarded(function()
                        return type(spellId) == "number" and spellId + 0 or nil
                    end, nil),
                }
```

- [ ] **Step 5: Add `Learn`, and keep a list of rows, in `AuraSlots.lua`**

In `ClickHeal/AuraSlots.lua`, directly after the `local learned = {}` block, add:

```lua

-- Every row the game draws, so an ID learned on one reaches them all.
local attached = {}

-- Names whose learned IDs have not reached the slots yet: filters are
-- changed out of combat only.
local pending = {}
```

In `AuraSlots.Attach`, replace:

```lua
    row.auraContainer = container
    return true
end
```

with:

```lua
    row.auraContainer = container
    attached[#attached + 1] = row
    return true
end
```

At the end of the file, add:

```lua

--- Take spell IDs from buffs read out of combat -- Spells.HelpfulAuras'
-- table, by name, each with its spellId -- and widen the slots of every
-- button holding that name, on every row. In combat the IDs wait for it to
-- end: slot filters are only changed out of combat. On 1.60.1 nothing can
-- be read in combat anyway, so what waits is only what a test stages.
function AuraSlots.Learn(auras)
    for name, aura in pairs(auras or {}) do
        local id = aura.spellId
        if type(id) == "number" then
            learned[name] = learned[name] or {}
            if not learned[name][id] then
                learned[name][id] = true
                pending[name] = true
            end
        end
    end

    if next(pending) == nil or (InCombatLockdown and InCombatLockdown()) then
        return
    end

    for _, row in ipairs(attached) do
        for _, slots in pairs(row.auraSlots) do
            if slots.spell and pending[slots.spell] then
                applyFilters(row, slots)
            end
        end
    end
    pending = {}
end
```

- [ ] **Step 6: Make `Row.RefreshAuras` learn, and draw nothing, on rows the game draws**

In `ClickHeal/Row.lua`, in `function Row.RefreshAuras(row)`, replace:

```lua
    local auras = ns.Spells.HelpfulAuras(row.unit)

    for index = 1, ns.Slots.MAX do
```

with:

```lua
    local auras = ns.Spells.HelpfulAuras(row.unit)

    -- The game draws this row's numbers, in combat too. What can still be
    -- read out of combat teaches its slots the IDs of other ranks and other
    -- casters' copies; button.timer stays empty, so there is one number.
    if ns.AuraSlots and ns.AuraSlots.Drawn(row) then
        ns.AuraSlots.Learn(auras)
        return
    end

    for index = 1, ns.Slots.MAX do
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `.\run-tests.ps1 ClickHeal`
Expected: all ClickHeal tests PASS.

- [ ] **Step 8: Commit**

```bash
git add ClickHeal/Spells.lua ClickHeal/AuraSlots.lua ClickHeal/Row.lua ClickHeal/tests/wow_stub.lua ClickHeal/tests/spells_spec.lua ClickHeal/tests/auraslots_spec.lua
git commit -m "ClickHeal: learn other ranks' IDs out of combat for the game's timers

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The numbers written as ClickHeal writes them

**Files:**
- Modify: `ClickHeal/AuraSlots.lua` (add `durationFormatter`; pass it to `SetDurationText`)
- Test: `ClickHeal/tests/auraslots_spec.lua`

**Interfaces:**
- Consumes: `addSlot` from Task 1.
- Produces: slot frames' `SetDurationText(label, { textFormatter = formatter })`, with `formatter` nil when the client lacks any part of it.

- [ ] **Step 1: Write the failing tests**

In `ClickHeal/tests/auraslots_spec.lua`, add at the end of the file:

```lua
-- The game's seconds formatter, as far as a test needs it: every setting it
-- is given, recorded.
local function withFormatter(e, leaveOut)
    e.Enum.SecondsFormatterAbbreviation = { None = 0, Truncate = 1, OneLetter = 2 }
    e.Enum.SecondsFormatterIntervalWhitespace = { Preserve = 0, Strip = 1, StripIgnoreLocale = 2 }
    e.Enum.SecondsFormatterInterval = { Seconds = 0, Minutes = 1, Hours = 2, Days = 3 }
    e.Enum.SecondsFormatterRounding = { RoundUp = 0, Truncate = 1 }
    e.C_StringUtil = {
        CreateSecondsFormatter = function()
            local formatter = { settings = {} }
            for _, setter in ipairs({ "SetDefaultAbbreviation", "SetStripIntervalWhitespace",
                "SetDesiredUnitCount", "SetMinInterval", "SetRounding", "SetCanRoundUpLastUnit" }) do
                if setter ~= leaveOut then
                    formatter[setter] = function(self, value) self.settings[setter] = value end
                end
            end
            return formatter
        end,
    }
end

describe("the game's numbers", function()
    it("are written as ClickHeal writes them: 7s, 8m, 2h", function()
        local ns, env = loggedIn(function(e) withFormatter(e) end)
        local row = ns.Row.Create("party1", env.UIParent)

        local formatter = row.auraSlots[1].own.frame.durationOptions.textFormatter
        assertEqual(2, formatter.settings.SetDefaultAbbreviation, "one letter")
        assertEqual(2, formatter.settings.SetStripIntervalWhitespace, "no space, whatever the locale")
        assertEqual(1, formatter.settings.SetDesiredUnitCount, "one unit")
        assertEqual(0, formatter.settings.SetMinInterval, "down to seconds")
        assertEqual(0, formatter.settings.SetRounding, "rounded up")
        assertEqual(true, formatter.settings.SetCanRoundUpLastUnit)
        assertEqual(formatter, row.auraSlots[1].other.frame.durationOptions.textFormatter, "one for all")
    end)

    it("fall back to the game's own style on a client missing part of the formatter", function()
        local ns, env = loggedIn(function(e) withFormatter(e, "SetStripIntervalWhitespace") end)
        local row = ns.Row.Create("party1", env.UIParent)

        assertTrue(ns.AuraSlots.Drawn(row), "a number in the game's style beats none")
        assertNil(row.auraSlots[1].own.frame.durationOptions.textFormatter)
    end)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `.\run-tests.ps1 ClickHeal`
Expected: `the game's numbers > are written as ClickHeal writes them` FAILS with `attempt to index a nil value (field 'durationOptions')`. `fall back to the game's own style…` also FAILS, the same way.

- [ ] **Step 3: Add the formatter**

In `ClickHeal/AuraSlots.lua`, directly after `local PLATE_ALPHA = 0.85`, add:

```lua

-- Made once, the first time a slot is set up: see durationFormatter.
local formatter

--- The formatter the game writes the numbers with, set up to match
-- Row.FormatDuration: "7s", "8m", "2h", one unit, rounded up. Nil on a
-- client missing any part of it, which leaves the game's own style ("8 m")
-- -- a number in another style beats no number.
local function durationFormatter()
    if formatter == nil then
        formatter = ns.Guarded(function()
            local made = C_StringUtil.CreateSecondsFormatter()
            made:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
            made:SetStripIntervalWhitespace(Enum.SecondsFormatterIntervalWhitespace.StripIgnoreLocale)
            made:SetDesiredUnitCount(1)
            made:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
            made:SetRounding(Enum.SecondsFormatterRounding.RoundUp)
            made:SetCanRoundUpLastUnit(true)
            return made
        end, false)
    end
    return formatter or nil
end
```

In `addSlot`, replace:

```lua
        frame:SetDurationText(label)
```

with:

```lua
        frame:SetDurationText(label, { textFormatter = durationFormatter() })
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `.\run-tests.ps1 ClickHeal`
Expected: all ClickHeal tests PASS.

- [ ] **Step 5: Commit**

```bash
git add ClickHeal/AuraSlots.lua ClickHeal/tests/auraslots_spec.lua
git commit -m "ClickHeal: the game's timers written as 7s, 8m, 2h

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Ship it: the TOC, `/ch auras`, no more `/ch probe`, the README

**Files:**
- Modify: `ClickHeal/ClickHeal.toc`
- Modify: `ClickHeal/tests/helpers.lua` (`M.FILES`)
- Modify: `ClickHeal/Group.lua` (the `/ch auras` line; delete the `/ch probe` block)
- Modify: `ClickHeal/README.md`
- Test: `ClickHeal/tests/group_spec.lua`

**Interfaces:**
- Consumes: `ns.AuraSlots.Drawn(row)` from Task 1.
- Produces: nothing new for other tasks.

- [ ] **Step 1: Write the failing tests**

In `ClickHeal/tests/group_spec.lua`, add at the end of the file:

```lua
describe("the aura report saying who draws the timers", function()
    local FILES_WITH_SLOTS = { "ClickHeal.lua", "Anchors.lua", "Spells.lua", "Slots.lua", "AuraSlots.lua", "Row.lua", "Group.lua" }

    local function reportWith(container)
        local ns, env = helpers.loadAddon(FILES_WITH_SLOTS)
        env.__auraContainer = container
        helpers.login(ns, env)
        helpers.command(env, "auras")
        return helpers.printed(env)
    end

    it("says the game draws them where it has the container", function()
        assertMatch("timers: drawn by the game", reportWith(true))
    end)

    it("says ClickHeal draws them where it does not", function()
        assertMatch("timers: drawn by ClickHeal", reportWith(false))
    end)

    it("has no probe any more", function()
        local ns, env = helpers.loadAddon(FILES_WITH_SLOTS)
        helpers.login(ns, env)

        helpers.command(env, "probe")

        assertMatch("Unknown command: probe", helpers.printed(env))
    end)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `.\run-tests.ps1 ClickHeal`
Expected: the two `timers: drawn by…` tests FAIL with `expected [...] to match [timers: drawn by the game]` (or `…ClickHeal`). `has no probe any more` FAILS, because `/ch probe` still exists.

- [ ] **Step 3: Print the line in `/ch auras`**

In `ClickHeal/Group.lua`, in the `ns.RegisterCommand("auras", ...)` handler, replace:

```lua
        for _, line in ipairs(ns.Spells.Report(unit, row and ns.Row.AssignedSpells(row))) do
            ns.Print(line)
        end
    end
end)
```

with:

```lua
        for _, line in ipairs(ns.Spells.Report(unit, row and ns.Row.AssignedSpells(row))) do
            ns.Print(line)
        end

        -- Which way this row's numbers reach the screen, because the reads
        -- above answer for ClickHeal's own way only: in combat they all
        -- fail on 1.60.1 while the game's own numbers go on counting.
        if row then
            ns.Print(string.format("  timers: %s",
                (ns.AuraSlots and ns.AuraSlots.Drawn(row))
                    and "drawn by the game (aura container)"
                    or "drawn by ClickHeal"))
        end
    end
end)
```

- [ ] **Step 4: Delete `/ch probe`**

In `ClickHeal/Group.lua`, delete everything from the line `-- THROWAWAY PROBE, 2026-09-27: delete once answered. In combat this client` through the `end)` that closes `ns.RegisterCommand("probe", ...)`. That includes the `local probe` line and `local function probeStep`. Keep the blank line that separated it from what follows.

- [ ] **Step 5: Load the new file in the game and in the default test list**

In `ClickHeal/ClickHeal.toc`, replace:

```
Slots.lua
Row.lua
```

with:

```
Slots.lua
AuraSlots.lua
Row.lua
```

In `ClickHeal/tests/helpers.lua`, in `M.FILES`, replace:

```lua
    "Slots.lua",
    "Row.lua",
```

with:

```lua
    "Slots.lua",
    "AuraSlots.lua",
    "Row.lua",
```

- [ ] **Step 6: Tell the README**

In `ClickHeal/README.md`, replace:

```
Blank means nobody has it on them, which is the signal to
click. It depends on the client being willing to say, on the same terms as
range above.
```

with:

```
Blank means nobody has it on them, which is the signal to
click. On WoW Forever the game writes these numbers itself, through its own
aura container: in combat it lets no addon read anyone's buffs, and the
game's own numbers are the ones that keep counting mid-fight. On a client
without that container, ClickHeal works them out itself, on the same terms
as range above.
```

- [ ] **Step 7: Run all tests**

Run: `.\run-tests.ps1`
Expected: every addon's suite passes, ClickHeal included.

- [ ] **Step 8: Package**

Run: `.\package.ps1 ClickHeal`
Expected: `Packaged 14 files -> C:\src\wow\dist\ClickHeal-0.1.0.zip`. That's one more file than before, `AuraSlots.lua`, which the script picks up from the `.toc`.

- [ ] **Step 9: Commit**

```bash
git add ClickHeal/ClickHeal.toc ClickHeal/tests/helpers.lua ClickHeal/Group.lua ClickHeal/README.md ClickHeal/tests/group_spec.lua
git commit -m "ClickHeal: ship the game-drawn timers; /ch auras says who draws them

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Check in the game, and settle the four risks

**Files:**
- Possibly modify: `ClickHeal/AuraSlots.lua` and its tests, only for a risk that turns out real. Each fix goes through its own failing test first.

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Install**

Run: `.\package.ps1 ClickHeal -Install`
Expected: `Installed -> C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\ClickHeal`.

Carl must **restart the game**, not `/reload`: the `.toc` gained a file.

- [ ] **Step 2: Ask Carl to check, in and out of combat**

Ask for a screenshot of each of these:
1. Thorns and Mark of the Wild on himself. Are his own row's numbers white on the plate, and still counting in a fight?
2. His Rejuvenation on a party member. Is it white, and still counting in a fight?
3. A buff someone else cast, if one is to hand, such as a paladin's blessing in a slot, or another druid's Mark. Is it grey?
4. A slot's spell changed in the settings. Does the number follow it?
5. The icon size changed. Do the numbers stay under the icons?
6. `/ch auras` shows `timers: drawn by the game (aura container)` for each unit.

- [ ] **Step 3: Settle each risk from what he saw**

- **Own row grey (spec risk 1).** If his own buffs on himself show grey rather than white, the game doesn't credit them to him on `"player"`. Then write a failing test in `auraslots_spec.lua`: a `"player"` row gets one slot per button, with `isFromPlayerOrPlayerPet` left nil, a white number and no plate. Then make `Attach` do that for `row.unit == "player"`.
- **Colour lost (risk 2).** If every number is white, grey ones included, the game resets the label colour. Then pass `options.textColor` with a flat colour curve for the grey slot. Look up `C_CurveUtil` in `scratchpad/forever-ui` (the cloned `forever` branch of `Gethe/wow-ui-source`) before writing it, and test first.
- **Plate under the grey number (risk 3).** If both numbers show when both buffs are there, the frame levels were reset. Then raise the own slot's frame level again after `AddAuraSlot` returns, test first.
- **Filters refused (risk 4).** If a slot never follows a spell change, `SetAuraSlotCandidateFilters` is refused. Then rebuild that button's two slots instead: a new slot key per change. Test first.

Each of these is a new change to the design, so agree it with Carl before writing its test. None of them runs unless the game shows the risk is real.

- [ ] **Step 4: Commit each fix on its own**

The message names the risk, for example for risk 1:

```bash
git add ClickHeal/AuraSlots.lua ClickHeal/tests/auraslots_spec.lua
git commit -m "ClickHeal: your own row's timers in one white slot; the game does not credit you on player

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
