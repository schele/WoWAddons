# Healclick Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A World of Warcraft addon that puts a row of spell buttons beside every party member, so healing, dispelling or buffing someone is one click on a button that already knows who it is for.

**Architecture:** Six Lua files in a new top-level `Healclick/` folder. `Slots.lua` holds the spell configuration and touches no game API, so the decisions are testable without a client. `Row.lua` builds one unit's row — name, health bar, and `Slots.MAX` `SecureActionButtonTemplate` buttons whose `unit` attribute is written once and never again. `Group.lua` owns the five rows, their order and the draggable anchor, and hands visibility to `RegisterUnitWatch`. Every secure write waits for combat to end.

**Tech Stack:** Lua 5.4 (tests), WoW Classic Lua 5.1 dialect (runtime), the repo's `run-tests.ps1` and `package.ps1`, and a hand-written stub of the WoW API under `Healclick/tests/`.

**Spec:** `docs/superpowers/specs/2026-09-19-healclick-design.md`

## Global Constraints

- `## Interface: 11509, 16001` — Classic Era 1.15.x and the 1.60.x Classic beta. Matches ForeverPanel and UrlCopy.
- **Runtime Lua is 5.1-flavoured.** Addon files must not use `goto`, integer division, or `table.unpack`. Test files run under Lua 5.4 and may.
- **An addon is a top-level folder holding `<name>.toc`.** Everything it needs lives inside it. Neither `run-tests.ps1` nor `package.ps1` may be edited, and `ForeverPanel/` and `UrlCopy/` must not be modified.
- **`package.ps1` builds its file list from the `.toc`.** Every Lua file must be listed there or it will not ship.
- **Addon code cannot cast a spell.** Every button is a `SecureActionButtonTemplate` carrying `type`, `spell` and `unit` attributes. Our Lua runs before and after, never instead.
- **No secure change happens in combat** — writing a spell attribute, changing the slot count, showing or hiding a button, or re-ordering rows. All of it waits for `PLAYER_REGEN_ENABLED`.
- **A button's `unit` attribute is written once at creation and never again.**
- SavedVariables table: `HealclickDB`. Slash commands: `/healclick` and `/hc`.
- Every file begins `local addonName, ns = ...` and hangs its exports off `ns`.
- Comments explain *why*, in the register the rest of the repo uses. No comment that restates the line below it.

## Running the tests

From the repo root, at any point after Task 2:

```powershell
.\run-tests.ps1 Healclick
```

---

### Task 1: The spike

**This task is not code you keep, and it cannot be run by an agent.** It is four questions that only the game client can answer, and every later task is built on the answers. It ends by handing the probe to the human and stopping.

**Files:**
- Create: `%LOCALAPPDATA%`-independent — write directly into the client at `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\HealclickProbe\HealclickProbe.toc` and `...\HealclickProbe.lua`
- **Nothing in this task is committed to the repo.**

**Interfaces:**
- Consumes: nothing.
- Produces: four answers, recorded in the ledger or the conversation, which Tasks 2-9 depend on.

- [ ] **Step 1: Write the probe's TOC**

Create `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\HealclickProbe\HealclickProbe.toc`:

```
## Interface: 11509, 16001
## Title: Healclick Probe (throwaway)
## Notes: Four questions. Delete this addon once they are answered.
## Version: 0.0.1
## SavedVariables: HealclickProbeDB

HealclickProbe.lua
```

- [ ] **Step 2: Write the probe**

Create `...\HealclickProbe\HealclickProbe.lua`:

```lua
-- Throwaway. Four questions the test harness cannot answer, because they are
-- about what Blizzard's client permits rather than about our own logic.
-- Delete this folder once they are answered.

local PREFIX = "|cff66ccffProbe|r"

local function say(message)
    print(PREFIX .. " " .. message)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function()
    -- Q4: does anything persist between sessions on this client?
    HealclickProbeDB = HealclickProbeDB or {}
    local before = HealclickProbeDB.logins or 0
    HealclickProbeDB.logins = before + 1
    say(string.format(
        "Q4 SavedVariables: this addon has been loaded %d times before. "
        .. "If this says 0 every login, nothing persists.", before
    ))

    -- Q1: does a secure button actually cast?
    local container = CreateFrame("Frame", "HealclickProbeContainer", UIParent)
    container:SetSize(160, 40)
    container:SetPoint("CENTER", 0, 140)

    local cast = CreateFrame(
        "Button", "HealclickProbeCast", container, "SecureActionButtonTemplate"
    )
    cast:SetAllPoints()
    cast:RegisterForClicks("AnyUp")
    cast:SetAttribute("type", "spell")
    -- A spell every character of this class has from level 1. Change it if the
    -- character running this does not know it.
    cast:SetAttribute("spell", "Healing Touch")
    cast:SetAttribute("unit", "player")
    cast:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")

    local label = cast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText("Q1: heal me")

    -- Q2: does RegisterUnitWatch show and hide with the party member?
    local watched = CreateFrame("Frame", "HealclickProbeWatch", UIParent)
    watched:SetSize(160, 24)
    watched:SetPoint("CENTER", 0, 95)
    watched:SetAttribute("unit", "party1")

    local background = watched:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.7)

    local watchedLabel = watched:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    watchedLabel:SetPoint("CENTER")
    watchedLabel:SetText("Q2: party1 exists")

    if RegisterUnitWatch then
        RegisterUnitWatch(watched)
    else
        say("Q2: RegisterUnitWatch does not exist on this client.")
    end

    -- Q3: what can be moved in combat -- the secure button, or the ordinary
    -- frame that merely contains it?
    SLASH_HCPROBE1 = "/hcprobe"
    SlashCmdList.HCPROBE = function()
        local combat = InCombatLockdown and InCombatLockdown() or false
        say(string.format("Q3 in combat: %s", tostring(combat)))

        local okButton, errButton = pcall(function()
            cast:SetPoint("CENTER", 0, 140)
        end)
        say(string.format(
            "Q3 moving the secure button: ok=%s %s",
            tostring(okButton), tostring(errButton or "")
        ))

        local okContainer, errContainer = pcall(function()
            container:SetPoint("CENTER", 0, 140)
        end)
        say(string.format(
            "Q3 moving its ordinary parent: ok=%s %s",
            tostring(okContainer), tostring(errContainer or "")
        ))
    end

    say("Loaded. See the two frames in the middle of the screen.")
end)
```

- [ ] **Step 3: Hand it to the human and stop**

Tell them, in these words or close to them:

> The probe is installed. In game: `/reload`, then
>
> 1. **Q1** — click the "heal me" button. Do you cast? If a spell fires, secure buttons work as the design assumes.
> 2. **Q2** — the "party1 exists" box should be invisible alone, and appear when you group with someone. Invite someone, then have them leave *while you are in combat*. Does the box disappear?
> 3. **Q3** — pull a mob, and while fighting type `/hcprobe`. It prints two lines: whether the secure button could be moved, and whether its ordinary parent could. Also watch for the red "Interface action failed because of an AddOn" popup.
> 4. **Q4** — printed at login. Reload twice; if the count never rises above 0, this client really does discard SavedVariables.
>
> Report the four answers and I'll carry on.

**Do not start Task 2 until Q1 is answered.** If secure buttons do not cast on this client, the addon as designed cannot exist and the design needs revisiting, not implementing. Q2, Q3 and Q4 change details; Q1 decides whether there is anything to build.

- [ ] **Step 4: Delete the probe once the answers are in**

```powershell
Remove-Item -Recurse -Force "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\HealclickProbe"
```

---

### Task 2: Addon skeleton and test harness

**Files:**
- Create: `Healclick/Healclick.toc`
- Create: `Healclick/Healclick.lua`
- Create: `Healclick/tests/runner.lua`
- Create: `Healclick/tests/wow_stub.lua`
- Create: `Healclick/tests/helpers.lua`
- Test: `Healclick/tests/addon_spec.lua`
- Modify: `README.md` (add a row to the addon table)

**Interfaces:**
- Consumes: nothing.
- Produces, on `ns`:
  - `ns.PREFIX`, `ns.Print(message)`
  - `ns.applyDefaults(target, source)`, `ns.AddDefaults(extra)`
  - `ns.RegisterSetting(definition)` — `{ store, key, type = "checkbox"|"slider"|"spelltable", name, tooltip?, min?, max?, step?, rows?, onChange? }`
  - `ns.SettingValue(setting)`, `ns.SetSettingValue(setting, value)`, `ns.settings`
  - `ns.RegisterCommand(name, help, handler)`, `ns.RegisterHelpLine(line)`, `ns.ShowHelp()`
  - `ns.OnLogin(handler)`, `ns.ensureDatabase()`, `ns.db`
- Produces, for tests: `helpers.loadAddon`, `helpers.login`, `helpers.command`, `helpers.printed`, `helpers.rowFor`, `helpers.attrs`, plus the stub's `env.units` table and `env.__setCombat`.

- [ ] **Step 1: Create the folder and the TOC**

Create `Healclick/Healclick.toc`:

```
## Interface: 11509, 16001
## Title: Healclick
## Notes: A row of spell buttons beside every party member.
## IconTexture: Interface\Icons\Spell_Nature_HealingTouch
## Author: You
## Version: 0.1.0
## SavedVariables: HealclickDB

Healclick.lua
Slots.lua
Row.lua
Group.lua
Settings.lua
```

The four files below `Healclick.lua` do not exist yet. That is deliberate and it is why this task does not run `package.ps1`: it would correctly fail. Task 9 is the first packaging run.

- [ ] **Step 2: Copy the spec runner**

```powershell
New-Item -ItemType Directory -Force Healclick\tests | Out-Null
Copy-Item UrlCopy\tests\runner.lua Healclick\tests\runner.lua
```

It is a generic runner with nothing addon-specific in it.

- [ ] **Step 3: Write the WoW stub**

Create `Healclick/tests/wow_stub.lua`. This is UrlCopy's stub with the chat and popup machinery removed, and the secure-frame, combat and unit API added.

