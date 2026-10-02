# MailHandler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A checkbox on every inbox mail, Select all, and an Open (N) button beside the game's Open All that takes the gold and items of only the ticked mails, never deleting any.

**Architecture:** `Inbox` reads the mailbox and gives each mail a key that survives its gold and items being taken. `Ticks` holds the ticked keys. `Opener` works through the ticked mails from the bottom up, one take at a time, waiting for the server between takes. `Buttons` lays the checkboxes on the game's own rows after every inbox redraw and adds Select all and Open (N).

**Tech Stack:** Lua 5.1-flavoured (WoW runtime), Lua 5.4 for tests, the repo's spec runner (`run-tests.ps1`), Node for the icon (`tools/draw-icons.mjs`), PowerShell for packaging.

**Spec:** [docs/superpowers/specs/2026-10-02-mailhandler-design.md](../specs/2026-10-02-mailhandler-design.md)

## Global Constraints

- `## Interface: 11509, 16001`. No `SavedVariables`: ticks are forgotten when the mailbox closes.
- Runtime Lua is 5.1-flavoured: no `goto`, no `//`, no `table.unpack` in addon files.
- `run-tests.ps1` and `package.ps1` are not modified. Outside `MailHandler/`, only `tools/draw-icons.mjs`, the root `README.md` and the spec change (Task 6, and the spec's Open section now).
- Comments explain *why*; none restates the line below it.
- **Never** call `DeleteInboxItem`. **Never** take from a mail with cash on delivery.
- Takes go one at a time: `Opener.LOOK = 0.25` seconds between looks, `Opener.MAX_LOOKS = 8` looks (about two seconds) before a take is given up.
- Ticked mails are worked from the **bottom up** (oldest first). A mail's key counts alike mails only *above* it, so a mail the game removes once empty never moves a key still to be opened.
- Every read that could raise goes through `ns.Guarded`; `C_Container.GetContainerNumFreeSlots` first, `GetContainerNumFreeSlots` second.
- Chat lines start with `ns.PREFIX = "|cff66ccffMailHandler|r"` and a space. Words, verbatim:
  - `Opened 4 mails: 1g 23s 4c, 3 items.` (either part left out when nothing; `1 mail`, `1 item` singular)
  - `Skipped 1 cash-on-delivery mail.`
  - `Bags are full: 2 ticked mails left.` / `Mailbox closed: 2 ticked mails left.`
  - The parts are joined by a space; nothing is printed when none applies.
- Money words: `GetMoneyString(copper)` where the client has it, else `1g 23s 4c` leaving out zero parts, `0c` for nothing.
- Commit messages start `MailHandler: ` and end with the trailer `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **Two equal sales, both ticked, removed by the game once empty.** Both are opened; neither tick is lost. Pinned in Task 4 ("opens alike mails the game removes once empty").
2. **A take the server never answers.** It is given up after about two seconds and the run goes on; that mail stays ticked. Pinned in Task 4 ("gives up a take the server never answers").
3. **A mail that will not read.** It is skipped; the others are read and keyed. Pinned in Task 2 ("skips a mail it cannot read").
4. **Bags full partway through a mail with gold and items.** The gold already taken shows in the line, and the line says how many ticked mails are left. Pinned in Task 4 ("stops when the bags are full").
5. **Clicking Open while it runs.** Nothing more starts, and Open is greyed until it ends. Pinned in Task 4 ("does nothing when Open is clicked while it runs") and Task 5 ("greys Open while it is opening").

## File Structure

| File | Responsibility |
|---|---|
| `MailHandler/MailHandler.toc` | Manifest and load order |
| `MailHandler/MailHandler.lua` | Namespace, `ns.Print`, `ns.Guarded`, `ns.Money`, `ns.Count`, `ns.Changed` |
| `MailHandler/Inbox.lua` | Reading the mailbox: mails with keys, attachments, free bag slots |
| `MailHandler/Ticks.lua` | The ticked keys, Select all, the count |
| `MailHandler/Opener.lua` | Opening the ticked mails, waiting, stopping, the line |
| `MailHandler/Buttons.lua` | Checkboxes on the rows, Select all, Open (N), Open All where missing, the mailbox events |
| `MailHandler/icon.tga` | Drawn by `tools/draw-icons.mjs` |
| `MailHandler/README.md` | What it does, install |
| `MailHandler/tests/runner.lua` | Copied unchanged from FishScale |
| `MailHandler/tests/wow_stub.lua` | The stubbed client: frames, the inbox, a server, bags, money, timers |
| `MailHandler/tests/helpers.lua` | Loading, mails, opening and closing the mailbox |
| `MailHandler/tests/*_spec.lua` | One spec per addon file |

The spec's Open section said "top to bottom"; this plan works bottom up, and Task 6 corrects the spec, for the reason in Global Constraints.

---

### Task 1: The core

**Files:**
- Create: `MailHandler/MailHandler.toc`, `MailHandler/MailHandler.lua`
- Create: `MailHandler/tests/runner.lua` (copy), `MailHandler/tests/wow_stub.lua`, `MailHandler/tests/helpers.lua`
- Test: `MailHandler/tests/addon_spec.lua`

**Interfaces:**
- Consumes: nothing.
- Produces: `ns.PREFIX`, `ns.Print(message)`, `ns.Guarded(fn, whenUnknown)`, `ns.Money(copper) -> string`, `ns.Count(count, word) -> "1 mail" | "2 mails"`, `ns.Changed()` (calls `ns.Buttons.Refresh()` if it exists).
  - Helpers: `helpers.FILES`, `helpers.loadAddon(prepare) -> ns, env`, `helpers.fire(env, event, ...)`, `helpers.mail(env, sender, subject, money, items, cod) -> mail`, `helpers.sale(env, item, count, money) -> mail`, `helpers.expired(env, item, count, slots) -> mail`, `helpers.openMailbox(env)`, `helpers.closeMailbox(env)`, `helpers.printed(env)`.
  - Stub state: `env.__mails` (top to bottom; each `{ sender, subject, money, cod, items = { [slot] = { name, count } }, raises, lost }`), `env.__money`, `env.__freeSlots`, `env.__log` (`"money i"`, `"item i:slot"`, `"delete i"`), `env.__slowServer`, `env.__autoRemove`, `env.__timers`, `env.__timerDelays`, `env.__runTimers()`, `env.__runAllTimers()`, `env.InboxFrame` (`.pageNum`), `env.MailItem1..7` and `env.MailItem1Button..7`, `env.OpenAllMail`, `env.InboxPrevPageButton`, `env.InboxFrame_Update()`, `widget:Click(mouseButton)`.

- [ ] **Step 1: Copy the spec runner**

```bash
mkdir -p MailHandler/tests
cp FishScale/tests/runner.lua MailHandler/tests/runner.lua
```

- [ ] **Step 2: Write the stubbed client**

Create `MailHandler/tests/wow_stub.lua`:

```lua
-- A minimal stand-in for the WoW API, enough to load MailHandler outside
-- the game: frames, the inbox and its rows, a server that answers takes,
-- bags, money and timers. It records what was done so tests can assert on it.

local stub = {}

local function makeWidget(env, kind, parent, template)
    local widget = {
        kind = kind,
        parent = parent,
        template = template,
        scripts = {},
        registeredEvents = {},
        points = {},
        shown = true,
        enabled = true,
        checked = false,
    }

    function widget:SetScript(name, fn) self.scripts[name] = fn end
    function widget:GetScript(name) return self.scripts[name] end
    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end
    function widget:SetPoint(...) table.insert(self.points, { ... }) end
    function widget:ClearAllPoints() self.points = {} end
    function widget:GetPoint(index)
        local point = self.points[index or 1]
        if point then return table.unpack(point) end
    end
    function widget:SetSize(w, h) self.width, self.height = w, h end
    function widget:SetWidth(value) self.width = value end
    function widget:GetWidth() return self.width or 0 end
    function widget:GetParent() return self.parent end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text end
    function widget:CreateFontString() return makeWidget(env, "FontString", self) end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end
    function widget:SetEnabled(value) self.enabled = value and true or false end
    function widget:IsEnabled() return self.enabled end
    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:SetShown(value) self.shown = value and true or false end
    function widget:IsShown() return self.shown end

    -- Test helper: drive this widget's OnEvent handler.
    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then handler(self, event, ...) end
    end
    -- Test helper: a click, which a disabled button ignores. A check button
    -- flips before its script runs, as the client's does.
    function widget:Click(mouseButton)
        if not self.enabled then return end
        if self.template == "UICheckButtonTemplate" then
            self.checked = not self.checked
        end
        if self.scripts.OnClick then
            self.scripts.OnClick(self, mouseButton or "LeftButton")
        end
    end

    return widget
end

function stub.newEnv()
    local env = setmetatable({}, { __index = _G })

    env._G = env
    env.__frames = {}
    env.__printed = {}

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do
            pieces[index] = tostring((select(index, ...)))
        end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    function env.CreateFrame(kind, name, parent, template)
        local frame = makeWidget(env, kind or "Frame", parent, template)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        return frame
    end

    function env.hooksecurefunc(name, fn)
        local original = env[name]
        env[name] = function(...)
            local results = { original(...) }
            fn(...)
            return table.unpack(results)
        end
    end

    -- The game's inbox: seven rows a page, each with its icon button, the
    -- page buttons and Open All at the bottom.
    env.INBOXITEMS_TO_DISPLAY = 7
    env.ATTACHMENTS_MAX_RECEIVE = 12
    env.UIParent = makeWidget(env, "Frame")
    env.InboxFrame = makeWidget(env, "Frame", env.UIParent)
    env.InboxFrame.pageNum = 1
    for row = 1, 7 do
        env["MailItem" .. row] = makeWidget(env, "Frame", env.InboxFrame)
        env["MailItem" .. row .. "Button"] = makeWidget(env, "Button", env["MailItem" .. row])
    end
    env.InboxPrevPageButton = makeWidget(env, "Button", env.InboxFrame)
    env.OpenAllMail = makeWidget(env, "Button", env.InboxFrame, "UIPanelButtonTemplate")
    env.OpenAllMail.width = 120
    env.OpenAllMail:SetPoint("BOTTOM", env.InboxFrame, "BOTTOM", 0, 101)
    env.__redraws = 0
    function env.InboxFrame_Update() env.__redraws = env.__redraws + 1 end

    -- Timers run when a test says so. The server's answers to takes made
    -- before a round land after its timers, so a look always comes first.
    env.__timers = {}
    env.__timerDelays = {}
    env.__replies = {}
    env.C_Timer = {
        After = function(delay, fn)
            table.insert(env.__timerDelays, delay)
            table.insert(env.__timers, fn)
        end,
    }
    function env.__runTimers()
        local pending, replies = env.__timers, env.__replies
        env.__timers, env.__replies = {}, {}
        for _, fn in ipairs(pending) do fn() end
        for _, fn in ipairs(replies) do fn() end
    end
    function env.__runAllTimers()
        for _ = 1, 1000 do
            if #env.__timers == 0 and #env.__replies == 0 then return end
            env.__runTimers()
        end
        error("timers never stopped queuing")
    end

    -- The mailbox, top to bottom, and the server behind it.
    env.__mails = {}
    env.__money = 0
    env.__freeSlots = 10
    env.__log = {}
    -- A server that answers late, and one that removes a mail once it is
    -- empty, as the game may do with auction mail.
    env.__slowServer = false
    env.__autoRemove = false

    local function itemCount(mail)
        local count = 0
        for _ in pairs(mail.items) do count = count + 1 end
        return count
    end

    local function emptied(mail)
        if env.__autoRemove and mail.money == 0 and itemCount(mail) == 0 then
            for index, other in ipairs(env.__mails) do
                if other == mail then
                    table.remove(env.__mails, index)
                    return
                end
            end
        end
    end

    local function answer(mail, fn)
        if mail.lost then return end
        if env.__slowServer then
            table.insert(env.__replies, fn)
        else
            fn()
        end
    end

    function env.GetInboxNumItems() return #env.__mails, #env.__mails end
    function env.GetInboxHeaderInfo(index)
        local mail = env.__mails[index]
        if not mail then return nil end
        if mail.raises then error("attempt to compare a secret value") end
        return "icon", nil, mail.sender, mail.subject, mail.money, mail.cod, 29.5,
            itemCount(mail), false, false, false, true, false
    end
    function env.GetInboxItem(index, slot)
        local mail = env.__mails[index]
        local item = mail and mail.items[slot]
        if item then return item.name, 1000 + slot, "icon", item.count, 1, true end
    end
    function env.TakeInboxMoney(index)
        table.insert(env.__log, "money " .. index)
        local mail = env.__mails[index]
        if not mail then return end
        answer(mail, function()
            env.__money = env.__money + mail.money
            mail.money = 0
            emptied(mail)
        end)
    end
    function env.TakeInboxItem(index, slot)
        table.insert(env.__log, "item " .. index .. ":" .. slot)
        local mail = env.__mails[index]
        if not (mail and mail.items[slot]) or env.__freeSlots <= 0 then return end
        answer(mail, function()
            mail.items[slot] = nil
            env.__freeSlots = env.__freeSlots - 1
            emptied(mail)
        end)
    end
    function env.DeleteInboxItem(index) table.insert(env.__log, "delete " .. index) end
    function env.GetMoney() return env.__money end

    -- Bags: the free slots are all in the backpack.
    env.C_Container = {
        GetContainerNumFreeSlots = function(bag)
            if bag == 0 then return env.__freeSlots, 0 end
            return 0, 0
        end,
    }

    return env
end

return stub
```

- [ ] **Step 3: Write the test helpers**

Create `MailHandler/tests/helpers.lua`:

```lua
local stub = require("wow_stub")

local M = {}

M.FILES = {
    "MailHandler.lua",
}

--- Load the addon's files into a stubbed client, in .toc order. `prepare`
-- sees the client first.
function M.loadAddon(prepare)
    local env = stub.newEnv()
    if prepare then prepare(env) end
    local ns = {}
    for _, path in ipairs(M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("MailHandler", ns)
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

--- A mail at the bottom of the box. `items` maps attachment slots to
-- { name, count }.
function M.mail(env, sender, subject, money, items, cod)
    local mail = { sender = sender, subject = subject, money = money or 0, cod = cod or 0, items = items or {} }
    table.insert(env.__mails, mail)
    return mail
end

function M.sale(env, item, count, money)
    return M.mail(env, "Alliance Auction House", string.format("Auction successful: %s (%d)", item, count), money)
end

--- An expired auction, its items in `slots` attachments of `count` each.
function M.expired(env, item, count, slots)
    local items = {}
    for slot = 1, slots or 1 do
        items[slot] = { name = item, count = count }
    end
    return M.mail(env, "Alliance Auction House", string.format("Auction expired: %s (%d)", item, count), 0, items)
end

function M.openMailbox(env)
    M.fire(env, "MAIL_SHOW")
    env.InboxFrame_Update()
end

function M.closeMailbox(env)
    M.fire(env, "MAIL_CLOSED")
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

return M
```

- [ ] **Step 4: Write the manifest**

Create `MailHandler/MailHandler.toc`:

```
## Interface: 11509, 16001
## Title: MailHandler
## Notes: Tick the mails you want and open only those.
## Author: You
## Version: 0.1.0

MailHandler.lua
```

- [ ] **Step 5: Write the failing spec**

Create `MailHandler/tests/addon_spec.lua`:

```lua
local helpers = require("helpers")

describe("the addon's chat lines", function()
    it("start with its name", function()
        local ns, env = helpers.loadAddon()

        ns.Print("hello")

        assertMatch("^|cff66ccffMailHandler|r hello$", helpers.printed(env))
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
        assertEqual("1g 2s", ns.Money(10200))
    end)

    it("say 0c for nothing", function()
        local ns = helpers.loadAddon()

        assertEqual("0c", ns.Money(0))
    end)

    it("are the client's own where it has them", function()
        local ns, env = helpers.loadAddon()
        env.GetMoneyString = function(copper) return "MONEY:" .. copper end

        assertEqual("MONEY:5", ns.Money(5))
    end)
end)

describe("counting", function()
    it("says one mail, or a number of mails", function()
        local ns = helpers.loadAddon()

        assertEqual("1 mail", ns.Count(1, "mail"))
        assertEqual("3 items", ns.Count(3, "item"))
    end)
end)

describe("a change", function()
    it("does nothing while there are no buttons", function()
        local ns = helpers.loadAddon()

        ns.Changed()
    end)
end)
```

- [ ] **Step 6: Run it to see it fail**

Run: `.\run-tests.ps1 MailHandler`
Expected: FAIL, every test, with `cannot open MailHandler.lua`.

- [ ] **Step 7: Write the core**

Create `MailHandler/MailHandler.lua`:

```lua
local addonName, ns = ...

ns.PREFIX = "|cff66ccffMailHandler|r"

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

--- "1 mail", "2 mails".
function ns.Count(count, word)
    if count == 1 then
        return "1 " .. word
    end
    return string.format("%d %ss", count, word)
end

--- Something about the ticks or the opening changed: redraw the boxes and
-- Open's count, if they are made.
function ns.Changed()
    if ns.Buttons and ns.Buttons.Refresh then
        ns.Buttons.Refresh()
    end
end
```

- [ ] **Step 8: Run it and see it pass**

Run: `.\run-tests.ps1 MailHandler`
Expected: `7 passed, 0 failed`.

- [ ] **Step 9: Commit**

```bash
git add MailHandler
git commit -m "MailHandler: the core -- chat, money words and counts" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Reading the mailbox

**Files:**
- Create: `MailHandler/Inbox.lua`
- Modify: `MailHandler/MailHandler.toc` (append `Inbox.lua`), `MailHandler/tests/helpers.lua` (`M.FILES` gains `"Inbox.lua"`)
- Test: `MailHandler/tests/inbox_spec.lua`

**Interfaces:**
- Consumes: `ns.Guarded` (Task 1).
- Produces: `ns.Inbox.Count() -> number`, `ns.Inbox.Mails() -> { { index, key, sender, subject, money, cod, items }, ... }` top to bottom, `ns.Inbox.Find(key) -> mail | nil`, `ns.Inbox.HasAttachment(index, slot) -> boolean`, `ns.Inbox.FirstAttachment(index) -> slot | nil`, `ns.Inbox.FreeSlots() -> number`. A key is `sender|subject|cod#n`, n counting alike mails from the top.

- [ ] **Step 1: Write the failing spec**

Create `MailHandler/tests/inbox_spec.lua`:

```lua
local helpers = require("helpers")

describe("the mailbox", function()
    it("gives each mail's sender, subject, gold, cash on delivery and items, top to bottom", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 1500)
        helpers.expired(env, "Bronze Bar", 12, 2)

        local mails = ns.Inbox.Mails()

        assertEqual(2, #mails)
        assertEqual(1, mails[1].index)
        assertEqual("Alliance Auction House", mails[1].sender)
        assertEqual("Auction successful: Rough Stone (46)", mails[1].subject)
        assertEqual(1500, mails[1].money)
        assertEqual(0, mails[1].cod)
        assertEqual(0, mails[1].items)
        assertEqual(2, mails[2].items)
    end)

    it("gives each mail a key its gold and items do not change", function()
        local ns, env = helpers.loadAddon()
        local mail = helpers.expired(env, "Bronze Bar", 12, 2)
        mail.money = 100
        local before = ns.Inbox.Mails()[1].key

        mail.money = 0
        mail.items[1] = nil

        assertEqual(before, ns.Inbox.Mails()[1].key)
    end)

    it("tells alike mails apart by their order", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Copper Bar", 20, 500)
        helpers.sale(env, "Copper Bar", 20, 500)

        local mails = ns.Inbox.Mails()

        assertTrue(mails[1].key ~= mails[2].key)
        assertMatch("#1$", mails[1].key)
        assertMatch("#2$", mails[2].key)
    end)

    it("finds a mail by its key, and nothing for one that is gone", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 1500)
        helpers.sale(env, "Lodestone", 11, 900)
        local key = ns.Inbox.Mails()[2].key

        assertEqual(2, ns.Inbox.Find(key).index)

        table.remove(env.__mails, 2)
        assertNil(ns.Inbox.Find(key))
    end)

    it("skips a mail it cannot read", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 1500).raises = true
        helpers.sale(env, "Lodestone", 11, 900)

        local mails = ns.Inbox.Mails()

        assertEqual(1, #mails)
        assertEqual(2, mails[1].index)
    end)

    it("finds a mail's first attachment, and none in an empty one", function()
        local ns, env = helpers.loadAddon()
        local mail = helpers.expired(env, "Bronze Bar", 12, 3)
        mail.items[1] = nil
        helpers.sale(env, "Lodestone", 11, 900)

        assertEqual(2, ns.Inbox.FirstAttachment(1))
        assertNil(ns.Inbox.FirstAttachment(2))
    end)

    it("counts free bag slots, through the old call too", function()
        local ns, env = helpers.loadAddon()
        env.__freeSlots = 7

        assertEqual(7, ns.Inbox.FreeSlots())

        local container = env.C_Container
        env.C_Container = nil
        env.GetContainerNumFreeSlots = container.GetContainerNumFreeSlots
        assertEqual(7, ns.Inbox.FreeSlots())
    end)
end)
```

- [ ] **Step 2: Add the file to the load lists**

In `MailHandler/tests/helpers.lua`, `M.FILES` gains `"Inbox.lua"` after `"MailHandler.lua"`. In `MailHandler/MailHandler.toc`, add `Inbox.lua` as the last line.

- [ ] **Step 3: Run the tests to see them fail**

Run: `.\run-tests.ps1 MailHandler`
Expected: every test fails, with `cannot open Inbox.lua`.

- [ ] **Step 4: Write the reading**

Create `MailHandler/Inbox.lua`:

```lua
local addonName, ns = ...

-- What is in the mailbox: each mail's sender, subject, gold, cash on
-- delivery and items, and a key that stays with the mail while its gold and
-- items are taken. Reading only.

local Inbox = {}
ns.Inbox = Inbox

local function maxAttachments()
    return ATTACHMENTS_MAX_RECEIVE or 12
end

local function lastBag()
    return NUM_BAG_SLOTS or 4
end

function Inbox.Count()
    return ns.Guarded(function()
        local count = GetInboxNumItems()
        return type(count) == "number" and count or 0
    end, 0)
end

local function header(index)
    return ns.Guarded(function()
        local _, _, sender, subject, money, cod, _, itemCount = GetInboxHeaderInfo(index)
        if sender == nil and subject == nil then
            return nil
        end
        return {
            index = index,
            sender = type(sender) == "string" and sender or "",
            subject = type(subject) == "string" and subject or "",
            money = type(money) == "number" and money or 0,
            cod = type(cod) == "number" and cod or 0,
            items = type(itemCount) == "number" and itemCount or 0,
        }
    end, nil)
end

--- Every mail, top to bottom. A key is the mail's sender, subject and cash
-- on delivery, which taking its gold and items does not change, numbered
-- among the mails alike in those above it: two equal sales are #1 and #2.
function Inbox.Mails()
    local mails, seen = {}, {}
    for index = 1, Inbox.Count() do
        local mail = header(index)
        if mail then
            local base = mail.sender .. "|" .. mail.subject .. "|" .. mail.cod
            seen[base] = (seen[base] or 0) + 1
            mail.key = base .. "#" .. seen[base]
            mails[#mails + 1] = mail
        end
    end
    return mails
end

function Inbox.Find(key)
    for _, mail in ipairs(Inbox.Mails()) do
        if mail.key == key then
            return mail
        end
    end
    return nil
end

function Inbox.HasAttachment(index, slot)
    return ns.Guarded(function()
        local name = GetInboxItem(index, slot)
        return type(name) == "string" and name ~= ""
    end, false)
end

function Inbox.FirstAttachment(index)
    for slot = 1, maxAttachments() do
        if Inbox.HasAttachment(index, slot) then
            return slot
        end
    end
    return nil
end

function Inbox.FreeSlots()
    local free = 0
    for bag = 0, lastBag() do
        free = free + ns.Guarded(function()
            local get = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
            local slots = get and get(bag)
            return type(slots) == "number" and slots or 0
        end, 0)
    end
    return free
end
```

- [ ] **Step 5: Run the tests and see them pass**

Run: `.\run-tests.ps1 MailHandler`
Expected: `14 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add MailHandler
git commit -m "MailHandler: read the mailbox, with a key that stays with each mail" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The ticks

**Files:**
- Create: `MailHandler/Ticks.lua`
- Modify: `MailHandler/MailHandler.toc` (append `Ticks.lua`), `MailHandler/tests/helpers.lua` (`M.FILES` gains `"Ticks.lua"`)
- Test: `MailHandler/tests/ticks_spec.lua`

**Interfaces:**
- Consumes: `ns.Inbox.Mails()` (Task 2), `ns.Changed()` (Task 1).
- Produces: `ns.Ticks.Is(key) -> boolean`, `ns.Ticks.Set(key, on)`, `ns.Ticks.Clear()`, `ns.Ticks.Mails(mails) -> { mail, ... }` (the ticked ones, top to bottom; `mails` defaults to the inbox now), `ns.Ticks.Count(mails) -> number`, `ns.Ticks.AllTicked(mails) -> boolean`, `ns.Ticks.SetAll(on)`.

- [ ] **Step 1: Write the failing spec**

Create `MailHandler/tests/ticks_spec.lua`:

```lua
local helpers = require("helpers")

describe("a tick", function()
    it("ticks and unticks a mail", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 1500)
        local key = ns.Inbox.Mails()[1].key

        ns.Ticks.Set(key, true)
        assertTrue(ns.Ticks.Is(key))

        ns.Ticks.Set(key, false)
        assertFalse(ns.Ticks.Is(key))
    end)

    it("stays on its mail when a mail above it goes", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 1500)
        helpers.sale(env, "Lodestone", 11, 900)
        helpers.sale(env, "Copper Bar", 60, 2400)
        ns.Ticks.Set(ns.Inbox.Mails()[3].key, true)

        table.remove(env.__mails, 1)

        local ticked = ns.Ticks.Mails()
        assertEqual(1, #ticked)
        assertEqual("Auction successful: Copper Bar (60)", ticked[1].subject)
        assertEqual(2, ticked[1].index)
    end)

    it("is counted only while its mail is in the box", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 1500)
        ns.Ticks.Set(ns.Inbox.Mails()[1].key, true)

        table.remove(env.__mails, 1)

        assertEqual(0, ns.Ticks.Count())
    end)
end)

describe("Select all", function()
    local function box(env, count)
        for index = 1, count do
            helpers.sale(env, "Stone " .. index, 1, 100)
        end
    end

    it("ticks every mail, on every page, and unticks them again", function()
        local ns, env = helpers.loadAddon()
        box(env, 10)

        ns.Ticks.SetAll(true)
        assertEqual(10, ns.Ticks.Count())

        ns.Ticks.SetAll(false)
        assertEqual(0, ns.Ticks.Count())
    end)

    it("shows ticked only while every mail is", function()
        local ns, env = helpers.loadAddon()
        assertFalse(ns.Ticks.AllTicked(), "an empty box")

        box(env, 10)
        ns.Ticks.SetAll(true)
        assertTrue(ns.Ticks.AllTicked())

        ns.Ticks.Set(ns.Inbox.Mails()[4].key, false)
        assertFalse(ns.Ticks.AllTicked())
    end)

    it("is forgotten, with every tick, when cleared", function()
        local ns, env = helpers.loadAddon()
        box(env, 3)
        ns.Ticks.SetAll(true)

        ns.Ticks.Clear()

        assertEqual(0, ns.Ticks.Count())
    end)
end)
```

- [ ] **Step 2: Add the file to the load lists**

In `MailHandler/tests/helpers.lua`, `M.FILES` gains `"Ticks.lua"` after `"Inbox.lua"`. In `MailHandler/MailHandler.toc`, add `Ticks.lua` as the last line.

- [ ] **Step 3: Run the tests to see them fail**

Run: `.\run-tests.ps1 MailHandler`
Expected: every test fails, with `cannot open Ticks.lua`.

- [ ] **Step 4: Write the ticks**

Create `MailHandler/Ticks.lua`:

```lua
local addonName, ns = ...

-- Which mails are ticked, by key: a tick stays with its mail across pages
-- and as the list moves. Forgotten when the mailbox closes.

local Ticks = {}
ns.Ticks = Ticks

local ticked = {}

function Ticks.Is(key)
    return key ~= nil and ticked[key] == true
end

function Ticks.Set(key, on)
    if key then
        ticked[key] = on and true or nil
    end
    ns.Changed()
end

function Ticks.Clear()
    ticked = {}
end

--- The ticked mails among `mails`, top to bottom: a tick whose mail has
-- gone is not counted.
function Ticks.Mails(mails)
    local list = {}
    for _, mail in ipairs(mails or ns.Inbox.Mails()) do
        if ticked[mail.key] then
            list[#list + 1] = mail
        end
    end
    return list
end

function Ticks.Count(mails)
    return #Ticks.Mails(mails)
end

function Ticks.AllTicked(mails)
    mails = mails or ns.Inbox.Mails()
    return #mails > 0 and Ticks.Count(mails) == #mails
end

function Ticks.SetAll(on)
    for _, mail in ipairs(ns.Inbox.Mails()) do
        ticked[mail.key] = on and true or nil
    end
    ns.Changed()
end
```

- [ ] **Step 5: Run the tests and see them pass**

Run: `.\run-tests.ps1 MailHandler`
Expected: `20 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add MailHandler
git commit -m "MailHandler: ticks that stay with their mail, and Select all" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Opening the ticked mails

**Files:**
- Create: `MailHandler/Opener.lua`
- Modify: `MailHandler/MailHandler.toc` (append `Opener.lua`), `MailHandler/tests/helpers.lua` (`M.FILES` gains `"Opener.lua"`)
- Test: `MailHandler/tests/opener_spec.lua`

**Interfaces:**
- Consumes: `ns.Inbox.Find`, `ns.Inbox.HasAttachment`, `ns.Inbox.FirstAttachment`, `ns.Inbox.FreeSlots` (Task 2); `ns.Ticks.Mails`, `ns.Ticks.Set` (Task 3); `ns.Print`, `ns.Money`, `ns.Count`, `ns.Changed` (Task 1).
- Produces: `ns.Opener.LOOK = 0.25`, `ns.Opener.MAX_LOOKS = 8`, `ns.Opener.Start(mails) -> boolean` (false when running or nothing ticked), `ns.Opener.Running() -> boolean`, `ns.Opener.Stop()` (for the mailbox closing).

- [ ] **Step 1: Write the failing spec**

Create `MailHandler/tests/opener_spec.lua`:

```lua
local helpers = require("helpers")

local function tick(ns, ...)
    local mails = ns.Inbox.Mails()
    for _, index in ipairs({ ... }) do
        ns.Ticks.Set(mails[index].key, true)
    end
end

local function logged(env, entry)
    for _, line in ipairs(env.__log) do
        if line == entry then return true end
    end
    return false
end

describe("Open", function()
    it("takes the gold of the ticked mails only", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 100)
        helpers.sale(env, "Lodestone", 11, 200)
        helpers.sale(env, "Copper Bar", 60, 300)
        tick(ns, 1, 3)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(400, env.__money)
        assertEqual(200, env.__mails[2].money)
    end)

    it("takes every item of a ticked mail, one at a time, a pause apart", function()
        local ns, env = helpers.loadAddon()
        helpers.expired(env, "Bronze Bar", 12, 2)
        tick(ns, 1)

        ns.Opener.Start()
        assertEqual(1, #env.__log)
        assertEqual("item 1:1", env.__log[1])
        assertEqual(0.25, env.__timerDelays[1])

        env.__runTimers()
        assertEqual("item 1:2", env.__log[2])

        env.__runAllTimers()
        assertNil(next(env.__mails[1].items))
    end)

    it("takes the gold before the items", function()
        local ns, env = helpers.loadAddon()
        local mail = helpers.expired(env, "Bronze Bar", 12, 1)
        mail.money = 50
        tick(ns, 1)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual("money 1", env.__log[1])
        assertEqual("item 1:1", env.__log[2])
    end)

    it("never deletes a mail, and leaves an emptied one in the box", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 100)
        helpers.expired(env, "Bronze Bar", 12, 1)
        tick(ns, 1, 2)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(2, #env.__mails)
        for _, line in ipairs(env.__log) do
            assertFalse(line:find("delete", 1, true), line)
        end
    end)

    it("unticks each mail once it is opened", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 100)
        helpers.sale(env, "Lodestone", 11, 200)
        tick(ns, 1, 2)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(0, ns.Ticks.Count())
    end)

    it("works from the bottom up", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 100)
        helpers.sale(env, "Lodestone", 11, 200)
        tick(ns, 1, 2)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual("money 2", env.__log[1])
        assertEqual("money 1", env.__log[2])
    end)

    it("opens alike mails the game removes once empty, keeping the other's tick", function()
        local ns, env = helpers.loadAddon()
        env.__autoRemove = true
        helpers.sale(env, "Lodestone", 11, 900)
        helpers.sale(env, "Copper Bar", 20, 500)
        helpers.sale(env, "Copper Bar", 20, 500)
        tick(ns, 2, 3)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(1000, env.__money)
        assertEqual(1, #env.__mails)
        assertEqual(900, env.__mails[1].money)
    end)

    it("skips a cash-on-delivery mail and unticks it", function()
        local ns, env = helpers.loadAddon()
        helpers.mail(env, "Garrok", "Linen", 0, { [1] = { name = "Linen Cloth", count = 20 } }, 500)
        tick(ns, 1)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(0, #env.__log)
        assertEqual(0, ns.Ticks.Count())
        assertMatch("Skipped 1 cash%-on%-delivery mail%.", helpers.printed(env))
    end)

    it("stops when the bags are full, with the gold taken before", function()
        local ns, env = helpers.loadAddon()
        env.__freeSlots = 0
        helpers.expired(env, "Bronze Bar", 12, 1)
        helpers.sale(env, "Rough Stone", 46, 100)
        tick(ns, 1, 2)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(100, env.__money)
        assertFalse(logged(env, "item 1:1"))
        local printed = helpers.printed(env)
        assertMatch("Opened 1 mail: 1s%.", printed)
        assertMatch("Bags are full: 1 ticked mail left%.", printed)
    end)

    it("stops when the mailbox closes", function()
        local ns, env = helpers.loadAddon()
        helpers.expired(env, "Bronze Bar", 12, 2)
        helpers.expired(env, "Light Feather", 4, 2)
        tick(ns, 1, 2)

        ns.Opener.Start()
        ns.Opener.Stop()
        env.__runAllTimers()

        assertEqual(1, #env.__log)
        assertFalse(ns.Opener.Running())
        assertMatch("Mailbox closed: 2 ticked mails left%.", helpers.printed(env))
    end)

    it("waits for a server that answers late", function()
        local ns, env = helpers.loadAddon()
        env.__slowServer = true
        helpers.sale(env, "Rough Stone", 46, 100)
        helpers.sale(env, "Lodestone", 11, 200)
        tick(ns, 1, 2)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(300, env.__money)
        assertMatch("Opened 2 mails: 3s%.", helpers.printed(env))
    end)

    it("gives up a take the server never answers, and goes on", function()
        local ns, env = helpers.loadAddon()
        local lost = helpers.sale(env, "Rough Stone", 46, 100)
        lost.lost = true
        helpers.sale(env, "Lodestone", 11, 200)
        tick(ns, 1, 2)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(200, env.__money)
        assertFalse(ns.Opener.Running())
        assertTrue(ns.Ticks.Is(ns.Inbox.Mails()[1].key), "the mail given up stays ticked")
    end)

    it("says what it took in one line", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 10000)
        helpers.sale(env, "Lodestone", 11, 2304)
        helpers.expired(env, "Bronze Bar", 12, 1)
        helpers.expired(env, "Light Feather", 4, 2)
        tick(ns, 1, 2, 3, 4)

        ns.Opener.Start()
        env.__runAllTimers()

        assertMatch("^|cff66ccffMailHandler|r Opened 4 mails: 1g 23s 4c, 3 items%.$", helpers.printed(env))
    end)

    it("does nothing when Open is clicked while it runs", function()
        local ns, env = helpers.loadAddon()
        helpers.expired(env, "Bronze Bar", 12, 2)
        tick(ns, 1)

        assertTrue(ns.Opener.Start())
        assertFalse(ns.Opener.Start())

        assertEqual(1, #env.__log)
    end)
end)
```

- [ ] **Step 2: Add the file to the load lists**

In `MailHandler/tests/helpers.lua`, `M.FILES` gains `"Opener.lua"` after `"Ticks.lua"`. In `MailHandler/MailHandler.toc`, add `Opener.lua` as the last line.

- [ ] **Step 3: Run the tests to see them fail**

Run: `.\run-tests.ps1 MailHandler`
Expected: every test fails, with `cannot open Opener.lua`.

- [ ] **Step 4: Write the opener**

Create `MailHandler/Opener.lua`:

```lua
local addonName, ns = ...

-- Opening the ticked mails: gold first, then each item, one take at a
-- time, each waited for until the server answers. From the bottom up, so a
-- mail the game removes once empty never moves the ones still to do: a
-- mail's key counts only the mails above it.

local Opener = {}
ns.Opener = Opener

-- How often to look whether the server has answered a take, and how many
-- looks (about two seconds) before it is given up.
Opener.LOOK = 0.25
Opener.MAX_LOOKS = 8

local run

function Opener.Running()
    return run ~= nil
end

--- Whether the take a run is waiting on has been answered: the gold or the
-- item is gone from the mail, or the mail itself is.
local function answered(waiting)
    local mail = ns.Inbox.Find(waiting.key)
    if not mail then
        return true
    end
    if waiting.kind == "money" then
        return mail.money == 0
    end
    return not ns.Inbox.HasAttachment(mail.index, waiting.slot)
end

local function left(current)
    return #current.targets - current.at + 1
end

local function report(current, stopped)
    local parts = {}

    local opened = 0
    for _ in pairs(current.took) do
        opened = opened + 1
    end
    if opened > 0 then
        local what = {}
        local gained = math.max(0, (GetMoney() or 0) - current.startMoney)
        if gained > 0 then
            what[#what + 1] = ns.Money(gained)
        end
        if current.items > 0 then
            what[#what + 1] = ns.Count(current.items, "item")
        end
        local line = "Opened " .. ns.Count(opened, "mail")
        if #what > 0 then
            line = line .. ": " .. table.concat(what, ", ")
        end
        parts[#parts + 1] = line .. "."
    end

    if current.cod > 0 then
        parts[#parts + 1] = string.format("Skipped %s.", ns.Count(current.cod, "cash-on-delivery mail"))
    end
    if stopped then
        parts[#parts + 1] = stopped
    end
    if #parts > 0 then
        ns.Print(table.concat(parts, " "))
    end
end

local function finish(current, stopped)
    if run ~= current then
        return
    end
    run = nil
    report(current, stopped)
    ns.Changed()
end

local step

local function later(current)
    C_Timer.After(Opener.LOOK, function()
        step(current)
    end)
end

step = function(current)
    if run ~= current then
        return
    end

    local waiting = current.waiting
    if waiting then
        local done = answered(waiting)
        if not done and waiting.looks < Opener.MAX_LOOKS then
            waiting.looks = waiting.looks + 1
            later(current)
            return
        end
        current.waiting = nil
        if done then
            current.took[waiting.key] = true
            if waiting.kind == "item" then
                current.items = current.items + 1
            end
        else
            -- The server never answered: leave this mail, still ticked.
            current.at = current.at + 1
        end
    end

    while true do
        local key = current.targets[current.at]
        if not key then
            finish(current)
            return
        end

        local mail = ns.Inbox.Find(key)
        local slot = mail and ns.Inbox.FirstAttachment(mail.index)
        if mail and mail.cod > 0 then
            current.cod = current.cod + 1
            ns.Ticks.Set(key, false)
            current.at = current.at + 1
        elseif mail and mail.money > 0 then
            TakeInboxMoney(mail.index)
            current.waiting = { key = key, kind = "money", looks = 0 }
            later(current)
            return
        elseif slot then
            if ns.Inbox.FreeSlots() <= 0 then
                finish(current, string.format("Bags are full: %s left.", ns.Count(left(current), "ticked mail")))
                return
            end
            TakeInboxItem(mail.index, slot)
            current.waiting = { key = key, kind = "item", slot = slot, looks = 0 }
            later(current)
            return
        else
            -- Nothing left in it, or the game has removed it.
            ns.Ticks.Set(key, false)
            current.at = current.at + 1
        end
    end
end

--- Open the ticked mails, bottom up. False when a run is already going or
-- nothing is ticked.
function Opener.Start(mails)
    if run then
        return false
    end
    local ticked = ns.Ticks.Mails(mails)
    if #ticked == 0 then
        return false
    end

    local targets = {}
    for index = #ticked, 1, -1 do
        targets[#targets + 1] = ticked[index].key
    end
    run = {
        targets = targets,
        at = 1,
        startMoney = GetMoney() or 0,
        items = 0,
        cod = 0,
        took = {},
    }
    ns.Changed()
    step(run)
    return true
end

--- The mailbox closed: stop, and say what was done and what is left.
function Opener.Stop()
    if run then
        finish(run, string.format("Mailbox closed: %s left.", ns.Count(left(run), "ticked mail")))
    end
end
```

- [ ] **Step 5: Run the tests and see them pass**

Run: `.\run-tests.ps1 MailHandler`
Expected: `34 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add MailHandler
git commit -m "MailHandler: open the ticked mails, bottom up, a take at a time" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The checkboxes and buttons

**Files:**
- Create: `MailHandler/Buttons.lua`
- Modify: `MailHandler/MailHandler.toc` (append `Buttons.lua`), `MailHandler/tests/helpers.lua` (`M.FILES` gains `"Buttons.lua"`)
- Test: `MailHandler/tests/buttons_spec.lua`

**Interfaces:**
- Consumes: `ns.Inbox.Mails` (Task 2); `ns.Ticks.Is`, `ns.Ticks.Set`, `ns.Ticks.SetAll`, `ns.Ticks.Clear`, `ns.Ticks.Count`, `ns.Ticks.AllTicked` (Task 3); `ns.Opener.Start`, `ns.Opener.Running`, `ns.Opener.Stop` (Task 4).
- Produces: `ns.Buttons.Create()`, `ns.Buttons.Refresh()`, `ns.Buttons.Parts() -> { boxes = { [row] = CheckButton }, selectAll, open, openAll }` (`openAll` only where the game has none). Listens to `MAIL_SHOW`, `MAIL_INBOX_UPDATE`, `MAIL_CLOSED`; hooks `InboxFrame_Update`.

- [ ] **Step 1: Write the failing spec**

Create `MailHandler/tests/buttons_spec.lua`:

```lua
local helpers = require("helpers")

local function opened(count, prepare)
    local ns, env = helpers.loadAddon(prepare)
    for index = 1, count do
        helpers.sale(env, "Stone " .. index, 1, 100 * index)
    end
    helpers.openMailbox(env)
    return ns, env, ns.Buttons.Parts()
end

describe("the boxes", function()
    it("sit on each row, for that row's mail", function()
        local ns, _, parts = opened(3)
        local mails = ns.Inbox.Mails()

        assertEqual(mails[1].key, parts.boxes[1].key)
        assertEqual(mails[3].key, parts.boxes[3].key)
        assertTrue(parts.boxes[3]:IsShown())
        assertFalse(parts.boxes[4]:IsShown())
    end)

    it("follow a page change", function()
        local ns, env, parts = opened(9)

        env.InboxFrame.pageNum = 2
        env.InboxFrame_Update()

        assertEqual(ns.Inbox.Mails()[8].key, parts.boxes[1].key)
        assertTrue(parts.boxes[2]:IsShown())
        assertFalse(parts.boxes[3]:IsShown())
    end)

    it("tick their mail, and Open counts it", function()
        local ns, _, parts = opened(3)

        parts.boxes[2]:Click()

        assertTrue(ns.Ticks.Is(ns.Inbox.Mails()[2].key))
        assertEqual("Open (1)", parts.open:GetText())
        assertTrue(parts.boxes[2]:GetChecked())
    end)
end)

describe("Open", function()
    it("is greyed while nothing is ticked", function()
        local _, _, parts = opened(3)
        assertFalse(parts.open:IsEnabled())

        parts.boxes[1]:Click()
        assertTrue(parts.open:IsEnabled())
    end)

    it("opens the ticked mails", function()
        local _, env, parts = opened(3)
        parts.boxes[2]:Click()

        parts.open:Click()
        env.__runAllTimers()

        assertEqual(200, env.__money)
    end)

    it("is greyed while it is opening", function()
        local _, env, parts = opened(3)
        env.__slowServer = true
        parts.boxes[1]:Click()
        parts.boxes[2]:Click()

        parts.open:Click()

        assertFalse(parts.open:IsEnabled())
    end)
end)

describe("Select all", function()
    it("ticks every mail on every page, and unticks them", function()
        local ns, _, parts = opened(9)

        parts.selectAll:Click()
        assertEqual(9, ns.Ticks.Count())
        assertEqual("Open (9)", parts.open:GetText())
        assertTrue(parts.selectAll:GetChecked())

        parts.selectAll:Click()
        assertEqual(0, ns.Ticks.Count())
    end)

    it("shows ticked only while every mail is", function()
        local _, _, parts = opened(3)
        parts.selectAll:Click()

        parts.boxes[2]:Click()

        assertFalse(parts.selectAll:GetChecked())
    end)
end)

describe("Open All", function()
    it("is the game's own, moved over to make room", function()
        local _, env, parts = opened(3)

        local _, _, _, x = env.OpenAllMail:GetPoint(1)
        local _, _, _, openX = parts.open:GetPoint(1)
        assertEqual(50, x)
        assertEqual(-50, openX)
        assertTrue(env.OpenAllMail:IsShown())
        assertNil(parts.openAll)
    end)

    it("is MailHandler's own where the game has none, and opens every mail", function()
        local _, env, parts = opened(3, function(e) e.OpenAllMail = nil end)

        assertTrue(parts.openAll ~= nil)
        parts.openAll:Click()
        env.__runAllTimers()

        assertEqual(600, env.__money)
    end)
end)

describe("closing the mailbox", function()
    it("forgets the ticks", function()
        local ns, env, parts = opened(3)
        parts.boxes[1]:Click()

        helpers.closeMailbox(env)

        assertEqual(0, ns.Ticks.Count())
        assertEqual("Open (0)", parts.open:GetText())
    end)
end)
```

- [ ] **Step 2: Add the file to the load lists**

In `MailHandler/tests/helpers.lua`, `M.FILES` gains `"Buttons.lua"` after `"Opener.lua"`. In `MailHandler/MailHandler.toc`, add `Buttons.lua` as the last line.

- [ ] **Step 3: Run the tests to see them fail**

Run: `.\run-tests.ps1 MailHandler`
Expected: every test fails, with `cannot open Buttons.lua`.

- [ ] **Step 4: Write the buttons**

Create `MailHandler/Buttons.lua`:

```lua
local addonName, ns = ...

-- The checkboxes and buttons, laid on the game's own inbox: a box left of
-- each mail's icon, Select all under the title, and Open (N) beside the
-- game's Open All, which is moved over, not changed.

local Buttons = {}
ns.Buttons = Buttons

local BUTTON_WIDTH, BUTTON_HEIGHT = 96, 22
-- How far Open and Open All sit either side of where Open All was.
local SHIFT = 50

local created = false
local boxes = {}
local selectAll, openButton, ownOpenAll

local function rowsPerPage()
    return INBOXITEMS_TO_DISPLAY or 7
end

local function pageOffset()
    local page = InboxFrame and InboxFrame.pageNum
    return ((type(page) == "number" and page or 1) - 1) * rowsPerPage()
end

local function makeBox(row)
    local rowFrame = _G["MailItem" .. row]
    if not rowFrame then
        return nil
    end
    local box = CreateFrame("CheckButton", nil, rowFrame, "UICheckButtonTemplate")
    box:SetSize(22, 22)
    local icon = _G["MailItem" .. row .. "Button"]
    box:SetPoint("RIGHT", icon or rowFrame, "LEFT", -1, 0)
    box:SetScript("OnClick", function(self)
        ns.Ticks.Set(self.key, self:GetChecked())
    end)
    return box
end

local function panelButton(name, text, onClick)
    local made = CreateFrame("Button", name, InboxFrame, "UIPanelButtonTemplate")
    made:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    made:SetText(text)
    made:SetScript("OnClick", onClick)
    return made
end

local function openAll()
    ns.Ticks.SetAll(true)
    ns.Opener.Start()
end

function Buttons.Create()
    if created or not InboxFrame then
        return
    end
    created = true

    for row = 1, rowsPerPage() do
        boxes[row] = makeBox(row)
    end

    selectAll = CreateFrame("CheckButton", "MailHandlerSelectAll", InboxFrame, "UICheckButtonTemplate")
    selectAll:SetSize(22, 22)
    selectAll:SetPoint("TOPLEFT", InboxFrame, "TOPLEFT", 64, -36)
    selectAll.label = selectAll:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectAll.label:SetPoint("LEFT", selectAll, "RIGHT", 2, 0)
    selectAll.label:SetText("Select all")
    selectAll:SetScript("OnClick", function(self)
        ns.Ticks.SetAll(self:GetChecked())
    end)

    openButton = panelButton("MailHandlerOpenButton", "Open (0)", function()
        ns.Opener.Start()
    end)

    local native = OpenAllMail
    if native then
        local point, relative, relativePoint, x, y = native:GetPoint(1)
        point = point or "BOTTOM"
        relative = relative or InboxFrame
        relativePoint = relativePoint or point
        x, y = x or 0, y or 0
        native:ClearAllPoints()
        native:SetWidth(BUTTON_WIDTH)
        native:SetPoint(point, relative, relativePoint, x + SHIFT, y)
        openButton:SetPoint(point, relative, relativePoint, x - SHIFT, y)
    else
        -- This client has no Open All: one of ours, beside Open.
        openButton:SetPoint("LEFT", InboxPrevPageButton or InboxFrame, "RIGHT", 40, 0)
        ownOpenAll = panelButton("MailHandlerOpenAllButton", "Open All", openAll)
        ownOpenAll:SetPoint("LEFT", openButton, "RIGHT", 6, 0)
    end

    if hooksecurefunc and InboxFrame_Update then
        hooksecurefunc("InboxFrame_Update", Buttons.Refresh)
    end
end

function Buttons.Refresh()
    if not created then
        return
    end

    local mails = ns.Inbox.Mails()
    local byIndex = {}
    for _, mail in ipairs(mails) do
        byIndex[mail.index] = mail
    end

    local offset = pageOffset()
    for row, box in pairs(boxes) do
        local mail = byIndex[offset + row]
        box.key = mail and mail.key or nil
        box:SetShown(mail ~= nil)
        box:SetChecked(mail ~= nil and ns.Ticks.Is(mail.key))
    end

    local running = ns.Opener.Running()
    local count = ns.Ticks.Count(mails)
    selectAll:SetChecked(ns.Ticks.AllTicked(mails))
    openButton:SetText(string.format("Open (%d)", count))
    openButton:SetEnabled(count > 0 and not running)
    if ownOpenAll then
        ownOpenAll:SetEnabled(#mails > 0 and not running)
    end
end

function Buttons.Parts()
    return { boxes = boxes, selectAll = selectAll, open = openButton, openAll = ownOpenAll }
end

local events = CreateFrame("Frame")
events:RegisterEvent("MAIL_SHOW")
events:RegisterEvent("MAIL_INBOX_UPDATE")
events:RegisterEvent("MAIL_CLOSED")
events:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SHOW" then
        Buttons.Create()
        Buttons.Refresh()
    elseif event == "MAIL_INBOX_UPDATE" then
        Buttons.Refresh()
    else
        ns.Opener.Stop()
        ns.Ticks.Clear()
        Buttons.Refresh()
    end
end)
```

- [ ] **Step 5: Run the tests and see them pass**

Run: `.\run-tests.ps1 MailHandler`
Expected: `45 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add MailHandler
git commit -m "MailHandler: checkboxes on the inbox rows, Select all, and Open beside Open All" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Icon, READMEs, the spec, package, and the game

**Files:**
- Modify: `tools/draw-icons.mjs` (an envelope for MailHandler)
- Create: `MailHandler/icon.tga` (generated)
- Modify: `MailHandler/MailHandler.toc` (`## IconTexture`)
- Create: `MailHandler/README.md`
- Modify: `README.md` (root: a row)
- Modify: `docs/superpowers/specs/2026-10-02-mailhandler-design.md` (Open works bottom up; "Checked in game" after Carl's check)

**Interfaces:**
- Consumes: the finished addon.
- Produces: `dist/MailHandler-0.1.0.zip`, pushed to `origin/main`.

- [ ] **Step 1: Draw the icon**

In `tools/draw-icons.mjs`, change the first comment line to:

```js
// Draws the 64x64 icons for BossLoot, FishScale, BankBags, GatherMap, RankUp, AutoVendor, LFGBoard and MailHandler, and their minimap icons, in the style of
```

Before the line `const root = process.argv[2];`, add:

```js
// MailHandler: an envelope with its flap, in blue.
const blue = {
  dark: [6, 12, 22], glow: [26, 60, 104], ring: [96, 160, 230],
  light: [210, 232, 255], mid: [110, 164, 226], outline: [16, 36, 70], detail: [40, 80, 140],
};
const envelope = roundBox(32, 33, 20, 14, 2.5);
const envelopeDetails = union(
  segment(13.5, 20.5, 32, 35, 1), // the flap's two edges
  segment(50.5, 20.5, 32, 35, 1),
);
const envelopeShine = ellipse(22, 23.5, 5, 1.3);
```

After the last `writeTga(...)` line, add:

```js
writeTga(path.join(root, 'MailHandler', 'icon.tga'), draw(blue, envelope, envelopeDetails, envelopeShine));
```

Run: `node tools/draw-icons.mjs .` then `git status --short`.
Expected: `MailHandler/icon.tga` new, `tools/draw-icons.mjs` modified, no other `.tga` changed. Look at it as a PNG: a blue envelope on a dark tile with a ring.

- [ ] **Step 2: Point the manifest at it**

In `MailHandler/MailHandler.toc`, add after the `## Notes:` line (with the Edit tool: a shell passing it through Node loses the backslashes):

```
## IconTexture: Interface\AddOns\MailHandler\icon
```

- [ ] **Step 3: Write the README**

Create `MailHandler/README.md`:

````markdown
# MailHandler (World of Warcraft AddOn)

Open the mails you choose, not all or none. Every mail in your inbox gets a
checkbox; **Open** takes the gold and items of the ticked ones only, beside
the game's own **Open All**.

```
 [x] Alliance Auction House   Auction successful: Rough Stone (46)
 [x] Alliance Auction House   Auction successful: Copper Bar (60)
 [ ] Alliance Auction House   Auction expired: Bronze Bar (12)
        [ Open (2) ]  [ Open All ]
```

Collect your auction sales and leave the expired items in the mailbox for
when you have bag space, or relist them later.

## Ticking

- A checkbox left of each mail. A tick stays with its mail across pages
  and as mails above it are taken.
- **Select all**, under the title, ticks every mail on every page; click it
  again to untick them all.
- Ticks are forgotten when you close the mailbox.

## Open

**Open (N)** takes the gold, then each item, of every ticked mail, one at a
time so the server keeps up, starting with the oldest at the bottom. When it
is done, one chat line:

    Opened 4 mails: 1g 23s 4c, 3 items.

- It **never deletes a mail**. The game itself may remove an empty auction
  mail once its gold is taken.
- A **cash-on-delivery** mail is skipped and the line says so: MailHandler
  never pays for one.
- When your **bags are full** it stops and says how many ticked mails are
  left. Closing the mailbox stops it too.

**Open All** is the game's own button, moved over to make room. On a
client without one, MailHandler adds its own.

## Install

1. Copy this folder into your client's `Interface/AddOns` as `MailHandler`,
   so the result is `.../Interface/AddOns/MailHandler/MailHandler.toc`.
2. Restart the client and enable MailHandler from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 MailHandler -Install

See the [repo README](../README.md) for packaging and test commands.
````

- [ ] **Step 4: Add MailHandler to the root README's table**

In `README.md`, add after the LFGBoard row (with the Edit tool):

```markdown
| [MailHandler](MailHandler/) | A checkbox on every mail, and Open beside Open All to take only the ticked ones |
```

- [ ] **Step 5: Correct the spec's order**

In `docs/superpowers/specs/2026-10-02-mailhandler-design.md`, in "## Open", change `works through the ticked mails, top to bottom, one step at a time:` to `works through the ticked mails from the bottom up (oldest first), one step at a time, so a mail the game removes once empty never moves the ones still to do:`.

- [ ] **Step 6: Run every suite and package**

Run: `.\run-tests.ps1`
Expected: every suite passes; MailHandler shows `45 passed, 0 failed`.

Run: `.\package.ps1 MailHandler`
Expected: `dist/MailHandler-0.1.0.zip`, no "listed but missing" error.

- [ ] **Step 7: Commit and push**

```bash
git add tools/draw-icons.mjs MailHandler README.md docs/superpowers/specs/2026-10-02-mailhandler-design.md
git commit -m "MailHandler: icon and README; Open works bottom up" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push origin main
```

- [ ] **Step 8: Carl checks it in game, and the answers go into the spec**

On the machine Carl plays on: `git pull`, `.\package.ps1 MailHandler -Install`, restart, enable MailHandler. At a mailbox on Forever, the spec's "Checked in game" list:

1. The checkboxes appear on the rows and follow Prev and Next; Select all and Open (N) sit where they should.
2. Open takes only the ticked mails' gold and items; the line's gold matches the money gained.
3. What the game does with an empty auction mail.
4. Bags full stops it with the line saying so.

Write the answers into "## Checked in game", dated; change the status line to `**Status:** approved, checked in game`; commit with `MailHandler: what the game showed`. If the checkboxes do not appear, the inbox redraws differently on Forever: take it back to Carl with a `/fstack` of a mail row.
