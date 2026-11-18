# AutoVendor Junk List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the player pick items (typically low-level whites) that AutoVendor sells at every merchant along with the greys, chosen from a grid of their bag items on AutoVendor's options page.

**Architecture:** A new `Junk.lua` mirrors `Keep.lua` (an account-wide `{ [itemID] = name }` list with commands). `Bags.Junk` also sells listed items, and a new `Bags.Sellable` lists bag items that could be listed. The options page scrolls and gains an "Always sold" list and an "In your bags" grid, which lives in a new `Picker.lua`.

**Tech Stack:** WoW addon Lua (interfaces 11509 and 16001), the repo's own spec runner with the stubbed client in `AutoVendor/tests/wow_stub.lua`.

**Spec:** `docs/superpowers/specs/2026-11-18-autovendor-junk-list-design.md`

## Global Constraints

- Saved data lives in `AutoVendorDB`, per account: `junk = { [itemID] = name }` next to the existing `keep`.
- An item is on one list at most; adding to one takes it off the other and says so in chat.
- A slot is sold only when it holds a grey or a junk-listed item, has a sell price, is not locked, and is not on the keep list.
- One switch covers both: the page's checkbox reads `Sell grey items and my junk list`; `/av sell` prints `Sell grey items and junk list: on.` / `off.`
- Page order: description, the three switches, `Never sold` (keep list), `Always sold` (junk list, rows with a `Stop selling` button), `In your bags (click to always sell)` (the grid). The page scrolls.
- No new switches, no version bump in this plan (0.3.0 comes at release).
- Run tests from `AutoVendor/`: `lua tests/runner.lua tests/<file>_spec.lua`, or `.\run-tests.ps1 AutoVendor` from the repo root. Lua is at `C:\Users\Carl\AppData\Local\Programs\Lua\bin\lua.exe`.
- The stub (`tests/wow_stub.lua`) gains whatever widget methods new code calls, as no-ops or recorders; `tests/helpers.lua` `M.FILES` follows the `.toc` order.

## Review Focus

- An item the client has not described yet (no name or price from `GetItemInfo`) is left out of the grid, never shown blank or raising, and appears once it is described and the page refreshes. Test in Task 2 and Task 4.
- A junk-listed item with no sell price (e.g. `/av junk 6948`, the Hearthstone) is never sold. Test in Task 2.
- Grid buttons are reused: after a click redraws the grid, the button under the cursor holds the next item, and clicking it adds that item, not the first one. Test in Task 4.
- A bag slot that raises when read (a secret value) costs that slot only, both for selling and for the grid. Test in Task 2.
- A grey put on the keep list stays unsold even if it is also typed into `/av junk`: adding to the junk list takes it off the keep list, so the player's latest choice wins, and chat says so. Test in Task 1.

---

### Task 1: The junk list and its commands

**Files:**
- Create: `AutoVendor/Junk.lua`
- Modify: `AutoVendor/Keep.lua` (move `itemName`, `readItem`, `shown` out to `ns`; take an item off the junk list when it is kept; `/av list` shows both lists)
- Modify: `AutoVendor/AutoVendor.lua` (home of the shared item helpers)
- Modify: `AutoVendor/AutoVendor.toc` and `AutoVendor/tests/helpers.lua` `M.FILES`: `Junk.lua` after `Keep.lua`
- Modify: `AutoVendor/README.md`: a "The junk list" section after "The keep list", with the commands table
- Test: `AutoVendor/tests/junk_spec.lua` (new), `AutoVendor/tests/keep_spec.lua`

**Interfaces:**
- Produces: `ns.ReadItem(text) -> itemID, name` or nil (a Shift-clicked link or a bare number, as `readItem` does now); `ns.ItemName(itemID) -> string|nil`; `ns.ShownItem(name) -> "[name]"`.
- Produces: `ns.Junk.All() -> { [itemID] = name }`, `ns.Junk.Has(itemID) -> boolean`, `ns.Junk.Add(itemID, name)`, `ns.Junk.Remove(itemID)`, `ns.Junk.Drop(itemID) -> boolean` (silent removal, true when it was there).
- Produces: `ns.Keep.Drop(itemID) -> boolean` (silent removal, same contract).
- `Junk.Add`, `Junk.Remove`, `Keep.Add` and `Keep.Remove` call `ns.SettingsPanel.Refresh()` when it exists, as Keep does now.