```lua
-- A minimal stand-in for the WoW API, enough to load the addon outside the
-- game. Widgets record what was done to them so tests can assert on it.
--
-- The point of interest is SetAttribute. We can never test that Blizzard casts
-- the right spell; we can test that we asked it to.

local stub = {}

local function makeWidget(kind, parent, template)
    local widget = {
        kind = kind,
        parent = parent,
        template = template,
        points = {},
        scripts = {},
        registeredEvents = {},
        children = {},
        attributes = {},
        width = 0,
        height = 0,
        shown = true,
        text = "",
        alpha = 1,
        value = 0,
        minValue = 0,
        maxValue = 1,
    }

    function widget:SetPoint(...) table.insert(self.points, { ... }) end
    function widget:ClearAllPoints() self.points = {} end
    function widget:SetAllPoints() end
    function widget:GetPoint(index)
        local point = self.points[index or 1]
        if point then return table.unpack(point) end
    end

    function widget:SetWidth(value) self.width = value end
    function widget:GetWidth() return self.width end
    function widget:SetHeight(value) self.height = value end
    function widget:GetHeight() return self.height end
    function widget:SetSize(w, h) self.width, self.height = w, h end

    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:SetShown(value) self.shown = value and true or false end
    function widget:IsShown() return self.shown end

    function widget:SetScript(name, fn) self.scripts[name] = fn end
    function widget:GetScript(name) return self.scripts[name] end
    function widget:HookScript(name, fn)
        local existing = self.scripts[name]
        self.scripts[name] = function(...)
            if existing then existing(...) end
            fn(...)
        end
    end

    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end
    function widget:RegisterForClicks() end
    function widget:RegisterForDrag() end
    function widget:EnableMouse() end
    function widget:SetMovable() end
    function widget:StartMoving() self.moving = true end
    function widget:StopMovingOrSizing() self.moving = false end
    function widget:SetFrameStrata() end
    function widget:SetJustifyH() end
    function widget:SetNormalTexture() end
    function widget:SetAutoFocus(value) self.autoFocus = value and true or false end
    function widget:ClearFocus() self.focused = false end
    function widget:SetFocus() self.focused = true end
    function widget:HighlightText() end
    function widget:SetMaxLetters() end

    -- The whole point. Secure attributes are what the client acts on, so the
    -- tests assert on these rather than on anything happening.
    function widget:SetAttribute(name, value) self.attributes[name] = value end
    function widget:GetAttribute(name) return self.attributes[name] end

    function widget:SetAlpha(value) self.alpha = value end
    function widget:GetAlpha() return self.alpha end

    function widget:SetMinMaxValues(low, high) self.minValue, self.maxValue = low, high end
    function widget:GetMinMaxValues() return self.minValue, self.maxValue end
    function widget:SetValue(value)
        self.value = value
        local handler = self.scripts.OnValueChanged
        if handler then handler(self, value) end
    end
    function widget:GetValue() return self.value end
    function widget:SetValueStep() end
    function widget:SetObeyStepOnDrag() end
    function widget:SetStatusBarColor(r, g, b) self.barColor = { r, g, b } end

    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end

    function widget:SetText(value)
        self.text = value or ""
        local handler = self.scripts.OnTextChanged
        if handler then handler(self) end
    end
    function widget:GetText() return self.text end
    function widget:GetName() return self.frameName end
    function widget:SetTextColor(r, g, b) self.textColor = { r, g, b } end
    function widget:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end

    function widget:CreateTexture()
        local texture = makeWidget("Texture", self)
        table.insert(self.children, texture)
        return texture
    end

    function widget:CreateFontString()
        local fontString = makeWidget("FontString", self)
        table.insert(self.children, fontString)
        return fontString
    end

    function widget:GetParent() return self.parent end
    function widget:SetParent(value) self.parent = value end

    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then handler(self, event, ...) end
    end

    return widget
end

stub.makeWidget = makeWidget

function stub.newEnv()
    local env = setmetatable({}, { __index = _G })

    env.__frames = {}
    env.__printed = {}
    env.__watched = {}
    env.__inCombat = false
    env._G = env

    env.UIParent = makeWidget("Frame")
    env.SlashCmdList = {}
    env.OKAY = "Okay"

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do
            pieces[index] = tostring((select(index, ...)))
        end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    function env.CreateFrame(kind, name, parent, template)
        local frame = makeWidget(kind or "Frame", parent, template)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        return frame
    end

    -- Combat ------------------------------------------------------------
    function env.InCombatLockdown() return env.__inCombat end

    --- Test helper: enter or leave combat, firing the event the client fires.
    function env.__setCombat(inCombat)
        env.__inCombat = inCombat and true or false
        local event = inCombat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED"
        for _, frame in ipairs(env.__frames) do
            if frame.registeredEvents[event] then
                frame:Fire(event)
            end
        end
    end

    -- Units --------------------------------------------------------------
    -- Tests edit this table directly: env.units.party2.health = 30
    env.units = {
        player = { name = "Skyler", class = "DRUID", health = 100, healthMax = 100, connected = true, dead = false, inRange = true },
        party1 = { name = "Borgir", class = "WARRIOR", health = 80, healthMax = 100, connected = true, dead = false, inRange = true },
        party2 = { name = "Nimue", class = "MAGE", health = 50, healthMax = 100, connected = true, dead = false, inRange = true },
    }

    local function unit(id) return env.units[id] end

    function env.UnitExists(id) return unit(id) ~= nil end
    function env.UnitName(id) local u = unit(id) return u and u.name end
    function env.UnitClass(id)
        local u = unit(id)
        if not u then return nil end
        return u.class, u.class
    end
    function env.UnitHealth(id) local u = unit(id) return u and u.health or 0 end
    function env.UnitHealthMax(id) local u = unit(id) return u and u.healthMax or 0 end
    function env.UnitIsDeadOrGhost(id) local u = unit(id) return u and u.dead or false end
    function env.UnitIsConnected(id) local u = unit(id) return u and u.connected or false end
    function env.UnitInRange(id)
        local u = unit(id)
        if not u then return false, false end
        return u.inRange and true or false, true
    end

    env.RAID_CLASS_COLORS = {
        DRUID   = { r = 1.00, g = 0.49, b = 0.04 },
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
        MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
        PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
    }

    -- Spells --------------------------------------------------------------
    -- Everything the client "knows". A name outside this list is unknown,
    -- which is a warning rather than a refusal: a player may be configuring
    -- a spell they have not learned yet.
    env.__spells = {
        ["Regrowth"] = true,
        ["Rejuvenation"] = true,
        ["Remove Curse"] = true,
        ["Mark of the Wild"] = true,
        ["Healing Touch"] = true,
    }

    function env.GetSpellInfo(name)
        if env.__spells[name] then return name end
        return nil
    end

    -- Secure visibility ----------------------------------------------------
    function env.RegisterUnitWatch(frame)
        env.__watched[#env.__watched + 1] = frame
        frame.unitWatched = true
    end

    function env.UnregisterUnitWatch(frame)
        frame.unitWatched = false
    end

    -- Settings -------------------------------------------------------------
    env.SettingsPanel = makeWidget("Frame")
    env.GameMenuFrame = makeWidget("Frame")
    function env.HideUIPanel(frame) if frame and frame.Hide then frame:Hide() end end

    env.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            return { name = name, frame = frame, GetID = function() return "category-id" end }
        end,
        RegisterAddOnCategory = function(category) env.__settingsCategory = category end,
        OpenToCategory = function(id) env.__openedCategory = id end,
    }

    env.C_AddOns = {
        GetAddOnMetadata = function(_, field)
            return field == "Version" and "9.9.9" or nil
        end,
    }

    env.__timers = {}
    env.__tickers = {}

    env.C_Timer = {
        After = function(_, fn) table.insert(env.__timers, fn) end,
        NewTicker = function(interval, fn)
            local ticker = { interval = interval, fn = fn, Cancel = function() end }
            table.insert(env.__tickers, ticker)
            return ticker
        end,
    }

    function env.__runTimers()
        local pending = env.__timers
        env.__timers = {}
        for _, fn in ipairs(pending) do fn() end
    end

    --- Test helper: run every ticker once, the way a few seconds would.
    function env.__tick()
        for _, ticker in ipairs(env.__tickers) do ticker.fn() end
    end

    function env.hooksecurefunc(target, name, post)
        if type(target) == "string" then
            target, name, post = env, target, name
        end
        local original = target[name]
        target[name] = function(...)
            local result = original(...)
            post(...)
            return result
        end
    end

    return env
end

return stub
```

- [ ] **Step 4: Write the test helpers**

Create `Healclick/tests/helpers.lua`:

```lua
local stub = require("wow_stub")

local M = {}

M.FILES = {
    "Healclick.lua",
    "Slots.lua",
    "Row.lua",
    "Group.lua",
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
        chunk("Healclick", ns)
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
    M.fire(env, "ADDON_LOADED", "Healclick")
    M.fire(env, "PLAYER_LOGIN")
end

function M.command(env, text)
    env.SlashCmdList.HEALCLICK(text)
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

--- The row built for a unit.
function M.rowFor(ns, unit)
    return ns.Group.Rows()[unit]
end

--- A button's secure attributes, as a plain table.
function M.attrs(button)
    return button.attributes
end

return M
```

- [ ] **Step 5: Write the failing test**

Create `Healclick/tests/addon_spec.lua`:

```lua
local helpers = require("helpers")

local ONLY_CORE = { "Healclick.lua" }

describe("the database", function()
    it("applies defaults at login", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        helpers.login(ns, env)

        assertEqual(1, ns.db.version)
    end)

    it("lets a stored value win over a default", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        env.HealclickDB = { version = 99 }
        helpers.login(ns, env)

        assertEqual(99, ns.db.version)
    end)

    it("fills in a nested table added since the value was saved", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        ns.AddDefaults({ later = { added = "yes" } })
        env.HealclickDB = { version = 1 }
        helpers.login(ns, env)

        assertEqual("yes", ns.db.later.added)
    end)
end)

describe("commands", function()
    it("runs a registered command", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        local got
        ns.RegisterCommand("ping", "Ping", function(rest) got = rest end)
        helpers.login(ns, env)

        helpers.command(env, "ping there")
        assertEqual("there", got)
    end)

    it("shows the command list for a bare /hc, the way /fp and /url do", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        ns.RegisterCommand("ping", "Ping the thing", function() end)
        helpers.login(ns, env)

        helpers.command(env, "")
        assertMatch("Ping the thing", helpers.printed(env))
    end)

    it("says so for a command it does not know", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        helpers.login(ns, env)

        helpers.command(env, "wibble")
        assertMatch("Unknown command", helpers.printed(env))
    end)
end)

describe("the setting registry", function()
    it("keeps settings in declaration order", function()
        local ns = helpers.loadAddon(ONLY_CORE)
        ns.AddDefaults({ box = { first = true, second = 2 } })

        ns.RegisterSetting({ store = "box", key = "first", type = "checkbox", name = "First" })
        ns.RegisterSetting({ store = "box", key = "second", type = "slider", name = "Second", min = 1, max = 3 })

        assertEqual("First", ns.settings[1].name)
        assertEqual("Second", ns.settings[2].name)
    end)

    it("accepts a spell table, which is this addon's own control", function()
        local ns = helpers.loadAddon(ONLY_CORE)
        ns.AddDefaults({ box = { spells = {} } })

        local setting = ns.RegisterSetting({
            store = "box", key = "spells", type = "spelltable", name = "Spells", rows = 8,
        })

        assertEqual("spelltable", setting.type)
    end)

    it("refuses a setting with no default behind it", function()
        local ns = helpers.loadAddon(ONLY_CORE)

        -- A control wired to nothing renders fine and does nothing at all,
        -- which is the hardest kind of bug to see.
        assertErrors(function()
            ns.RegisterSetting({ store = "nowhere", key = "nothing", type = "checkbox", name = "No" })
        end)
    end)

    it("refuses a type it cannot render", function()
        local ns = helpers.loadAddon(ONLY_CORE)
        ns.AddDefaults({ box = { thing = 1 } })

        assertErrors(function()
            ns.RegisterSetting({ store = "box", key = "thing", type = "dial", name = "Dial" })
        end)
    end)
end)

describe("settings values", function()
    it("writes through and calls onChange", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        ns.AddDefaults({ box = { flag = false } })
        local seen
        local setting = ns.RegisterSetting({
            store = "box", key = "flag", type = "checkbox", name = "Flag",
            onChange = function(value) seen = value end,
        })
        helpers.login(ns, env)

        ns.SetSettingValue(setting, true)
        assertTrue(ns.db.box.flag)
        assertTrue(seen)
    end)

    it("stays quiet when the value has not changed", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        ns.AddDefaults({ box = { flag = false } })
        local calls = 0
        local setting = ns.RegisterSetting({
            store = "box", key = "flag", type = "checkbox", name = "Flag",
            onChange = function() calls = calls + 1 end,
        })
        helpers.login(ns, env)

        ns.SetSettingValue(setting, false)
        assertEqual(0, calls)
    end)
end)
```

- [ ] **Step 6: Run the test to verify it fails**

```powershell
.\run-tests.ps1 Healclick
```

Expected: FAIL — `Healclick.lua` does not exist, so the spec raises while loading.

- [ ] **Step 7: Write the namespace file**

Create `Healclick/Healclick.lua`:

```lua
local addonName, ns = ...

ns.PREFIX = "|cff66ccffHealclick|r"

-- Defaults are contributed by each file at load time, so every piece of config
-- lives next to the code that reads it and this file never learns the others.
local defaults = {
    version = 1,
}

--- Merge a defaults table into a saved table without clobbering stored values.
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

ns.applyDefaults = applyDefaults

--- Register additional defaults. Called at file load, before ADDON_LOADED.
function ns.AddDefaults(extra)
    applyDefaults(defaults, extra)
end

function ns.Print(message)
    print(string.format("%s %s", ns.PREFIX, message))
end

-- Settings registry. A file declares the config it owns, and Settings.lua
-- renders what it finds.
local settings = {}
ns.settings = settings

-- checkbox and slider are the shapes UrlCopy's panel already knows. spelltable
-- is this addon's own: one row per slot, holding a spell name.
local SETTING_TYPES = { checkbox = true, slider = true, spelltable = true }

function ns.RegisterSetting(definition)
    assert(type(definition) == "table", "RegisterSetting expects a table")

    local store, key = definition.store, definition.key
    assert(type(store) == "string" and store ~= "", "setting requires a store")
    assert(type(key) == "string" and key ~= "", "setting requires a key")
    assert(type(definition.name) == "string", "setting requires a name")
    assert(
        SETTING_TYPES[definition.type],
        "unknown setting type: " .. tostring(definition.type)
    )

    -- A setting with no default reads nil and writes somewhere nothing else
    -- looks, which shows up as a control that silently does nothing.
    assert(
        type(defaults[store]) == "table" and defaults[store][key] ~= nil,
        string.format("no default registered for %s.%s", store, key)
    )

    table.insert(settings, definition)
    return definition
end

function ns.SettingValue(setting)
    local store = ns.db and ns.db[setting.store]
    return store and store[setting.key]
end

function ns.SetSettingValue(setting, value)
    local store = ns.db and ns.db[setting.store]
    if not store or store[setting.key] == value then
        return
    end

    store[setting.key] = value
    if setting.onChange then
        setting.onChange(value)
    end
end

local function ensureDatabase()
    if type(HealclickDB) ~= "table" then
        HealclickDB = {}
    end

    applyDefaults(HealclickDB, defaults)
    ns.db = HealclickDB
end

ns.ensureDatabase = ensureDatabase

-- Slash commands. Each file registers its own, so a feature owns its commands
-- and its help text.
local commands = {}
ns.commands = commands

local helpLines = {}
ns.helpLines = helpLines

function ns.RegisterCommand(name, help, handler)
    commands[name] = { help = help, handler = handler }
end

function ns.RegisterHelpLine(line)
    table.insert(helpLines, line)
end

local function showHelp()
    ns.Print("Commands:")

    for _, line in ipairs(helpLines) do
        ns.Print(line)
    end

    local names = {}
    for name in pairs(commands) do
        table.insert(names, name)
    end
    table.sort(names)

    for _, name in ipairs(names) do
        ns.Print(string.format("/hc %s - %s", name, commands[name].help))
    end
end

ns.ShowHelp = showHelp

local function runCommand(msg)
    local input = msg and msg:match("^%s*(.-)%s*$") or ""

    -- A bare "/hc" lists the commands, the same as "/fp" and "/url" do. Three
    -- addons whose login lines sit together must not disagree about this.
    if input == "" or input == "help" then
        showHelp()
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
    showHelp()
end

SLASH_HEALCLICK1 = "/healclick"
SLASH_HEALCLICK2 = "/hc"
SlashCmdList.HEALCLICK = runCommand

-- Work to do once the player is in the world and the database exists.
local loginHandlers = {}

function ns.OnLogin(handler)
    table.insert(loginHandlers, handler)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ensureDatabase()
    elseif event == "PLAYER_LOGIN" then
        ensureDatabase()

        for _, handler in ipairs(loginHandlers) do
            handler()
        end

        ns.Print("Loaded. Type /hc for commands.")
    end
end)
```

- [ ] **Step 8: Run the tests to verify they pass**

```powershell
.\run-tests.ps1 Healclick
```

Expected: PASS, 12 tests.

- [ ] **Step 9: Add Healclick to the repo README**

In `README.md`, add a row to the addon table under UrlCopy's:

```markdown
| [Healclick](Healclick/) | A row of spell buttons beside every party member, so healing or dispelling someone is one click |
```

- [ ] **Step 10: Commit**

```bash
git add Healclick README.md
git commit -m "Add the Healclick skeleton and its test harness"
```

---

### Task 3: The spell slots

Pure data: how many buttons, what is in each. No frames, no game API beyond `GetSpellInfo`. This is the half of the addon that can be wrong on its own terms, so it is the half that tests properly.

**Files:**
- Create: `Healclick/Slots.lua`
- Test: `Healclick/tests/slots_spec.lua`

**Interfaces:**
- Consumes: `ns.AddDefaults`, `ns.db` (Task 2).
- Produces:
  - `ns.Slots.MAX` — 8. Buttons built per row regardless of how many are used.
  - `ns.Slots.Count()` → 1..MAX, clamped from `ns.db.bar.slots`
  - `ns.Slots.Spell(index)` → spell name or nil
  - `ns.Slots.Set(index, spellName)` → `ok, message`. **Always stores a non-empty name**; `message` is a warning when the client does not recognise it. An empty string clears the slot.
  - `ns.Slots.Seed(class)` — fills empty slots once, from `UnitClass("player")`
  - Defaults: `bar = { slots = 4, locked = false, selfBottom = false, spells = {} }`, `seeded = false`

**A deliberate departure from the spec, agreed before this plan was written.** The spec said an unrecognised spell name is "reported to the player, not stored". That is wrong: `GetSpellInfo` only knows spells the character has learned, so a level-5 Druid would have their own seeded defaults rejected — Regrowth is learned at 12, Remove Curse at 24. `Slots.Set` therefore stores the name and returns a warning alongside it. The spec has been amended to match.

- [ ] **Step 1: Write the failing test**

Create `Healclick/tests/slots_spec.lua`:

