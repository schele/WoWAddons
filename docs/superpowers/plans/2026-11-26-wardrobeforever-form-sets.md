# WardrobeForever form sets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shifting into a form puts on the equipment set the player chose for it; shifting out puts back what they wore before; in combat only weapons change and the rest waits for the fight to end.

**Architecture:** A new `Forms.lua` owns the choices and the swapping. Each update works out the wanted gear (the remembered normal gear with the current form's set on top) as slot → item GUID, then moves items one slot at a time with the cursor (`C_Container.PickupContainerItem` / `PickupInventoryItem`), skipping non-weapon slots in combat. `Settings.lua` gains a Forms section with one dropdown per form.

**Tech Stack:** Lua 5.1-style WoW addon (Forever client, interface 16001); tests in Lua 5.4 against `tests/wow_stub.lua`, run by `.\run-tests.ps1 WardrobeForever`.

**Spec:** `docs/superpowers/specs/2026-11-26-wardrobeforever-form-sets-design.md`

## Global Constraints

- Forever only (`## Interface: 16001`). Read Blizzard's `forever` branch of Gethe/wow-ui-source before assuming an API's shape.
- Saved per character: `## SavedVariablesPerCharacter: WardrobeForeverCharDB`.
- `.toc` load order: `WardrobeForever.lua`, `Forms.lua`, `Settings.lua`. Version `0.2.0`.
- Combat-safe slots come from Blizzard's `INVSLOTS_EQUIPABLE_IN_COMBAT` (main hand 16, off hand 17, ranged 18).
- Exact copy: dropdown entry `Leave gear alone`; empty-section line `This character has no forms or stances.`
- Options rows hang a 16px gap under the description (CLAUDE.md).
- No chat output, no red error from the game: never try a non-weapon slot in combat.
- The hover pop-out is unchanged; `wardrobe_spec.lua` and `settings_spec.lua` keep passing.
- One commit for the addon change, at the end. Every commit touching `WardrobeForever/` becomes a line in Wago's changelog (`tools/WagoChangelog.ps1`), so its subject is player-facing and starts `WardrobeForever: `.
- Install only with `.\package.ps1 WardrobeForever -Install -NoWago`. No Wago upload.

## Review Focus

1. **An item on the cursor when the form changes** (the player is dragging something): WardrobeForever must not drop or clear it; it waits and swaps on the next equipment change. Test in Task 1.
2. **/reload or login while shapeshifted, with a record saved**: nothing is swapped back and forth. Test in Task 2, plus the in-game check in Task 5.
3. **Bags full** when a set empties a slot: the slot stays as it is, nothing ends up on the cursor, and the record is kept so a later update can finish. Test in Task 1.
4. **A chosen set deleted** in Blizzard's tab: the form counts as "Leave gear alone". A renamed set keeps working (kept by ID). Test in Task 3.
5. **A shift while the last swap is still in flight** (items locked): locked slots are skipped and retried on `PLAYER_EQUIPMENT_CHANGED`, and are never mistaken for a change by hand. Test in Task 2.

---

### Task 0: Check the game (Carl, in Forever, before any code)

Gate for the whole plan: if check 4 fails, stop and bring the design back.

- [ ] **Step 1:** `/run for i=1,GetNumShapeshiftForms() do print(i, GetShapeshiftFormInfo(i)) end`. Expected: one line per form, its 5th value a spell ID (768 for Cat Form).
- [ ] **Step 2:** `/run local g=C_Item.GetItemGUID(ItemLocation:CreateFromEquipmentSlot(16)) print(g, C_Item.GetItemLocation(g):GetEquipmentSlot())`. Expected: a GUID, then `16`.
- [ ] **Step 3:** Save a set named `Cat` on the Equipment Manager tab, then `/run for s,l in pairs(C_EquipmentSet.GetItemLocations(C_EquipmentSet.GetEquipmentSetID("Cat"))) do print(s,l) end`. Expected: a number per slot (1 = ignored, 0 = empty, large numbers = where the item is).
- [ ] **Step 4:** In Cat Form, out of combat, right-click a piece of armour in your bags. Expected: it goes on.
- [ ] **Step 5:** In Cat Form, in a fight, right-click a weapon or idol in your bags. Expected: it goes on.

Note any surprise in the spec's "Check in the game first" section before Task 1.

### Task 1: Wear a form's set and put normal gear back

**Files:**
- Create: `WardrobeForever/Forms.lua`
- Modify: `WardrobeForever/WardrobeForever.toc` (add `Forms.lua` between the two files; add the `SavedVariablesPerCharacter` line)
- Modify: `WardrobeForever/tests/wow_stub.lua`, `WardrobeForever/tests/helpers.lua`
- Test: `WardrobeForever/tests/forms_spec.lua`

**Interfaces:**
- Produces (`ns.Forms`):
  - `Forms.List() -> { { spellID: number, name: string, index: number }, ... }`: this character's stance bar, in bar order.
  - `Forms.Sets() -> { { setID: number, name: string }, ... }`: in `C_EquipmentSet.GetEquipmentSetIDs()` order.
  - `Forms.GetSet(spellID) -> setID | nil`
  - `Forms.SetSet(spellID, setID | nil)`: saves the choice and runs `Forms.Update()`.
  - `Forms.Update()`: one pass (algorithm below).
  - Saved shape: `WardrobeForeverCharDB = { forms = { [spellID] = { set = setID, index = n } }, normal = { [slot] = guid | false }, placed = { [slot] = guid | false } }`. `false` means an empty slot.
- Produces (stub/helpers, used by Tasks 2 to 4):
  - Stub state: `__worn[slot] = guid`, `__bags[bag][slot] = guid` (bags 0 to 4, `__bagSize[bag]`, backpack 16 by default), `__itemInfo[guid] = { slots = {[slot]=true}, twoHand = bool }`, `__locked[guid] = true`, `__cursor`, `__pickups` (count of `PickupInventoryItem`/`PickupContainerItem` calls: "no cursor use" is `__pickups == 0`), `__refused` (count of equips the game turned down in combat), `__inCombat`, `__forms = { {spellID, name} }`, `__form` (index, 0 = none), `__sets[setID] = { name, slots = { [slot] = guid | "empty" } }` (a slot left out is ignored).
  - Stub API: `GetInventoryItemID`, `IsInventoryItemLocked`, `ItemLocation:CreateFromEquipmentSlot/CreateFromBagAndSlot` with `IsEquipmentSlot/GetEquipmentSlot/IsBagAndSlot/GetBagAndSlot`, `C_Item.DoesItemExist/GetItemGUID` (raises for an empty location, as the client does)`/GetItemLocation/IsLocked`, `ClearCursor`, `CursorHasItem`, `PickupInventoryItem`, `C_Container.PickupContainerItem/GetContainerFreeSlots/GetContainerNumFreeSlots`, `C_PaperDollInfo.CursorCanGoInSlot`, `UnitAffectingCombat`, `GetNumShapeshiftForms/GetShapeshiftForm/GetShapeshiftFormInfo` (spell ID 4th), `C_Spell.GetSpellName`, `C_EquipmentSet.GetEquipmentSetIDs/GetEquipmentSetInfo/GetItemLocations` (packed with `stub.worn`/`stub.inBag`; 0 empty, 1 ignored, -1 missing), `INVSLOTS_EQUIPABLE_IN_COMBAT`, `EQUIPMENT_SET_EMPTY_SLOT/IGNORED_SLOT/ITEM_MISSING`, `NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4`.
  - Stub rules: dropping a cursor item on a slot swaps it with the slot's item (the old one goes where the cursor item came from); a two-hander landing in 16 pushes the 17 item to the first free bag slot, or the drop is refused if there is none; in combat, a drop on a slot outside `INVSLOTS_EQUIPABLE_IN_COMBAT` is refused, clears the cursor and counts in `__refused`.
  - Helpers: `item(env, guid, slots, twoHand)`, `wear(env, slot, guid)`, `stow(env, guid, bag?, slot?)` (first free slot by default), `wearing(env, slot) -> guid|nil`, `makeSet(env, setID, name, slots)`, `druid(env)` (Bear Form 5487, Aquatic Form 1066, Cat Form 768, Travel Form 783), `shift(env, spellID|nil)` (sets `__form`, fires `UPDATE_SHAPESHIFT_FORM`), `fight(env, on)` (sets `__inCombat`, fires `PLAYER_REGEN_DISABLED`/`ENABLED`), `start(saved, prepare) -> ns, env` (loads, puts `saved` in `WardrobeForeverCharDB`, fires `ADDON_LOADED "WardrobeForever"`, `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`). `SLOT` gains `CHEST = 5`, `OFFHAND = 17`, `RANGED = 18`.

- [ ] **Step 1: Extend the stub and helpers as above, and write the failing tests**

Fixture: a druid wearing `legs-caster` (7) and `head-caster` (1), with `legs-cat` in the backpack, set 1 "Cat" = `{ [7] = "legs-cat" }`, and Cat Form's choice made with `ns.Forms.SetSet(768, 1)`.

```lua
it("puts on the Cat set when you shift into Cat Form")          -- shift 768 → wearing(7) == "legs-cat"
it("leaves the slots the set ignores alone")                    -- wearing(1) == "head-caster"
it("puts back what you wore when you shift out")                -- shift nil → wearing(7) == "legs-caster"
it("forgets what you wore once it is all back")                 -- next(db.normal) == nil, next(db.placed) == nil
it("goes from Cat's set straight to Bear's, and back from either")
  -- Bear (set 2) = { [7]="legs-bear", [8]="feet-bear" }, normal feet "feet-caster":
  -- 768 → legs-cat/feet-caster; 5487 → legs-bear/feet-bear; nil → legs-caster/feet-caster
it("brings your normal gear back in a form left on Leave gear alone") -- 768 then 783 → "legs-caster"
it("changes nothing for a form with no set")                    -- 783 from normal → no cursor use, db.normal empty
it("empties a slot the set saved as empty, and refills it on the way out")
  -- set { [17]="empty" }, worn "book" in 17 → nil in 17 and "book" in a bag; out → wearing(17) == "book"
it("keeps a slot it cannot empty when the bags are full")       -- __bagSize[0]=0 → wearing(17)=="book", CursorHasItem()==false
it("skips a set item that is missing")                          -- set slot -1 → slot unchanged, db.normal[slot] == nil
it("swaps rings between fingers and back")
  -- normal 11="ring-c", 12="ring-a"; set { [11]="ring-a", [12]="ring-b" } → 11 a, 12 b; out → 11 c, 12 a
it("brings back the off-hand a two-hander pushed off")
  -- normal 16="mace" (1H), 17="book"; set { [16]="staff" } (twoHand, 17 ignored) → 16 staff, 17 nil; out → mace, book
it("waits while you hold an item on the cursor")                -- cursor holds bag item, shift 768 → legs unchanged, cursor kept;
                                                                -- ClearCursor + PLAYER_EQUIPMENT_CHANGED → "legs-cat"
```

- [ ] **Step 2: Run, expect FAIL** — `.\run-tests.ps1 WardrobeForever`: forms_spec fails (`ns.Forms` is nil); the other specs pass.

- [ ] **Step 3: Implement `Forms.lua`**

Loads only where `C_EquipmentSet` and `GetShapeshiftFormInfo` exist. On `ADDON_LOADED` for this addon, it fills in the saved table. It registers `UPDATE_SHAPESHIFT_FORM`, `PLAYER_REGEN_ENABLED`, `PLAYER_EQUIPMENT_CHANGED` and `PLAYER_ENTERING_WORLD`, each running `Forms.Update()`. The current form is the 4th return of `GetShapeshiftFormInfo(GetShapeshiftForm())`, or none at index 0. A set's wanted items are `GetItemLocations` turned into GUIDs: a worn or bag (0 to `NUM_TOTAL_EQUIPPED_BAG_SLOTS`) location becomes its item's GUID, empty becomes `false`, and ignored, missing or bank slots are left out.

The pass, which the tests do not fully pin:

```lua
-- WEAPON_PARTNER = { [16] = 17, [17] = 16 }
function Forms.Update()
    if not ready or CursorHasItem() then return end
    local set = wanted items of the current form's set, or {}        -- slot -> guid | false
    -- 1. A slot WardrobeForever filled that now holds neither its item nor
    --    the normal one was changed by hand: let it go.
    for slot, normal in pairs(db.normal) do
        local now = worn(slot)                                         -- guid | false
        if db.placed[slot] ~= nil and now ~= db.placed[slot] and now ~= normal
            and not IsInventoryItemLocked(slot) then forget(slot) end
    end
    -- 2. Record the normal gear of every slot the set will change, all
    --    before any move (rings swap fingers mid-pass). Changing one weapon
    --    slot records the other too: a two-hander pushes the off-hand off.
    for slot, item in pairs(set) do
        if db.normal[slot] == nil and worn(slot) ~= item then
            db.normal[slot] = worn(slot)
            local partner = WEAPON_PARTNER[slot]
            if partner and db.normal[partner] == nil then db.normal[partner] = worn(partner) end
        end
    end
    -- 3. Move, in slot order (main hand before off hand).
    for slot = 1, 19 do
        local want, restoring = set[slot], false
        if want == nil and db.normal[slot] ~= nil
            and set[WEAPON_PARTNER[slot] or 0] == nil then         -- the partner of a set weapon waits
            want, restoring = db.normal[slot], true
        end
        if want ~= nil then
            if worn(slot) == want then
                if restoring then forget(slot) else db.placed[slot] = want end
            elseif not (UnitAffectingCombat("player") and not INVSLOTS_EQUIPABLE_IN_COMBAT[slot])
                and not IsInventoryItemLocked(slot) then
                local result = want == false and takeOff(slot) or putOn(want, slot)
                -- "moved" | "locked" | "missing" | "refused"
                if result == "moved" and not restoring then db.placed[slot] = want end
                if restoring and (result == "missing" or result == "refused") then forget(slot) end
                if restoring and worn(slot) == want then forget(slot) end
            end
        end
    end
end
```

`putOn(guid, slot)`: find the item with `C_Item.GetItemLocation`. It is "missing" when there is none, or when it sits in a bag outside 0 to `NUM_TOTAL_EQUIPPED_BAG_SLOTS`, and "locked" when `C_Item.IsLocked`. Otherwise `ClearCursor`, pick it up, and if `C_PaperDollInfo.CursorCanGoInSlot(slot)` is false, `ClearCursor` and return "refused". Then `PickupInventoryItem(slot)`. On a worn-to-worn move, when `db.placed[from] ~= nil`, set `db.placed[from]` to the item that just left `slot`. `takeOff(slot)`: take the first free slot in bags 0 to `NUM_TOTAL_EQUIPPED_BAG_SLOTS` (`GetContainerNumFreeSlots` bag type 0) that this pass has not used yet, then `PickupInventoryItem(slot)` and `C_Container.PickupContainerItem(bag, free)`. Return "refused" with no free slot.

`Forms.SetSet(spellID, setID)` stores `{ set = setID, index = <its stance bar index> }` (`nil` clears it) and runs `Forms.Update()`. `Forms.GetSet` returns the stored set ID.

- [ ] **Step 4: Run, expect PASS** — `.\run-tests.ps1 WardrobeForever`: all specs pass.

### Task 2: Combat, changes by hand, locks and reloads

**Files:**
- Modify: `WardrobeForever/Forms.lua`
- Test: `WardrobeForever/tests/forms_spec.lua`

**Interfaces:**
- Consumes: everything Task 1 produces.
- Produces: no new names.

- [ ] **Step 1: Write the failing tests** (Task 1's fixture, plus set "Cat" = `{ [7]="legs-cat", [16]="staff-cat" }` where combat matters, with `mace` worn in 16)

```lua
it("in a fight, changes weapons at once and armour when it ends")
  -- fight on, shift 768 → wearing(16)=="staff-cat", wearing(7)=="legs-caster", __refused==0
  -- fight off → wearing(7)=="legs-cat"
it("counts only the form you end the fight in")                 -- fight; 768; 5487; nil; fight off → all normal, __refused==0
it("leaves a slot you changed by hand while shifted")
  -- in Cat, equip "legs-pvp" by hand (stub swap) + PLAYER_EQUIPMENT_CHANGED; shift nil → wearing(7)=="legs-pvp", wearing(16)=="mace"
it("lets go of a normal item you no longer have")               -- in Cat, remove "legs-caster" from the bags; nil → "legs-cat", db.normal[7]==nil
it("tries a locked item again on the next equipment change")
  -- __locked["legs-cat"]=true; shift 768 → "legs-caster"; unlock + PLAYER_EQUIPMENT_CHANGED → "legs-cat"
it("does not mistake a swap still in flight for a change by hand")
  -- db.placed[7]="legs-cat", worn "legs-caster", IsInventoryItemLocked(7) → Update keeps db.normal[7]
it("swaps nothing on a reload in Cat Form")                     -- start(saved from a Cat session, __form=Cat) → no cursor use, gear unchanged
it("puts your normal gear back after a reload")                 -- that session, shift nil → "legs-caster"
it("never tries armour in a fight, so the game shows no error") -- every combat test asserts __refused==0
```

- [ ] **Step 2: Run** — `.\run-tests.ps1 WardrobeForever`. Task 1's pass already carries these rules (combat skip, lock skip, step 1's hand-change check, `PLAYER_ENTERING_WORLD`), so most may pass at once. Each failure is a rule the pass gets wrong.
- [ ] **Step 3: Fix each failure in `Forms.Update`**, never by loosening a Task 1 test.
- [ ] **Step 4: Run, expect PASS** — `.\run-tests.ps1 WardrobeForever`.

### Task 3: Choices that last: Dire Bear, new forms, deleted sets

**Files:**
- Modify: `WardrobeForever/Forms.lua`
- Test: `WardrobeForever/tests/forms_spec.lua`

**Interfaces:**
- Consumes: `Forms.List/GetSet/SetSet/Sets`, the `forms` saved shape.
- Produces: `Forms.GetSet(spellID)` returns nil for a set that no longer exists. Saved choices move with the form that replaces theirs.

- [ ] **Step 1: Write the failing tests**

```lua
it("lists the stance bar's forms in order, by name")            -- List()[3].spellID==768, .name=="Cat Form", .index==3
it("keeps Bear's set when Dire Bear Form takes its place")
  -- SetSet(5487, 2); reload with __forms[1] = {9634, "Dire Bear Form"} → GetSet(9634)==2, saved forms[5487]==nil
it("keeps every choice when a new form is learned")             -- add {24858, "Moonkin Form"} at the end → GetSet(768) unchanged
it("treats a deleted set as Leave gear alone")                  -- __sets[1]=nil → GetSet(768)==nil; shift 768 → nothing moves
it("follows a set renamed on the Equipment Manager tab")        -- __sets[1].name="Feral" → GetSet(768)==1, Sets() lists "Feral"
it("lists the character's sets in the game's order")            -- Sets()[1] == { setID=1, name="Cat" }
```

- [ ] **Step 2: Run, expect FAIL** (Dire Bear, deleted set).
- [ ] **Step 3: Implement.** A saved choice whose spell is no longer on the bar moves to the form now at its saved `index`, if that form has no choice of its own. This runs at the start of `Forms.List()` and `Forms.Update()`. `GetSet` checks `C_EquipmentSet.GetEquipmentSetInfo(setID)` and returns nil when it gives nothing.
- [ ] **Step 4: Run, expect PASS** — `.\run-tests.ps1 WardrobeForever`.

### Task 4: The Forms section on the options page

**Files:**
- Modify: `WardrobeForever/Settings.lua`
- Modify: `WardrobeForever/tests/wow_stub.lua` (the `WowStyle1DropdownTemplate` stand-in, copied from `BankBags/tests/wow_stub.lua:200-235`, including `Pick`; `CreateFrame` passes the template through)
- Test: `WardrobeForever/tests/settings_spec.lua`

**Interfaces:**
- Consumes: `ns.Forms.List()`, `ns.Forms.Sets()`, `ns.Forms.GetSet(spellID)`, `ns.Forms.SetSet(spellID, setID|nil)`.
- Produces: `Panel.forms = { { spellID, label = FontString, dropdown = DropdownButton }, ... }` and `Panel.noForms` (FontString), both rebuilt on every `OnShow`.

- [ ] **Step 1: Write the failing tests** (a druid with sets 1 "Cat" and 2 "Bear")

```lua
it("has a row for each form, named as the game names it")       -- #panel.forms==4, panel.forms[3].label:GetText()=="Cat Form"
it("offers Leave gear alone and every set")                     -- radios: "Leave gear alone", "Cat", "Bear"
it("shows Leave gear alone until a set is picked")              -- forms[3].dropdown.selectionText=="Leave gear alone"
it("saves the set you pick for that form")                      -- forms[3].dropdown:Pick(2) → ns.Forms.GetSet(768)==1
it("lets you go back to Leave gear alone")                      -- Pick(1) → GetSet(768)==nil
it("hangs the first row 16px under the description")            -- forms[1].label.points[1] == {"TOPLEFT", panel.about, "BOTTOMLEFT", 0, -16}
it("says so on a character without forms")                     -- no druid() → panel.noForms:GetText()=="This character has no forms or stances.", #forms==0
it("adds a form learned since the page was last open")          -- hide, add Moonkin, show → #panel.forms==5
it("says how forms and sets work")                              -- about text matches "shifting into the form puts it on" and "Equipment Manager"
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** The about text becomes the current paragraph, a blank line, then exactly: `Pick a set for a form below, and shifting into the form puts it on; shifting out puts back what you had on. Make sets on the character sheet: the arrow at its top right, then the Equipment Manager tab. In combat, weapons change at once and the rest when the fight ends.` Each row has a label at `PADDING` (`GameFontHighlight`, 140 wide) and a `DropdownButton` with `WowStyle1DropdownTemplate`, 200 wide, beside it. Rows are spaced `ROW_HEIGHT`, the first hangs 16px under `about`'s bottom, and they are created on demand and hidden when not needed. The menu's radios are `Leave gear alone` (data `false`) and then `Forms.Sets()`; `isSelected` compares against `Forms.GetSet`, and `setSelected` calls `Forms.SetSet(spellID, data or nil)`. If `CreateFrame` with the template fails (`pcall`), the row shows its label only.
- [ ] **Step 4: Run, expect PASS** — `.\run-tests.ps1 WardrobeForever`.

### Task 5: Release prep and the in-game check

**Files:**
- Modify: `WardrobeForever/WardrobeForever.toc` (`## Version: 0.2.0`; `## Notes:` gains "and give each druid form its own gear set" or similar, under 150 characters)
- Modify: `WardrobeForever/README.md` (a "Gear for each form" section: the player-facing bullets from the spec's "What the player gets", plus a "How it works" paragraph; the Tests section mentions the form specs)

- [ ] **Step 1: Update `.toc` and README.**
- [ ] **Step 2: Run all tests** — `.\run-tests.ps1 WardrobeForever`. Expected: all pass, 0 failed.
- [ ] **Step 3: Install** — `.\package.ps1 WardrobeForever -Install -NoWago`, then check the installed `Forms.lua` hash matches the repo's.
- [ ] **Step 4: Carl checks in Forever** after `/reload`: pick a set for Cat Form in Options, AddOns, WardrobeForever; shift in and out out of combat (gear swaps both ways); shift in a fight (weapons now, armour when it ends, no red error); `/reload` in Cat Form (nothing swaps), then shift out (normal gear back).
- [ ] **Step 5: Commit** once Carl confirms:

```bash
git add WardrobeForever docs/superpowers/specs/2026-11-26-wardrobeforever-form-sets-design.md docs/superpowers/plans/2026-11-26-wardrobeforever-form-sets.md
git commit -m "WardrobeForever: pick a gear set for each form, worn when you shift into it"
```