- [ ] **Step 1: Write the failing tests** in `tests/junk_spec.lua` (use a `ready()` like keep_spec's):

```lua
it("lists an item from its Shift-clicked link", function()
    local ns, env = ready()
    helpers.command(env, "junk " .. env.__link(2589))
    assertTrue(ns.Junk.Has(2589))
    assertEqual("Linen Cloth", ns.db.junk[2589])
    assertMatch("Selling %[Linen Cloth%] at every merchant%.", helpers.printed(env))
end)
it("lists an item from its number", ...)            -- "junk 2589" -> Has(2589)
it("says so when the item is listed already", ...)  -- printed "[Linen Cloth] is already on the junk list."
it("gives the help for anything that is not an item", ...) -- "junk hello" -> help printed, nothing listed
it("takes an item off with /av unjunk", ...)        -- printed "No longer selling [Linen Cloth]."
it("says so when unjunking an item not on the list", ...) -- "[Linen Cloth] is not on the junk list."
it("takes a kept item off the keep list, and says so", function()
    local ns, env = ready()
    helpers.command(env, "keep 3300")
    helpers.command(env, "junk 3300")
    assertFalse(ns.Keep.Has(3300))
    assertTrue(ns.Junk.Has(3300))
    assertMatch("Selling %[Rabbit's Foot%] at every merchant%. It is off the keep list%.", helpers.printed(env))
end)
it("is still there after a reload", ...)             -- helpers.reload(env); ns.Junk.Has(2589)
it("is in /av's help", ...)                          -- "/av junk", "/av unjunk"
```

In `tests/keep_spec.lua` add:

```lua
it("takes a listed item off the junk list, and says so", function()
    local ns, env = ready()
    helpers.command(env, "junk 2589")
    helpers.command(env, "keep 2589")
    assertFalse(ns.Junk.Has(2589))
    assertMatch("Keeping %[Linen Cloth%]: it will not be sold%. It is off the junk list%.", helpers.printed(env))
end)
it("/av list names both lists", function()  -- after "keep 3300" and "junk 2589":
    -- printed has "Never sold:" before "[Rabbit's Foot]", then "Always sold:" before "[Linen Cloth]"
end)
it("/av list says each empty list is empty", ...) -- "Nothing is on the keep list." and "Nothing is on the junk list."
```

The existing "says when the list is empty" test keeps passing unchanged.

- [ ] **Step 2: Run them to see them fail**

Run: `lua tests/runner.lua tests/junk_spec.lua tests/keep_spec.lua` (from `AutoVendor/`)
Expected: the new tests FAIL (`Junk.lua` is not loaded, `ns.Junk` is nil); the old keep tests pass.

- [ ] **Step 3: Implement.** Move the helpers to `AutoVendor.lua` as `ns.ItemName`, `ns.ReadItem`, `ns.ShownItem`, and have `Keep.lua` use them. Write `Junk.lua` on `Keep.lua`'s model: `ns.AddDefaults({ junk = {} })`. Commands: `junk` (help: `always sell an item: Shift-click it after the command`) and `unjunk` (help: `stop selling an item: Shift-click it after the command`). `Keep.Add` calls `ns.Junk.Drop` and `Junk.Add` calls `ns.Keep.Drop`; each adds ` It is off the junk list.` / ` It is off the keep list.` to its line when the drop returned true. `/av list` (help: `show the items never sold and always sold`) prints `Never sold:` and the kept names, or `Nothing is on the keep list.`; then `Always sold:` and the listed names, or `Nothing is on the junk list.`. Names go in name order, as now.

- [ ] **Step 4: Run them to see them pass**

Run: `lua tests/runner.lua tests/junk_spec.lua tests/keep_spec.lua tests/addon_spec.lua`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add AutoVendor/Junk.lua AutoVendor/Keep.lua AutoVendor/AutoVendor.lua AutoVendor/AutoVendor.toc AutoVendor/README.md AutoVendor/tests/helpers.lua AutoVendor/tests/junk_spec.lua AutoVendor/tests/keep_spec.lua
git commit -m "AutoVendor: a junk list of items always sold, /av junk and /av unjunk"
```

### Task 2: Selling the junk list, and the bag items that could be listed

**Files:**
- Modify: `AutoVendor/Bags.lua`: `Bags.Junk` takes the junk list; new `Bags.Sellable`; `slotItem` also returns the icon
- Modify: `AutoVendor/Vendor.lua`: pass the junk list; `/av sell` wording
- Modify: `AutoVendor/AutoVendor.toc`: `## Notes:` becomes `Sells your grey items and the items you pick, and repairs your gear whenever you open a merchant, and undercuts the cheapest auction when you post one.`
- Modify: `AutoVendor/README.md` "What it sells": white items are sold only when the player put them on the junk list
- Modify: `AutoVendor/tests/wow_stub.lua` `env.__items`: add `[117] = { name = "Tough Jerky", quality = 1, price = 1 }`, used by this task's tests and the later ones
- Test: `AutoVendor/tests/bags_spec.lua`, `AutoVendor/tests/vendor_spec.lua`

**Interfaces:**
- Consumes: `ns.Junk.All()` (Task 1).
- Produces: `ns.Bags.Junk(keep, chosen) -> { { bag, slot, itemID, count, price }, ... }`. `chosen` is optional: the junk list, `{ [itemID] = name }`.
- Produces: `ns.Bags.Sellable(keep, chosen) -> { { itemID, name, icon }, ... }`. One entry per item ID in the bags. Each is not grey, has a sell price and a name, is on neither list and is not marked no-value. Sorted by name, then by item ID.

- [ ] **Step 1: Write the failing tests**

In `tests/bags_spec.lua`:

```lua
it("is a white item on the junk list", function()   -- describe("junk")
    local ns, env = ready()
    helpers.put(env, 0, 1, 2589, 5)
    local junk = ns.Bags.Junk({}, { [2589] = "Linen Cloth" })
    assertEqual(1, #junk); assertEqual(2589, junk[1].itemID); assertEqual(5, junk[1].count)
end)
it("is an item on the junk list no merchant will pay for", ...) -- "not junk": 6948 listed -> 0 entries
it("is an item on both lists", ...)                            -- "not junk": keep wins -> 0 entries
-- describe("what could be put on the junk list")
it("is each white item in the bags once, by name, with its icon", ...)
    -- 2589 in 0:1 and 0:2 -> one entry { itemID = 2589, name = "Linen Cloth", icon = 1 }
it("leaves out greys, items with no sell price, and items on either list", ...)
    -- slots hold 3300 (grey), 6948 (no price), 2589 (listed) and 117 (Tough Jerky) -> only 117
it("leaves out an item the client has not described yet", ...)
    -- env.__uncached[2589] = true -> no entry; cleared -> entry
it("skips a slot that will not read", ...)          -- env.__raisingSlots["0:1"] = true, 2589 in 0:2 -> entry found
```

In `tests/vendor_spec.lua`:

```lua
it("sells items on the junk list along with the greys", ...)
    -- 3300 in 0:1, 2589 in 0:2, "junk 2589", openMerchant, __runAllTimers -> both slots sold, line "Sold 2 items"
it("sells no junk-listed item with selling turned off", ...)
```

Change the existing expectation `"Sell grey items: off%."` to `"Sell grey items and junk list: off%."` (and `on` likewise).

- [ ] **Step 2: Run them to see them fail**

Run: `lua tests/runner.lua tests/bags_spec.lua tests/vendor_spec.lua`
Expected: the new tests and the changed wording FAIL; the rest pass.

- [ ] **Step 3: Implement.** In `readSlot`, a slot qualifies when `item.quality == POOR or chosen[item.itemID]`; the keep, lock, no-value and price checks stay as they are. `slotItem` also returns `icon`: `info.iconFileID` on the new API, or the first return of legacy `GetContainerItemInfo`. `Bags.Sellable` walks the same bags and slots, each slot read in its own `ns.Guarded` call. Its name comes from `ns.ItemName` and its price from `sellPrice`. `Vendor.lua`'s `nextJunk` passes `ns.Junk.All()`. `/av sell` gets the help text `turn selling grey items and your junk list on or off` and the new printed wording.

- [ ] **Step 4: Run them to see them pass**

Run: `lua tests/runner.lua tests/bags_spec.lua tests/vendor_spec.lua tests/junk_spec.lua`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add AutoVendor/Bags.lua AutoVendor/Vendor.lua AutoVendor/AutoVendor.toc AutoVendor/README.md AutoVendor/tests/wow_stub.lua AutoVendor/tests/bags_spec.lua AutoVendor/tests/vendor_spec.lua
git commit -m "AutoVendor: the junk list is sold at merchants along with the greys"
```

### Task 3: The options page scrolls and shows the junk list

**Files:**
- Modify: `AutoVendor/Settings.lua`
- Modify: `AutoVendor/tests/wow_stub.lua`: `SetScrollChild` (records `scrollChild`), `GetVerticalScrollRange` (0), `SetVerticalScroll`, `GetHeight`, `GetStringHeight` (12 for a FontString), `SetAllPoints`
- Test: `AutoVendor/tests/settings_spec.lua`

**Interfaces:**
- Consumes: `ns.Junk.All()`, `ns.Junk.Remove(itemID)` (Task 1).
- Produces: on `ns.SettingsPanel`, keeping `panel`, `logo`, `hint`, `sell`, `repair`, `undercut`, `heading`, `empty` and `rows`:
  - `scroll`, and `content` (the scroll child; everything on the page is made on it, or on `panel` when the client has no scroll template);
  - `junkHeading`, `junkEmpty` and `junkRows` (rows `{ frame, button, label, itemID }`, like `rows`);
  - `Panel.Bottom() -> region`, the last shown region of the junk section, for Task 4 to hang from.
- `Panel.Refresh()` sets `content`'s height to the stacked height of everything on it.

- [ ] **Step 1: Write the failing tests** (in `settings_spec.lua`; `hasText(panel.panel, …)` becomes `hasText(panel.content, …)` throughout):

```lua
it("labels the sell switch for both lists", function()
    local _, _, panel = opened()
    assertTrue(hasText(panel.sell, "^Sell grey items and my junk list$"))
end)
it("says nothing is always sold, and how to add something", ...)
    -- junkEmpty shown; text "Nothing is always sold. Click an item in your bags below to add it."
it("lists every junk-listed item by name, in name order", ...)  -- junkRows labels "Linen Cloth, Tough Jerky"
it("stops selling an item from its row's button, as /av unjunk does", ...)
    -- junkRows[1].button.scripts.OnClick() -> not ns.Junk.Has(2589), row hidden, junkEmpty shown
it("hangs the junk list under the keep list, however long that is", function()
    local ns, env = loggedIn()
    helpers.command(env, "keep 3300"); helpers.command(env, "keep 7073")
    local panel = ns.SettingsPanel; panel.panel:Show()
    local to, where, y = anchor(panel.junkHeading)
    assertEqual(panel.rows[2].frame, to); assertEqual("BOTTOMLEFT", where); assertEqual(-12, y)
    helpers.command(env, "unkeep 3300"); helpers.command(env, "unkeep 7073")
    assertEqual(panel.empty, (anchor(panel.junkHeading)))
end)
it("follows /av junk and /av unjunk while the page is open", ...)
it("grows the scrolling page by a row for each listed item", function()
    -- content height with one junk item, then two: the difference is 24
end)
it("puts the whole page inside the scroll frame", ...) -- panel.scroll.scrollChild == panel.content
```

- [ ] **Step 2: Run them to see them fail**

Run: `lua tests/runner.lua tests/settings_spec.lua`
Expected: the new tests FAIL; the existing ones still pass once their `hasText` target is `content`.

- [ ] **Step 3: Implement.** Build the scroll frame as ForeverPanel's `buildScroll` does (`ForeverPanel/Modules/Settings.lua:395-422`, including hiding the scroll bar when nothing overflows). Turn the keep list's rows, empty text and heading into one section builder used twice. The keep list keeps its field names and button `Sell again`. The junk list gets the `Always sold` heading and a `Stop selling` button that calls `ns.Junk.Remove(row.itemID)`. On each refresh, re-anchor `junkHeading` under the keep section's last shown region (TOPLEFT to BOTTOMLEFT, 0, -12). New hint text: `Open a merchant and your grey items, and anything on your junk list, are sold and your gear repaired, without a click. Nothing on the keep list is ever sold. At the auction house, a new auction asks one copper under the cheapest listing.`

- [ ] **Step 4: Run them to see them pass**

Run: `lua tests/runner.lua tests/settings_spec.lua tests/junk_spec.lua tests/keep_spec.lua`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add AutoVendor/Settings.lua AutoVendor/tests/wow_stub.lua AutoVendor/tests/settings_spec.lua
git commit -m "AutoVendor: the options page scrolls and shows the junk list"
```

### Task 4: Picking items from your bags on the options page

**Files:**
- Create: `AutoVendor/Picker.lua`
- Modify: `AutoVendor/Settings.lua`: the `In your bags (click to always sell)` heading, the grid under it, and a refresh on `BAG_UPDATE_DELAYED` while the page is shown
- Modify: `AutoVendor/AutoVendor.toc` and `AutoVendor/tests/helpers.lua` `M.FILES`: `Picker.lua` before `Settings.lua`
- Modify: `AutoVendor/tests/wow_stub.lua`: `env.GameTooltip` with `SetOwner(owner, anchor)`, `SetItemByID(id)` (records `itemID`), `Show`, `Hide`, `IsShown`
- Modify: `AutoVendor/README.md` "The settings page": the junk list and picking from the bags
- Test: `AutoVendor/tests/picker_spec.lua` (new)

**Interfaces:**
- Consumes: `ns.Bags.Sellable(keep, chosen)` (Task 2), `ns.Junk.Add(itemID, name)` and `ns.Junk.All()` (Task 1), and `ns.SettingsPanel.content` and `ns.SettingsPanel.Bottom()` (Task 3).
- Produces: `ns.Picker.Build(parent, width)`, which makes `Picker.frame` (not anchored) and `Picker.empty`, whose text is `Nothing else in your bags can be sold.`
- Produces: `ns.Picker.Refresh() -> height` and `Picker.buttons`, a reused list of `{ itemID, name, icon }` buttons. Buttons are 32 square with gaps of 4, in `floor((width + 4) / 36)` columns.
- On `ns.SettingsPanel`: `bagsHeading`, anchored 12 below `Panel.Bottom()`. `Picker.frame` hangs `LIST_GAP` below it, and the content height includes `Picker.Refresh()`'s result.

- [ ] **Step 1: Write the failing tests** in `tests/picker_spec.lua` (open the page as settings_spec's `opened()` does):

```lua
it("shows each sellable item in the bags as an icon", function()
    -- 2589 in 0:1 and 0:2, 3300 (grey) in 0:3 -> one shown button, itemID 2589, icon texture 1
end)
it("says when nothing else in the bags can be sold", ...)       -- empty bags -> Picker.empty shown
it("puts an item on the junk list with a click, and takes it off the grid", function()
    -- click button 1 -> ns.Junk.Has(2589); grid no longer shows 2589; junkRows show "Linen Cloth"
end)
it("adds what the button holds now, after the grid has moved up", function()
    -- 2589 and 117 (Tough Jerky) in bags; click button 1 (Linen Cloth), then button 1 again -> 117 listed too
end)
it("shows the item's tooltip on hover and hides it after", ...)
    -- OnEnter -> GameTooltip.itemID == 2589, owner is the button, shown; OnLeave -> hidden
it("follows the bags while the page is open", ...)
    -- put 117 in 0:4, fire BAG_UPDATE_DELAYED -> a button for 117
it("does no work for bag changes while the page is closed", ...)
    -- page hidden, fire BAG_UPDATE_DELAYED -> Bags.Sellable not called (wrap it to count)
it("shows an item once the client has described it", ...)
    -- __uncached[2589], open -> empty; clear it, fire BAG_UPDATE_DELAYED -> shown
it("wraps to a new row after ten icons, and the page grows with it", ...)
    -- 11 distinct sellable items -> button 11 anchored under button 1; content height up by 36 vs 10 items
```

- [ ] **Step 2: Run them to see them fail**

Run: `lua tests/runner.lua tests/picker_spec.lua`
Expected: FAIL (`Picker.lua` is not loaded).

- [ ] **Step 3: Implement** `Picker.lua` with `Build` and `Refresh` as above. Each button's icon is a texture with `SetAllPoints`. `OnEnter` calls `GameTooltip:SetOwner(button, "ANCHOR_RIGHT")`, then `SetItemByID(button.itemID)` and `Show`; `OnLeave` hides it. `OnClick` reads `button.itemID` and `button.name` at click time and calls `ns.Junk.Add`. The page redraws from `Junk.Add`'s refresh. In `Settings.lua`, build the heading and `ns.Picker.Build(content, PANEL_WIDTH - PADDING * 2)`, and position both on every refresh. Register `BAG_UPDATE_DELAYED` and refresh only when the page is built and `panel:IsShown()`.

- [ ] **Step 4: Run them to see them pass**

Run: `lua tests/runner.lua tests/picker_spec.lua tests/settings_spec.lua`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add AutoVendor/Picker.lua AutoVendor/Settings.lua AutoVendor/AutoVendor.toc AutoVendor/README.md AutoVendor/tests/helpers.lua AutoVendor/tests/wow_stub.lua AutoVendor/tests/picker_spec.lua
git commit -m "AutoVendor: pick items from your bags on the options page to always sell them"
```

### Task 5: Whole suite and install

**Files:** none changed.

- [ ] **Step 1: Run every AutoVendor test**

Run: `.\run-tests.ps1 AutoVendor` (repo root)
Expected: every spec passes, 0 failed.

- [ ] **Step 2: Install for testing in the game, without uploading**

Run: `.\package.ps1 AutoVendor -Install -NoWago`
Expected: `Installed -> C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\AutoVendor`; the installed `Picker.lua` and `Junk.lua` hash the same as the repo's.