```lua
local helpers = require("helpers")

local FILES = { "Healclick.lua", "Slots.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

describe("the slot count", function()
    it("defaults to four", function()
        local ns = loggedIn()
        assertEqual(4, ns.Slots.Count())
    end)

    it("clamps above the maximum", function()
        local ns = loggedIn()
        ns.db.bar.slots = 99
        assertEqual(ns.Slots.MAX, ns.Slots.Count())
    end)

    it("clamps below one", function()
        local ns = loggedIn()
        ns.db.bar.slots = 0
        assertEqual(1, ns.Slots.Count())
    end)

    it("builds more buttons than it uses, so growing needs no new frame", function()
        -- A frame created at the wrong moment is a frame the client refuses.
        local ns = loggedIn()
        assertTrue(ns.Slots.MAX > ns.Slots.Count())
    end)
end)

describe("setting a spell", function()
    it("stores a spell the client knows", function()
        local ns = loggedIn()
        local ok = ns.Slots.Set(1, "Regrowth")

        assertTrue(ok)
        assertEqual("Regrowth", ns.Slots.Spell(1))
    end)

    it("stores a spell the client does not know, and warns", function()
        -- GetSpellInfo only knows spells this character has learned. A level 5
        -- Druid setting up Remove Curse for level 24 is being sensible, not
        -- making a typo, and refusing them would reject our own seeds.
        local ns = loggedIn()
        local ok, message = ns.Slots.Set(1, "Tranquility")

        assertTrue(ok, "stored anyway")
        assertEqual("Tranquility", ns.Slots.Spell(1))
        assertMatch("Tranquility", message, "but said so")
    end)

    it("trims surrounding space", function()
        local ns = loggedIn()
        ns.Slots.Set(1, "  Regrowth  ")

        assertEqual("Regrowth", ns.Slots.Spell(1))
    end)

    it("clears a slot given an empty string", function()
        local ns = loggedIn()
        ns.Slots.Set(1, "Regrowth")
        ns.Slots.Set(1, "")

        assertNil(ns.Slots.Spell(1))
    end)

    it("refuses a slot number outside the range", function()
        local ns = loggedIn()

        assertFalse((ns.Slots.Set(0, "Regrowth")))
        assertFalse((ns.Slots.Set(ns.Slots.MAX + 1, "Regrowth")))
    end)
end)

describe("seeding", function()
    it("fills empty slots for the class", function()
        local ns = loggedIn()
        ns.Slots.Seed("DRUID")

        assertEqual("Regrowth", ns.Slots.Spell(1))
        assertEqual("Rejuvenation", ns.Slots.Spell(2))
        assertEqual("Remove Curse", ns.Slots.Spell(3))
        assertEqual("Mark of the Wild", ns.Slots.Spell(4))
    end)

    it("leaves a slot the player already chose", function()
        local ns = loggedIn()
        ns.Slots.Set(1, "Healing Touch")
        ns.Slots.Seed("DRUID")

        assertEqual("Healing Touch", ns.Slots.Spell(1))
    end)

    it("does not refill a slot the player deliberately emptied", function()
        -- Seeding is a starting point, not a policy. Emptying slot 2 and
        -- logging in again must not put Rejuvenation back.
        local ns = loggedIn()
        ns.Slots.Seed("DRUID")
        ns.Slots.Set(2, "")
        ns.Slots.Seed("DRUID")

        assertNil(ns.Slots.Spell(2))
    end)

    it("does nothing for a class it has no set for", function()
        local ns = loggedIn()
        ns.Slots.Seed("WARLOCK")

        assertNil(ns.Slots.Spell(1))
    end)

    it("survives being asked with no class at all", function()
        local ns = loggedIn()
        ns.Slots.Seed(nil)

        assertNil(ns.Slots.Spell(1))
    end)
end)

describe("slot defaults", function()
    it("starts unlocked, with the player's own row on top", function()
        local ns = loggedIn()
        assertFalse(ns.db.bar.locked)
        assertFalse(ns.db.bar.selfBottom)
    end)
end)
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
.\run-tests.ps1 Healclick
```

Expected: FAIL — `Slots.lua` does not exist.

- [ ] **Step 3: Write Slots.lua**

Create `Healclick/Slots.lua`:

```lua
local addonName, ns = ...

-- The spell slots: how many buttons a row has, and what is in each. Nothing
-- here builds a frame or casts anything, which is what lets the decisions be
-- tested without a client.

local Slots = {}
ns.Slots = Slots

-- Every row builds this many buttons whatever the count says. Growing the bar
-- later must never need a frame created at a moment the client forbids one.
Slots.MAX = 8

-- A starting set per class, so a configuration that was never saved is still
-- usable. ForeverPanel seeds its chat keys for the same reason.
local SEED = {
    DRUID   = { "Regrowth", "Rejuvenation", "Remove Curse", "Mark of the Wild" },
    PRIEST  = { "Flash Heal", "Renew", "Dispel Magic", "Power Word: Fortitude" },
    PALADIN = { "Holy Light", "Flash of Light", "Cleanse", "Blessing of Might" },
    SHAMAN  = { "Healing Wave", "Lesser Healing Wave", "Cure Poison", "Lightning Shield" },
}

ns.AddDefaults({
    bar = {
        slots = 4,
        locked = false,
        -- Your own row: top by default, bottom if you prefer it there.
        selfBottom = false,
        spells = {},
    },
    seeded = false,
})

function Slots.Count()
    local count = tonumber(ns.db and ns.db.bar.slots) or 4
    count = math.floor(count)

    if count < 1 then
        return 1
    elseif count > Slots.MAX then
        return Slots.MAX
    end

    return count
end

function Slots.Spell(index)
    local spells = ns.db and ns.db.bar.spells
    local spell = spells and spells[index]

    if spell == "" then
        return nil
    end

    return spell
end

--- Put a spell in a slot. Returns ok, and a warning when the client does not
-- recognise the name.
--
-- The name is stored either way. GetSpellInfo only knows spells this character
-- has learned, so refusing an unknown one would reject a level 5 Druid setting
-- up the Remove Curse they get at 24 -- and would reject our own seeds.
function Slots.Set(index, spellName)
    if type(index) ~= "number" or index < 1 or index > Slots.MAX then
        return false, "no such slot"
    end

    spellName = type(spellName) == "string" and spellName:match("^%s*(.-)%s*$") or ""

    if spellName == "" then
        ns.db.bar.spells[index] = nil
        return true
    end

    ns.db.bar.spells[index] = spellName

    if GetSpellInfo and not GetSpellInfo(spellName) then
        return true, string.format(
            "%s is not a spell you know yet. Kept anyway.", spellName
        )
    end

    return true
end

--- Fill empty slots with a starting set, once ever.
-- Once is the whole point: a slot the player deliberately empties must stay
-- empty at the next login rather than being helpfully refilled.
function Slots.Seed(class)
    if ns.db.seeded then
        return
    end
    ns.db.seeded = true

    local seed = SEED[class or ""]
    if not seed then
        return
    end

    for index, spell in ipairs(seed) do
        if ns.db.bar.spells[index] == nil then
            ns.db.bar.spells[index] = spell
        end
    end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
.\run-tests.ps1 Healclick
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Healclick/Slots.lua Healclick/tests/slots_spec.lua
git commit -m "Hold the spell slots, and seed a starting set"
```

---

### Task 4: One unit's row

**Files:**
- Create: `Healclick/Row.lua`
- Test: `Healclick/tests/row_spec.lua`

**Interfaces:**
- Consumes: `ns.Slots.MAX`, `ns.Slots.Count`, `ns.Slots.Spell` (Task 3).
- Produces:
  - `ns.Row.Create(unit, parent)` → a row frame with `row.unit`, `row.name`, `row.health`, `row.buttons[1..Slots.MAX]`. Sets the row's own `unit` attribute so `Group` can hand it to `RegisterUnitWatch`.
  - `ns.Row.ApplySpells(row)` — writes each button's `spell` attribute, shows the configured ones, hides the rest. **Caller guarantees no combat.**
  - `ns.Row.Refresh(row)` — name, class colour, health, dim state. Safe in combat.
  - `ns.Row.HEIGHT`, `ns.Row.WIDTH` — for `Group`'s layout arithmetic.

- [ ] **Step 1: Write the failing test**

Create `Healclick/tests/row_spec.lua`:

```lua
local helpers = require("helpers")

local FILES = { "Healclick.lua", "Slots.lua", "Row.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

describe("building a row", function()
    it("builds every slot the maximum allows, not just the ones in use", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        assertEqual(ns.Slots.MAX, #row.buttons)
    end)

    it("makes every button a secure action button", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        assertEqual("SecureActionButtonTemplate", row.buttons[1].template)
    end)

    it("binds every button to the unit, once and for all", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party2", env.UIParent)

        for index = 1, ns.Slots.MAX do
            local attrs = helpers.attrs(row.buttons[index])
            assertEqual("spell", attrs.type, "button " .. index .. " casts a spell")
            assertEqual("party2", attrs.unit, "button " .. index .. " is bound to party2")
        end
    end)

    it("gives the row itself a unit attribute for RegisterUnitWatch", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party3", env.UIParent)

        assertEqual("party3", row:GetAttribute("unit"))
    end)

    it("starts with every button hidden, since no spell is applied yet", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        assertFalse(row.buttons[1]:IsShown())
    end)
end)

describe("applying spells", function()
    it("writes the spell a slot holds", function()
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Regrowth")
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)
        assertEqual("Regrowth", helpers.attrs(row.buttons[1]).spell)
    end)

    it("never rewrites the unit while doing so", function()
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Regrowth")
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)
        assertEqual("party1", helpers.attrs(row.buttons[1]).unit)
    end)

    it("shows only the configured number of buttons", function()
        local ns, env = loggedIn()
        ns.db.bar.slots = 2
        ns.Slots.Set(1, "Regrowth")
        ns.Slots.Set(2, "Rejuvenation")
        ns.Slots.Set(3, "Remove Curse")
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)
        assertTrue(row.buttons[1]:IsShown())
        assertTrue(row.buttons[2]:IsShown())
        assertFalse(row.buttons[3]:IsShown(), "slot 3 is past the count")
    end)

    it("hides an empty slot inside the count", function()
        -- A button that looks pressable and does nothing is the same failure
        -- as one wired to a spell that does not exist.
        local ns, env = loggedIn()
        ns.db.bar.slots = 3
        ns.Slots.Set(1, "Regrowth")
        ns.Slots.Set(3, "Remove Curse")
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)
        assertFalse(row.buttons[2]:IsShown())
    end)

    it("clears the spell attribute of a slot that was emptied", function()
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Regrowth")
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)

        ns.Slots.Set(1, "")
        ns.Row.ApplySpells(row)

        assertNil(helpers.attrs(row.buttons[1]).spell)
    end)
end)

describe("refreshing a row", function()
    it("shows the unit's name", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.Refresh(row)
        assertEqual("Borgir", row.name:GetText())
    end)

    it("scales the health bar to the unit's maximum", function()
        local ns, env = loggedIn()
        env.units.party1.health = 30
        env.units.party1.healthMax = 120
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.Refresh(row)
        local low, high = row.health:GetMinMaxValues()
        assertEqual(0, low)
        assertEqual(120, high)
        assertEqual(30, row.health:GetValue())
    end)

    it("colours the bar by class", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party2", env.UIParent)

        ns.Row.Refresh(row)
        assertTrue(row.health.barColor ~= nil, "a mage bar is a mage colour")
    end)

    it("leaves a full-strength row alone", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.Refresh(row)
        assertEqual(1, row:GetAlpha())
    end)
end)

describe("dimming a row you cannot usefully click", function()
    -- Clicking a heal on someone dead or out of range burns a global cooldown
    -- and returns nothing at all.

    it("dims a dead unit", function()
        local ns, env = loggedIn()
        env.units.party1.dead = true
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.Refresh(row)
        assertTrue(row:GetAlpha() < 1)
    end)

    it("dims an offline unit", function()
        local ns, env = loggedIn()
        env.units.party1.connected = false
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.Refresh(row)
        assertTrue(row:GetAlpha() < 1)
    end)

    it("dims a unit out of range", function()
        local ns, env = loggedIn()
        env.units.party1.inRange = false
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.Refresh(row)
        assertTrue(row:GetAlpha() < 1)
    end)

    it("brightens again when the unit comes back into range", function()
        local ns, env = loggedIn()
        env.units.party1.inRange = false
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.Refresh(row)

        env.units.party1.inRange = true
        ns.Row.Refresh(row)

        assertEqual(1, row:GetAlpha())
    end)

    it("survives a unit that is not there at all", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party4", env.UIParent)

        ns.Row.Refresh(row)
        assertEqual("", row.name:GetText())
    end)
end)
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
.\run-tests.ps1 Healclick
```

Expected: FAIL — `Row.lua` does not exist.

- [ ] **Step 3: Write Row.lua**

Create `Healclick/Row.lua`:

```lua
local addonName, ns = ...

-- One unit's row: a name, a health bar, and the secure buttons that cast on
-- that unit. The buttons are the only part the client treats as special, and
-- the only thing we ever do to them is write attributes.

local Row = {}
ns.Row = Row

local NAME_WIDTH = 70
local BAR_WIDTH = 120
local BUTTON_SIZE = 22
local BUTTON_GAP = 2
local PADDING = 4

Row.HEIGHT = BUTTON_SIZE + 2
Row.WIDTH = NAME_WIDTH + BAR_WIDTH + PADDING * 2
    + (BUTTON_SIZE + BUTTON_GAP) * ns.Slots.MAX

-- How far a row fades when clicking it would achieve nothing.
local DIM = 0.35

--- Build one unit's row. Called once per unit, at login, out of combat.
function Row.Create(unit, parent)
    local row = CreateFrame("Frame", "HealclickRow" .. unit, parent)
    row:SetSize(Row.WIDTH, Row.HEIGHT)
    row.unit = unit

    -- Blizzard decides whether this row is on screen, via RegisterUnitWatch,
    -- and it reads the unit from here. Group makes that call.
    row:SetAttribute("unit", unit)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", PADDING, 0)
    row.name:SetWidth(NAME_WIDTH)
    row.name:SetJustifyH("LEFT")

    row.health = CreateFrame("StatusBar", nil, row)
    row.health:SetPoint("LEFT", NAME_WIDTH + PADDING * 2, 0)
    row.health:SetSize(BAR_WIDTH, Row.HEIGHT - 6)
    row.health:SetMinMaxValues(0, 1)
    row.health:SetValue(1)

    row.buttons = {}

    for index = 1, ns.Slots.MAX do
        local button = CreateFrame(
            "Button",
            "HealclickButton" .. unit .. index,
            row,
            "SecureActionButtonTemplate"
        )
        button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        button:SetPoint(
            "LEFT",
            NAME_WIDTH + BAR_WIDTH + PADDING * 3 + (index - 1) * (BUTTON_SIZE + BUTTON_GAP),
            0
        )
        button:RegisterForClicks("AnyUp")

        -- The two attributes that are written once and never again. Blizzard
        -- will not let us re-point a secure button in combat, so we never try:
        -- a button can only ever cast on the row it sits in.
        button:SetAttribute("type", "spell")
        button:SetAttribute("unit", unit)

        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.label:SetPoint("CENTER")

        button:Hide()
        row.buttons[index] = button
    end

    return row
end

--- Write the spell attributes and show only the slots in use.
-- Every call here is blocked once the player is in combat, so the caller is
-- responsible for not being in any. Group.ApplyAll is that caller.
function Row.ApplySpells(row)
    local count = ns.Slots.Count()

    for index = 1, ns.Slots.MAX do
        local button = row.buttons[index]
        local spell = index <= count and ns.Slots.Spell(index) or nil

        if spell then
            button:SetAttribute("spell", spell)
            button.label:SetText(spell:sub(1, 2))
            button:Show()
        else
            -- An empty slot is hidden rather than shown and inert. A button
            -- that looks pressable and does nothing is the worse failure.
            button:SetAttribute("spell", nil)
            button.label:SetText("")
            button:Hide()
        end
    end
end

--- Name, colour, health and the dim state. Touches nothing secure, so this is
-- safe at any time, including mid-fight when it matters most.
function Row.Refresh(row)
    local unit = row.unit

    if not UnitExists(unit) then
        row.name:SetText("")
        return
    end

    row.name:SetText(UnitName(unit) or "")

    local _, class = UnitClass(unit)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then
        row.name:SetTextColor(color.r, color.g, color.b)
        row.health:SetStatusBarColor(color.r, color.g, color.b)
    end

    local health = UnitHealth(unit) or 0
    local healthMax = UnitHealthMax(unit) or 0
    row.health:SetMinMaxValues(0, healthMax > 0 and healthMax or 1)
    row.health:SetValue(health)

    -- Clicking a heal on someone dead, offline or out of range burns a global
    -- cooldown and gives nothing back. Fading the row is the cheapest way to
    -- stop the hand before it does that.
    local reachable = not UnitIsDeadOrGhost(unit)
        and UnitIsConnected(unit)
        and (UnitInRange(unit))

    row:SetAlpha(reachable and 1 or DIM)
end
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
.\run-tests.ps1 Healclick
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Healclick/Row.lua Healclick/tests/row_spec.lua
git commit -m "Build one unit's row and its secure buttons"
```

---

### Task 5: The group

**Files:**
- Create: `Healclick/Group.lua`
- Test: `Healclick/tests/group_spec.lua`

**Interfaces:**
- Consumes: `ns.Row.Create`, `ns.Row.Refresh`, `ns.Row.HEIGHT` (Task 4); `ns.db`, `ns.OnLogin`, `ns.RegisterCommand` (Task 2); `ns.Slots.Seed` (Task 3).
- Produces:
  - `ns.Group.Units()` → the five unit ids in display order
  - `ns.Group.Rows()` → `{ [unit] = row }`
  - `ns.Group.Build()` — anchor plus one row per unit, once
  - `ns.Group.Layout()` — stacks the rows in `Units()` order
  - `ns.Group.RefreshAll()`
  - `ns.Group.Anchor()` → the draggable frame
  - Commands: `lock`, `reset`
  - Defaults: `anchor = { point = "CENTER", x = 0, y = -200 }`

The combat queue is **not** in this task — `Group.ApplyAll` arrives in Task 6.

- [ ] **Step 1: Write the failing test**

Create `Healclick/tests/group_spec.lua`:

```lua
local helpers = require("helpers")

local FILES = { "Healclick.lua", "Slots.lua", "Row.lua", "Group.lua" }

local function loggedIn(before)
    local ns, env = helpers.loadAddon(FILES)
    if before then before(ns, env) end
    helpers.login(ns, env)
    return ns, env
end

describe("the order of the rows", function()
    it("puts you first and the party in party order", function()
        local ns = loggedIn()
        local units = ns.Group.Units()

        assertEqual(5, #units)
        assertEqual("player", units[1])
        assertEqual("party1", units[2])
        assertEqual("party4", units[5])
    end)

    it("puts you last when you ask for it", function()
        local ns = loggedIn(function(_, env)
            env.HealclickDB = { bar = { selfBottom = true } }
        end)
        local units = ns.Group.Units()

        assertEqual("party1", units[1])
        assertEqual("player", units[5])
    end)

    it("keeps the party in party order either way", function()
        local ns = loggedIn(function(_, env)
            env.HealclickDB = { bar = { selfBottom = true } }
        end)
        local units = ns.Group.Units()

        assertEqual("party1", units[1])
        assertEqual("party2", units[2])
        assertEqual("party3", units[3])
        assertEqual("party4", units[4])
    end)
end)

describe("building the group", function()
    it("builds a row for every unit", function()
        local ns = loggedIn()

        for _, unit in ipairs(ns.Group.Units()) do
            assertTrue(helpers.rowFor(ns, unit) ~= nil, unit .. " has a row")
        end
    end)

    it("hands every row to RegisterUnitWatch", function()
        -- Showing and hiding a frame holding secure buttons is blocked in
        -- combat, which is exactly when the party changes. Blizzard's own
        -- watcher runs in the secure environment, so it is allowed to.
        local ns, env = loggedIn()

        assertEqual(5, #env.__watched)
        for _, row in ipairs(env.__watched) do
            assertTrue(row.unitWatched)
        end
    end)

    it("builds once, however often it is asked", function()
        local ns, env = loggedIn()
        local before = #env.__watched

        ns.Group.Build()
        assertEqual(before, #env.__watched, "no second set of rows")
    end)

    it("seeds the spells from the player's class", function()
        local ns = loggedIn()
        assertEqual("Regrowth", ns.Slots.Spell(1), "the stub player is a druid")
    end)
end)

describe("layout", function()
    it("stacks the rows downward from the anchor", function()
        local ns = loggedIn()
        ns.Group.Layout()

        local first = helpers.rowFor(ns, "player")
        local second = helpers.rowFor(ns, "party1")

        local _, _, _, _, firstY = first:GetPoint(1)
        local _, _, _, _, secondY = second:GetPoint(1)

        assertTrue(secondY < firstY, "party1 sits below you")
    end)

    it("re-stacks in the new order when you move to the bottom", function()
        local ns = loggedIn()
        ns.db.bar.selfBottom = true
        ns.Group.Layout()

        local player = helpers.rowFor(ns, "player")
        local party1 = helpers.rowFor(ns, "party1")

        local _, _, _, _, playerY = player:GetPoint(1)
        local _, _, _, _, party1Y = party1:GetPoint(1)

        assertTrue(playerY < party1Y, "you sit below party1 now")
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

        local anchor = ns.Group.Anchor()
        anchor.scripts.OnDragStart(anchor)

        assertFalse(anchor.moving == true, "a locked frame stays put")
    end)

    it("moves while unlocked", function()
        local ns = loggedIn()
        ns.db.bar.locked = false

        local anchor = ns.Group.Anchor()
        anchor.scripts.OnDragStart(anchor)

        assertTrue(anchor.moving)
    end)

    it("remembers where it was dropped", function()
        local ns = loggedIn()
        local anchor = ns.Group.Anchor()

        -- No nils in the middle: GetPoint unpacks this table, and a hole makes
        -- the length operator unreliable.
        anchor.points = { { "TOPLEFT", "UIParent", "TOPLEFT", 120, -40 } }
        anchor.scripts.OnDragStop(anchor)

        assertEqual("TOPLEFT", ns.db.anchor.point)
        assertEqual(120, ns.db.anchor.x)
        assertEqual(-40, ns.db.anchor.y)
    end)

    it("goes back to the middle on /hc reset", function()
        local ns, env = loggedIn()
        ns.db.anchor.point, ns.db.anchor.x, ns.db.anchor.y = "TOPLEFT", 120, -40

        helpers.command(env, "reset")

        assertEqual("CENTER", ns.db.anchor.point)
        assertEqual(0, ns.db.anchor.x)
    end)

    it("toggles the lock on /hc lock", function()
        local ns, env = loggedIn()
        assertFalse(ns.db.bar.locked)

        helpers.command(env, "lock")
        assertTrue(ns.db.bar.locked)
    end)
end)

describe("keeping the rows current", function()
    it("refreshes every row on demand", function()
        local ns, env = loggedIn()
        env.units.party1.health = 12

        ns.Group.RefreshAll()
        assertEqual(12, helpers.rowFor(ns, "party1").health:GetValue())
    end)

    it("polls for range, because the game fires no event for it", function()
        local ns, env = loggedIn()
        env.units.party1.inRange = false

        env.__tick()
        assertTrue(helpers.rowFor(ns, "party1"):GetAlpha() < 1)
    end)

    it("refreshes when the roster changes", function()
        local ns, env = loggedIn()
        env.units.party1.name = "Someone Else"

        helpers.fire(env, "GROUP_ROSTER_UPDATE")
        assertEqual("Someone Else", helpers.rowFor(ns, "party1").name:GetText())
    end)

    it("refreshes the right row when its health changes", function()
        local ns, env = loggedIn()
        env.units.party2.health = 7

        helpers.fire(env, "UNIT_HEALTH", "party2")
        assertEqual(7, helpers.rowFor(ns, "party2").health:GetValue())
    end)
end)
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
.\run-tests.ps1 Healclick
```

Expected: FAIL — `Group.lua` does not exist.

- [ ] **Step 3: Write Group.lua**

Create `Healclick/Group.lua`:

```lua
local addonName, ns = ...

-- The five rows, their order, and the frame you drag to put them somewhere.

local Group = {}
ns.Group = Group

local PARTY = { "party1", "party2", "party3", "party4" }
local ROW_GAP = 2

-- Range has no event. Five times a second is fast enough to be useful and slow
-- enough to cost nothing; it is the only polling in the addon.
local RANGE_INTERVAL = 0.2

local DEFAULT_ANCHOR = { point = "CENTER", x = 0, y = -200 }

ns.AddDefaults({
    anchor = {
        point = DEFAULT_ANCHOR.point,
        x = DEFAULT_ANCHOR.x,
        y = DEFAULT_ANCHOR.y,
    },
})

local anchor
local rows = {}

--- The five units in display order. A function rather than a constant,
-- because where your own row sits is the player's choice.
function Group.Units()
    local units = {}

    if not (ns.db and ns.db.bar.selfBottom) then
        units[#units + 1] = "player"
    end

    for _, unit in ipairs(PARTY) do
        units[#units + 1] = unit
    end

    if ns.db and ns.db.bar.selfBottom then
        units[#units + 1] = "player"
    end

    return units
end

function Group.Rows()
    return rows
end

function Group.Anchor()
    return anchor
end

local function createAnchor()
    anchor = CreateFrame("Frame", "HealclickAnchor", UIParent)
    anchor:SetSize(ns.Row.WIDTH, 1)
    anchor:SetPoint(ns.db.anchor.point, ns.db.anchor.x, ns.db.anchor.y)
    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")

    anchor:SetScript("OnDragStart", function(self)
        if not ns.db.bar.locked then
            self:StartMoving()
        end
    end)

    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        ns.db.anchor.point = point or DEFAULT_ANCHOR.point
        ns.db.anchor.x = x or 0
        ns.db.anchor.y = y or 0
    end)
end

--- Build the anchor and one row per unit. Once, at login, out of combat.
function Group.Build()
    if anchor then
        return
    end

    createAnchor()

    -- Every unit gets a row, including ones nobody is standing in. They are
    -- built now because they cannot be built later: creating a frame with
    -- secure buttons is one more thing the client refuses mid-fight.
    for _, unit in ipairs(Group.Units()) do
        local row = ns.Row.Create(unit, anchor)
        rows[unit] = row

        if RegisterUnitWatch then
            RegisterUnitWatch(row)
        end
    end

    Group.Layout()
end

--- Stack the rows under the anchor, in the configured order.
function Group.Layout()
    if not anchor then
        return
    end

    local y = 0

    for _, unit in ipairs(Group.Units()) do
        local row = rows[unit]
        if row then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, y)
            y = y - (ns.Row.HEIGHT + ROW_GAP)
        end
    end
end

function Group.RefreshAll()
    for _, row in pairs(rows) do
        ns.Row.Refresh(row)
    end
end

local function refreshUnit(unit)
    local row = rows[unit]
    if row then
        ns.Row.Refresh(row)
    end
end

ns.RegisterCommand("lock", "Stop the frame being dragged", function()
    ns.db.bar.locked = not ns.db.bar.locked
    ns.Print(ns.db.bar.locked and "Frame locked." or "Frame unlocked.")
end)

ns.RegisterCommand("reset", "Put the frame back in the middle", function()
    ns.db.anchor.point = DEFAULT_ANCHOR.point
    ns.db.anchor.x = DEFAULT_ANCHOR.x
    ns.db.anchor.y = DEFAULT_ANCHOR.y

    if anchor then
        anchor:ClearAllPoints()
        anchor:SetPoint(ns.db.anchor.point, ns.db.anchor.x, ns.db.anchor.y)
    end

    ns.Print("Frame back in the middle.")
end)

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UNIT_HEALTH")
watcher:RegisterEvent("UNIT_MAXHEALTH")
watcher:RegisterEvent("UNIT_CONNECTION")
watcher:RegisterEvent("PLAYER_FLAGS_CHANGED")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")

watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        -- Names and classes change wholesale, so no single row is enough.
        Group.RefreshAll()
    elseif unit then
        refreshUnit(unit)
    end
end)

ns.OnLogin(function()
    local _, class = UnitClass("player")
    ns.Slots.Seed(class)

    Group.Build()
    Group.RefreshAll()

    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(RANGE_INTERVAL, Group.RefreshAll)
    end
end)
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
.\run-tests.ps1 Healclick
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Healclick/Group.lua Healclick/tests/group_spec.lua
git commit -m "Lay out the five rows and keep them current"
```

---

### Task 6: The combat queue

The subtlest part of the addon and the one a review should look hardest at. Everything secure waits for combat to end.

**Files:**
- Modify: `Healclick/Group.lua` (append; and call `ApplyAll` from the login handler)
- Test: `Healclick/tests/combat_spec.lua`

**Interfaces:**
- Consumes: `ns.Row.ApplySpells` (Task 4); `Group.Layout`, `Group.Rows` (Task 5).
- Produces:
  - `ns.Group.ApplyAll()` → true when applied, false when held for later
  - `ns.Group.Pending()` → whether a change is waiting

- [ ] **Step 1: Write the failing test**

Create `Healclick/tests/combat_spec.lua`:

```lua
local helpers = require("helpers")

local FILES = { "Healclick.lua", "Slots.lua", "Row.lua", "Group.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

describe("applying out of combat", function()
    it("writes the spells", function()
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Regrowth")

        assertTrue(ns.Group.ApplyAll())
        assertEqual("Regrowth", helpers.attrs(helpers.rowFor(ns, "party1").buttons[1]).spell)
    end)

    it("leaves nothing pending", function()
        local ns = loggedIn()
        ns.Group.ApplyAll()

        assertFalse(ns.Group.Pending())
    end)
end)

describe("applying in combat", function()
    it("refuses, and says so by returning false", function()
        local ns, env = loggedIn()
        env.__setCombat(true)

        assertFalse(ns.Group.ApplyAll())
    end)

    it("writes nothing at all", function()
        -- The client blocks this, not us. Attempting it and being refused is
        -- an error in the player's face, so we do not attempt it.
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Regrowth")
        ns.Group.ApplyAll()

        env.__setCombat(true)
        ns.Slots.Set(1, "Rejuvenation")
        ns.Group.ApplyAll()

        assertEqual(
            "Regrowth",
            helpers.attrs(helpers.rowFor(ns, "party1").buttons[1]).spell,
            "still the old spell"
        )
    end)

    it("holds the change", function()
        local ns, env = loggedIn()
        env.__setCombat(true)
        ns.Group.ApplyAll()

        assertTrue(ns.Group.Pending())
    end)

    it("applies it the moment combat ends", function()
        local ns, env = loggedIn()
        env.__setCombat(true)
        ns.Slots.Set(1, "Rejuvenation")
        ns.Group.ApplyAll()

        env.__setCombat(false)

        assertEqual(
            "Rejuvenation",
            helpers.attrs(helpers.rowFor(ns, "party1").buttons[1]).spell
        )
        assertFalse(ns.Group.Pending())
    end)

    it("does nothing when combat ends with nothing waiting", function()
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Regrowth")
        ns.Group.ApplyAll()

        env.__setCombat(true)
        env.__setCombat(false)

        assertFalse(ns.Group.Pending())
    end)
end)

describe("what stays safe in combat", function()
    it("still refreshes health, which touches nothing secure", function()
        local ns, env = loggedIn()
        env.__setCombat(true)
        env.units.party1.health = 9

        ns.Group.RefreshAll()
        assertEqual(9, helpers.rowFor(ns, "party1").health:GetValue())
    end)

    it("still dims a unit that goes out of range mid-fight", function()
        local ns, env = loggedIn()
        env.__setCombat(true)
        env.units.party1.inRange = false

        env.__tick()
        assertTrue(helpers.rowFor(ns, "party1"):GetAlpha() < 1)
    end)
end)

describe("re-ordering, which moves secure buttons", function()
    it("waits for combat to end like everything else secure", function()
        local ns, env = loggedIn()
        ns.Group.ApplyAll()

        env.__setCombat(true)
        ns.db.bar.selfBottom = true
        ns.Group.ApplyAll()

        env.__setCombat(false)

        local player = helpers.rowFor(ns, "player")
        local party1 = helpers.rowFor(ns, "party1")
        local _, _, _, _, playerY = player:GetPoint(1)
        local _, _, _, _, party1Y = party1:GetPoint(1)

        assertTrue(playerY < party1Y, "you moved to the bottom once the fight ended")
    end)
end)
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
.\run-tests.ps1 Healclick
```

Expected: FAIL — `ns.Group.ApplyAll` is nil.

- [ ] **Step 3: Append the queue to Group.lua**

Add to the end of `Healclick/Group.lua`, before the `ns.OnLogin` block:

```lua
-- Nothing secure may be written in combat: not a spell attribute, not showing
-- or hiding a button, not moving a row, because moving a row moves the secure
-- buttons inside it. Rather than attempt it and put an error in the player's
-- face, hold the change and do it the moment the fight ends. ForeverPanel's
-- ChatKeys.Apply holds its bindings the same way.
local pending = false

function Group.Pending()
    return pending
end

--- Write every row's spells and re-stack the rows.
-- Returns true when it happened, false when it was held for later.
function Group.ApplyAll()
    if not anchor then
        return false
    end

    if InCombatLockdown and InCombatLockdown() then
        pending = true
        return false
    end

    pending = false
    Group.Layout()

    for _, row in pairs(rows) do
        ns.Row.ApplySpells(row)
    end

    return true
end

local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:SetScript("OnEvent", function()
    if pending then
        Group.ApplyAll()
    end
end)
```

- [ ] **Step 4: Apply on login**

In `Healclick/Group.lua`'s `ns.OnLogin` block, add `Group.ApplyAll()` after `Group.Build()`. The block becomes:

```lua
ns.OnLogin(function()
    local _, class = UnitClass("player")
    ns.Slots.Seed(class)

    Group.Build()
    Group.ApplyAll()
    Group.RefreshAll()

    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(RANGE_INTERVAL, Group.RefreshAll)
    end
end)
```

- [ ] **Step 5: Run the tests to verify they pass**

```powershell
.\run-tests.ps1 Healclick
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Healclick/Group.lua Healclick/tests/combat_spec.lua
git commit -m "Hold every secure change until the fight is over"
```

---

### Task 7: The settings panel

**Files:**
- Create: `Healclick/Settings.lua`
- Modify: `Healclick/Slots.lua` (append the setting declarations)
- Test: `Healclick/tests/settings_spec.lua`

**Interfaces:**
- Consumes: `ns.settings`, `ns.RegisterSetting`, `ns.SettingValue`, `ns.SetSettingValue`, `ns.RegisterCommand`, `ns.OnLogin` (Task 2); `ns.Slots.Set`, `ns.Slots.Spell`, `ns.Slots.MAX` (Task 3); `ns.Group.ApplyAll` (Task 6).
- Produces:
  - `ns.SettingsPanel.EnsureBuilt()`, `ns.SettingsPanel.Refresh()`, `ns.SettingsPanel.controls`
  - `ns.OpenSettings()`, and the `settings` command

- [ ] **Step 1: Write the failing test**

Create `Healclick/tests/settings_spec.lua`:

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

        assertTrue(controlFor(ns, "bar", "slots") ~= nil, "the count")
        assertTrue(controlFor(ns, "bar", "selfBottom") ~= nil, "where your row sits")
        assertTrue(controlFor(ns, "bar", "spells") ~= nil, "the spells")
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

    it("opens from /hc settings", function()
        local ns, env = loggedIn()
        helpers.command(env, "settings")

        assertEqual("category-id", env.__openedCategory)
    end)
end)

describe("the slot count slider", function()
    it("writes through to the database", function()
        local ns = loggedIn()
        controlFor(ns, "bar", "slots").widget:SetValue(6)

        assertEqual(6, ns.db.bar.slots)
    end)

    it("applies the change to the rows", function()
        local ns = loggedIn()
        ns.Slots.Set(6, "Regrowth")

        controlFor(ns, "bar", "slots").widget:SetValue(6)

        assertTrue(helpers.rowFor(ns, "party1").buttons[6]:IsShown())
    end)
end)

describe("the spell table", function()
    it("has a row for every slot the maximum allows", function()
        local ns = loggedIn()
        assertEqual(ns.Slots.MAX, #controlFor(ns, "bar", "spells").boxes)
    end)

    it("stores what is typed into a row", function()
        local ns = loggedIn()
        local boxes = controlFor(ns, "bar", "spells").boxes

        boxes[2]:SetText("Rejuvenation")
        boxes[2].scripts.OnEnterPressed(boxes[2])

        assertEqual("Rejuvenation", ns.Slots.Spell(2))
    end)

    it("keeps a spell the character has not learned, and says so", function()
        local ns, env = loggedIn()
        local boxes = controlFor(ns, "bar", "spells").boxes

        boxes[3]:SetText("Tranquility")
        boxes[3].scripts.OnEnterPressed(boxes[3])

        assertEqual("Tranquility", ns.Slots.Spell(3))
        assertMatch("Tranquility", helpers.printed(env))
    end)

    it("shows what is already configured when it refreshes", function()
        local ns = loggedIn()
        ns.Slots.Set(4, "Regrowth")

        ns.SettingsPanel.Refresh()
        assertEqual("Regrowth", controlFor(ns, "bar", "spells").boxes[4]:GetText())
    end)
end)
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
.\run-tests.ps1 Healclick
```

Expected: FAIL — `Settings.lua` does not exist, so `helpers.loadAddon()` with the full list raises.

- [ ] **Step 3: Declare the settings in Slots.lua**

Add to the end of `Healclick/Slots.lua`. They live here, next to the code that reads them, so `Settings.lua` never needs editing when one is added:

```lua
-- Declared next to the code that reads them. Settings.lua renders whatever has
-- been declared, so adding one here needs no edit there.
--
-- Every onChange routes through Group.ApplyAll rather than writing attributes
-- directly, because that is the one place that knows to wait for combat.
ns.RegisterSetting({
    store = "bar",
    key = "slots",
    type = "slider",
    name = "Buttons per player",
    min = 1,
    max = Slots.MAX,
    step = 1,
    onChange = function()
        if ns.Group then ns.Group.ApplyAll() end
    end,
})

ns.RegisterSetting({
    store = "bar",
    key = "selfBottom",
    type = "checkbox",
    name = "Put my row at the bottom",
    tooltip = "Whether you sit above the party or below it.",
    onChange = function()
        if ns.Group then ns.Group.ApplyAll() end
    end,
})

ns.RegisterSetting({
    store = "bar",
    key = "spells",
    type = "spelltable",
    name = "Spells",
    rows = Slots.MAX,
    onChange = function()
        if ns.Group then ns.Group.ApplyAll() end
    end,
})

ns.RegisterSetting({
    store = "bar",
    key = "locked",
    type = "checkbox",
    name = "Lock the frame",
    tooltip = "Stops the bar being dragged around by accident.",
})
```

- [ ] **Step 4: Write Settings.lua**

Create `Healclick/Settings.lua`:

```lua
local addonName, ns = ...

-- The settings panel. Everything on it comes from ns.RegisterSetting, so this
-- file never needs editing when a setting is added: it renders whatever has
-- been declared, in declaration order.

local PADDING = 16
local ROW_HEIGHT = 30
local SLIDER_EXTRA = 24
local BOX_HEIGHT = 24
local PANEL_WIDTH = 400

local Panel = {}
ns.SettingsPanel = Panel
Panel.controls = {}

local panel, category, built

local function addCheckbox(setting, y)
    local button = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", PADDING, y)

    -- The label belongs to the template on some clients and not others, so
    -- write our own rather than reaching for button.Text and finding nil.
    local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", button, "RIGHT", 4, 0)
    label:SetText(setting.name)

    button:SetScript("OnClick", function(self)
        ns.SetSettingValue(setting, self:GetChecked() and true or false)
    end)

    return {
        setting = setting,
        widget = button,
        Refresh = function()
            button:SetChecked(ns.SettingValue(setting) and true or false)
        end,
    }
end

local function addSlider(setting, y)
    local slider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", PADDING, y - SLIDER_EXTRA)
    slider:SetMinMaxValues(setting.min, setting.max)
    slider:SetValueStep(setting.step or 1)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(200)

    -- The template labels its ends "Low" and "High", which says nothing about
    -- the range. Show the actual numbers where the template exposes them.
    if slider.Low and slider.Low.SetText then
        slider.Low:SetText(tostring(setting.min))
    end
    if slider.High and slider.High.SetText then
        slider.High:SetText(tostring(setting.max))
    end

    local label = slider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 4)

    local function relabel(value)
        label:SetText(string.format("%s: %d", setting.name, value or 0))
    end

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        relabel(value)
        ns.SetSettingValue(setting, value)
    end)

    return {
        setting = setting,
        widget = slider,
        Refresh = function()
            local value = ns.SettingValue(setting)
            slider:SetValue(value)
            relabel(value)
        end,
    }
end

--- One edit box per slot. Typing a name and pressing Enter stores it.
-- The store is Slots.Set rather than SetSettingValue, because a slot is one
-- entry inside a table rather than a value of its own, and because Set is
-- where the "you have not learned that yet" warning comes from.
local function addSpellTable(setting, y)
    local rows = setting.rows or 8
    local boxes = {}

    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", PADDING, y)
    heading:SetText(setting.name)

    for index = 1, rows do
        local top = y - ROW_HEIGHT - (index - 1) * BOX_HEIGHT

        local number = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        number:SetPoint("TOPLEFT", PADDING, top - 4)
        number:SetText(tostring(index))

        local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        box:SetPoint("TOPLEFT", PADDING + 20, top)
        box:SetSize(180, BOX_HEIGHT - 4)
        box:SetAutoFocus(false)

        local function store()
            local ok, message = ns.Slots.Set(index, box:GetText())
            if not ok then
                ns.Print(message or "That slot does not exist.")
            elseif message then
                ns.Print(message)
            end

            box:ClearFocus()
            if setting.onChange then
                setting.onChange()
            end
        end

        box:SetScript("OnEnterPressed", store)
        box:SetScript("OnEditFocusLost", store)
        box:SetScript("OnEscapePressed", function()
            box:SetText(ns.Slots.Spell(index) or "")
            box:ClearFocus()
        end)

        boxes[index] = box
    end

    return {
        setting = setting,
        widget = boxes[1],
        boxes = boxes,
        height = ROW_HEIGHT + rows * BOX_HEIGHT,
        Refresh = function()
            for index = 1, rows do
                boxes[index]:SetText(ns.Slots.Spell(index) or "")
            end
        end,
    }
end

function Panel.Refresh()
    for _, control in ipairs(Panel.controls) do
        control.Refresh()
    end
end

local function ensureBuilt()
    if built or not panel then
        return
    end
    built = true

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PADDING, -PADDING)
    title:SetText("Healclick")

    -- From the addon's own metadata, not a constant here, which would drift
    -- from the .toc the first time either is bumped without the other.
    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -PADDING - ROW_HEIGHT)
    hint:SetWidth(PANEL_WIDTH - PADDING * 2)
    hint:SetJustifyH("LEFT")
    hint:SetText(
        "Changes take effect out of combat. Anything you change mid-fight is "
        .. "held until it ends, because the game will not let an addon "
        .. "re-point a spell button while you are fighting."
    )

    local y = -PADDING - ROW_HEIGHT * 2

    for _, setting in ipairs(ns.settings) do
        local control
        if setting.type == "slider" then
            control = addSlider(setting, y)
            y = y - ROW_HEIGHT - SLIDER_EXTRA
        elseif setting.type == "spelltable" then
            control = addSpellTable(setting, y)
            y = y - control.height
        else
            control = addCheckbox(setting, y)
            y = y - ROW_HEIGHT
        end

        table.insert(Panel.controls, control)
    end

    Panel.Refresh()
end

Panel.EnsureBuilt = ensureBuilt

--- Claim a place in the game's options, without building anything yet.
local function register()
    panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel.name = "Healclick"
    Panel.panel = panel

    panel:SetScript("OnShow", function()
        ensureBuilt()
        Panel.Refresh()
    end)

    -- A canvas category holds widgets we own, which avoids
    -- Settings.RegisterAddOnSetting: its argument list changed in 11.0 and a
    -- wrong guess there registers nothing and fails silently.
    category = Settings.RegisterCanvasLayoutCategory(panel, "Healclick")
    Settings.RegisterAddOnCategory(category)
end

-- Whether the panel on screen was opened from our command rather than through
-- the game menu. Decides where closing it should leave the player.
local openedByUs = false
local suppressGameMenu = false
local closeHooked = false

local function dismissGameMenu(frame)
    suppressGameMenu = false
    if HideUIPanel then
        HideUIPanel(frame)
    else
        frame:Hide()
    end
end

local function watchForClose()
    if closeHooked or not SettingsPanel or not SettingsPanel.HookScript then
        return
    end
    closeHooked = true

    SettingsPanel:HookScript("OnHide", function()
        -- Opening the panel from a command leaves the client queued to fall
        -- back to the game menu, which is not where the player came from.
        if not openedByUs then
            return
        end
        openedByUs = false
        suppressGameMenu = true

        C_Timer.After(0, function()
            if suppressGameMenu then
                if GameMenuFrame and GameMenuFrame:IsShown() then
                    dismissGameMenu(GameMenuFrame)
                end
                suppressGameMenu = false
            end
        end)
    end)

    if GameMenuFrame and GameMenuFrame.HookScript then
        GameMenuFrame:HookScript("OnShow", function(self)
            if suppressGameMenu then
                dismissGameMenu(self)
            end
        end)
    end
end

function ns.OpenSettings()
    if not category then
        ns.Print("This client has no settings panel. Use /hc for commands.")
        return
    end

    watchForClose()
    openedByUs = true
    ensureBuilt()

    Settings.OpenToCategory(category:GetID())
    Panel.Refresh()
end

ns.RegisterCommand("settings", "Open the settings panel", function()
    ns.OpenSettings()
end)

ns.OnLogin(function()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        register()
    else
        ns.Print("This client has no settings panel API. Use /hc instead.")
    end
end)
```

- [ ] **Step 5: Run the tests to verify they pass**

```powershell
.\run-tests.ps1 Healclick
```

Expected: PASS, every suite.

- [ ] **Step 6: Commit**

```bash
git add Healclick/Settings.lua Healclick/Slots.lua Healclick/tests/settings_spec.lua
git commit -m "Add the Healclick settings panel"
```

---

### Task 8: README, and the package

**Files:**
- Create: `Healclick/README.md`
- Verify: `package.ps1` builds `dist/Healclick-0.1.0.zip`

- [ ] **Step 1: Write the addon README**

Create `Healclick/README.md`:

````markdown
# Healclick (World of Warcraft AddOn)

A row of spell buttons beside every member of your party, so healing,
dispelling or buffing someone is one click on a button that already knows who
it is for.

Blizzard's party frames make you target first and cast second. Healclick
removes the targeting step.

```
 (o) Skyler    ████████░░   [Re][Rj][Re][Ma]
 (o) Borgir    ████░░░░░░   [Re][Rj][Re][Ma]
 (o) Nimue     ██████░░░░   [Re][Rj][Re][Ma]
```

A slot holds any spell you can cast on a friendly unit, so a dispel is not a
special case: Remove Curse, Cleanse and Abolish Poison go in a slot exactly
like Regrowth does. So do buffs — Thorns, Mark of the Wild.

A row dims when the person is dead, offline, or out of range, because clicking
a heal on them burns a global cooldown and gives you nothing back.

## What it cannot do, and why

**Addon code cannot cast a spell in this game.** Casting on a unit is
protected: the only route is one of Blizzard's secure buttons carrying "cast
*this* on *that unit*", which **you** click. Healclick sets those attributes;
the game does the rest.

Three consequences you will notice:

- **Changes take effect out of combat.** Editing a spell, changing the number
  of buttons, or moving your own row to the bottom is held until the fight
  ends. The game refuses those changes mid-fight, so Healclick waits rather
  than putting an error on your screen.
- **A button can only ever cast on the person whose row it sits in.** Its unit
  is fixed when the row is built and never changes.
- **Whether a row is on screen is Blizzard's decision, not ours** — the game's
  own `RegisterUnitWatch` handles it, which is why a party change mid-fight
  works at all.

## Install

1. Copy this folder into your client's `Interface/AddOns` as `Healclick`, so
   the result is `.../Interface/AddOns/Healclick/Healclick.toc`.
2. Restart the client and enable Healclick from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 Healclick -Install

See the [repo README](../README.md) for packaging and test commands.

Built against Classic Era 1.15.x (`11509`) and the 1.60.x Classic beta
(`16001`).

## Commands

`/healclick` or the short `/hc`:

- `/hc` - Show the command list
- `/hc settings` - Open the settings panel
- `/hc lock` - Stop the frame being dragged
- `/hc reset` - Put the frame back in the middle

## Settings

| Setting | Does |
|---|---|
| Buttons per player | How many slots each row shows, 1 to 8 |
| Put my row at the bottom | Whether you sit above the party or below it |
| Spells | One row per slot; type the spell's name |
| Lock the frame | Stops the bar being dragged by accident |

A spell you have not learned yet is kept, not rejected — setting up the Remove
Curse you get at level 24 is sensible, not a typo. Healclick says so once and
keeps it.

Slots are seeded with a starting set for your class the first time you log in.
A slot you deliberately empty stays empty.

## Party only

Raid is not supported and is not a setting you are missing. Forty people with
a five-slot bar each is 200 buttons — taller than a screen stacked, wider than
one in columns. It needs its own layout, decided by someone who is raiding.

## Tests

The slot logic, the row building, the layout and the combat queue are covered
by unit tests that run outside the game against a stubbed WoW API
(`tests/wow_stub.lua`).

From the repo root:

```powershell
.\run-tests.ps1 Healclick
```

Or a single suite by hand, from this folder:

```
lua tests/runner.lua tests/slots_spec.lua
```

What the tests prove is that Healclick asks for the right thing: that party2's
third button carries `spell="Remove Curse"` and `unit="party2"`. Whether the
client honours it is something only the client can answer.
````

- [ ] **Step 2: Verify the package builds**

```powershell
.\package.ps1 Healclick
```

Expected: `Packaged 7 files -> ...\dist\Healclick-0.1.0.zip` — the `.toc`, five Lua files and the README.

- [ ] **Step 3: Run the whole repo's tests**

```powershell
.\run-tests.ps1
```

Expected: `ForeverPanel`, `UrlCopy` and `Healclick` all pass. The first two must be untouched.

- [ ] **Step 4: Commit**

```bash
git add Healclick/README.md
git commit -m "Document Healclick"
```

---

## In-game verification

After Task 8:

```powershell
.\package.ps1 Healclick -Install
```

Then, in game:

1. `/hc` lists the commands.
2. Five rows appear. Yours shows your name and health; the other four are
   invisible until you group.
3. Click a button on your own row. Do you cast the spell in slot 1?
4. `/hc settings`, change slot 2's spell, close. Does the button change?
5. Group with someone. Their row appears with their name, class colour and
   health. Click a heal on it — do they get healed?
6. Walk out of range of them. Does their row dim? Walk back — does it brighten?
7. **In combat**, open settings and change a spell. Nothing should happen, and
   no error should appear. Leave combat — the change should apply.
8. **In combat**, have someone leave the party. Their row should vanish with no
   "Interface action failed" error.
9. `/hc lock`, try to drag the frame. `/hc reset` puts it back.
