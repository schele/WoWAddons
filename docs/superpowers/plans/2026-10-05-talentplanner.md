# TalentPlanner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Plan the order talent points are spent in, see the plan in a planner window and in the game's talent window, and be told (and optionally helped to learn) which talent comes next when a point is free.

**Architecture:** Two pure files carry the rules: `Plan.lua` (add, remove, validate, levels, next, over) and `Codec.lua` (the `TP1:` string). They see trees only as plain tables, never the game. `Trees.lua` is the one place that reads the game's talent calls and turns them into that table. Everything visible (planner window, talent-window overlay, reminder, minimap button, settings page) reads the active plan from `TalentPlanner.lua`'s database helpers and redraws when `ns.Changed()` is called.

**Tech Stack:** Lua 5.1-flavoured (WoW runtime), Lua 5.4 for tests with the repo's own spec runner (`run-tests.ps1`), Node for the icon (`tools/draw-icons.mjs`), PowerShell for packaging.

**Spec:** [docs/superpowers/specs/2026-10-05-talentplanner-design.md](../specs/2026-10-05-talentplanner-design.md)

## Global Constraints

- Target clients: Classic Era 1.15.x and the WoW Forever client (`_classic_beta_`): `## Interface: 11509, 16001`.
- `## SavedVariables: TalentPlannerDB`. Layout: `TalentPlannerDB.chars["Name-Realm"] = { active = "<name>", plans = { [name] = { class = "DRUID", points = { {tab, i}, ... } } } }`; settings beside `chars`.
- Point n is taken at level n + 9; at most 51 points (level 60).
- Rules, checked on every added point: below maxRank in the plan so far; the tree has 5 x (tier - 1) points planned before it; its prerequisite at full rank before it; no more than 51 points.
- Export string: `TP1:<CLASS>:<points>`, two characters a point: tab (1-3), then talent index in base 36 (`1`-`9`, `a`-`z`).
- Reminder line, verbatim shape: `Talent point ready: Feral Instinct (2/5)`. Not repeated for the same point.
- Settings, defaults: Remind me when a point is free (on); Show the plan in the talent window (on); Show the Learn next button (off); Show the minimap button (on).
- `LearnTalent` only when the client has it, never in combat, only with the Learn setting on.
- Every game call goes through `ns.Guarded`. `Plan.lua` and `Codec.lua` make no game calls at all (a spec loads them into an empty environment to prove it).
- Talent buttons: `TalentFrameTalent<n>` or `PlayerTalentFrameTalent<n>`; tab info in either shape (`name, icon, points` or `id, name, description, icon, points`); unspent points from `UnitCharacterPoints("player")` or `GetUnspentTalentPoints()`; addon-loaded from `C_AddOns.IsAddOnLoaded` or `IsAddOnLoaded`.
- Runtime Lua is 5.1-flavoured: no `goto`, no `//`, no `table.unpack` in addon files.
- `run-tests.ps1`, `package.ps1` and the root `README.md` are not modified. `tools/draw-icons.mjs` gets additive lines only (another agent edits it concurrently).
- Every chat line starts with `ns.PREFIX = "|cff66ccffTalentPlanner|r"` and a space.
- No commits in this run: the main session commits.

## Review Focus

1. **A plan for points the client does not have** (an imported string or a saved plan naming talent 12 in a tree of 10, after a WoW Forever change). Expect: import refuses naming the point; a saved plan still draws, the bad point flagged and never offered as next. Pinned in Task 2 ("refuses a talent the tree does not have") and Task 3 ("rejects an index beyond the tree").
2. **Removing a talent other points rely on**, through the tier gate rather than a prerequisite (taking a tier-1 point out leaves a tier-2 point short). Expect: nothing changes, the message names the later point. Pinned in Task 2 ("refuses when a later point loses its tier").
3. **The player off plan** (spent a point the plan does not have). Expect: next still skips what is already learned, and the off-plan talent shows a red edge. Pinned in Task 2 ("next skips points already learned") and Task 6 ("marks a talent with more points than planned").
4. **The talent UI loaded before TalentPlanner** (another addon loads it first). Expect: overlay still attaches at login. Pinned in Task 6 ("attaches at login when the talent UI is already loaded").
5. **A pasted string with spaces or a newline round it, or lower/upper case index letters.** Expect: accepted. Pinned in Task 3 ("trims and accepts either case").

## File Structure

| File | Responsibility |
|---|---|
| `TalentPlanner/TalentPlanner.toc` | Manifest and load order |
| `TalentPlanner/TalentPlanner.lua` | Defaults, `ns.Print`, `ns.Guarded`, commands, OnLogin, `ns.Changed`/`ns.OnChange`, `ns.Plans` (per-character plans: active, new, rename, delete, select, import), `/tp probe` |
| `TalentPlanner/Plan.lua` | Pure rules: `Plan.Check/Add/Validate/Remove/Undo/Count/Levels/LevelOf/Next/Over/RanksOf` |
| `TalentPlanner/Codec.lua` | Pure `Codec.Encode/Decode` |
| `TalentPlanner/Trees.lua` | `Trees.Read()` from the game; `Trees.Missing()`; `Trees.Unspent()` |
| `TalentPlanner/Planner.lua` | The window, the plan menu, the text dialog (export/import/name/confirm) |
| `TalentPlanner/TalentFrame.lua` | Overlay on the game's talent window, its Learn next button |
| `TalentPlanner/Reminder.lua` | The chat line; `Reminder.LearnNext()` and its result for the probe |
| `TalentPlanner/Minimap.lua` | Minimap button: left planner, right settings, drag |
| `TalentPlanner/Settings.lua` | Canvas page with four checkboxes |
| `TalentPlanner/icon.tga`, `minimap.tga` | From `tools/draw-icons.mjs` |
| `TalentPlanner/README.md` | Like the other addons' |
| `TalentPlanner/tests/runner.lua` | Copied unchanged from FishScale |
| `TalentPlanner/tests/wow_stub.lua` | Stub client with a made-up three-tree druid, talent UI, menus, edit boxes, combat, LearnTalent |
| `TalentPlanner/tests/helpers.lua` | Load, fire, login, command, printed, `trees()` |
| `TalentPlanner/tests/*_spec.lua` | plan, codec, trees, addon (db/commands/probe), planner, talentframe, reminder, minimap, settings |

## The test class

The stub's druid (tab, index: name, tier, column, maxRank, prerequisite):

- 1 Balance: 1 Starlight Wrath t1c2 5; 2 Nature's Grasp t1c3 1; 3 Improved Nature's Grasp t1c4 4 (needs 1.2); 4 Moonglow t2c1 5; 5 Natural Weapons t2c2 5; 6 Moonfury t3c2 5; 7 Omen of Clarity t3c3 5; 8 Moonkin Form t4c2 1 (needs 1.6)
- 2 Feral Combat: 1 Ferocity t1c2 5; 2 Feral Instinct t1c3 5; 3 Thick Hide t2c2 5; 4 Feral Swiftness t2c3 5; 5 Sharpened Claws t3c2 5; 6 Feral Charge t3c3 1; 7 Savage Fury t3c1 5; 8 Blood Frenzy t4c1 5; 9 Primal Fury t4c2 5 (needs 2.5); 10 Heart of the Wild t5c2 5 (needs 2.9)
- 3 Restoration: 1 Improved Mark t1c2 5; 2 Furor t1c3 5; 3 Nature's Focus t2c2 5; 4 Swiftmend t2c3 1

Feral holds 46 points, so Feral full plus five Balance is exactly 51. Heart of the Wild is index 10, encoded `2a`.

## Trees table (the contract between Trees.lua and Plan.lua)

```lua
trees = {
  [tab] = {
    name = "Feral Combat", icon = <texture>, spent = <number>,
    talents = {
      [i] = { name = "Feral Instinct", icon = <texture>, tier = 1, column = 3,
              rank = 0, maxRank = 5, prereq = <index in same tab or nil> },
    },
  },
}
```

---

### Task 1: Scaffold and test harness

**Files:** Create `TalentPlanner/TalentPlanner.toc`, `TalentPlanner/TalentPlanner.lua`, `tests/runner.lua` (copy of FishScale's), `tests/wow_stub.lua`, `tests/helpers.lua`, `tests/addon_spec.lua`.

**Interfaces — Produces:** `ns.PREFIX`, `ns.Print(msg)`, `ns.Guarded(fn, whenUnknown)`, `ns.AddDefaults(t)`, `ns.RegisterCommand(name, help, handler)`, `ns.OnLogin(fn)`, `ns.OnChange(fn)`, `ns.Changed()`, `ns.db`, `ns.CharKey()` (`"Skyler-Aldira"`), `ns.PlayerClass()` (`"DRUID"`), `ns.Plans.Active()` -> plan, name (creates `"Plan 1"` for the player's class when there are none), `ns.Plans.Names()` (sorted), `ns.Plans.Select(name)`, `ns.Plans.New(name)` -> ok, why, `ns.Plans.Rename(new)` -> ok, why, `ns.Plans.Delete()`, `ns.Plans.Store(name, points)` (new plan with points, made active). Slash: `/tp` empty toggles the planner (when `ns.Planner` exists), `help` lists commands. Commands `new <name>`, `rename <name>`, `delete`.

- [ ] Step 1: write `addon_spec.lua`: loads and prints a loaded line; `/tp help` lists commands; db defaults (`remind`, `overlay` true, `learn` false, `minimap.hide` false); `Plans.Active()` creates "Plan 1" with class DRUID under `chars["Skyler-Aldira"]`; New refuses an empty or taken name, makes the new plan active; Rename moves it and keeps it active; Delete removes and falls back to another plan; `/tp new Feral` / `/tp rename Bear` / `/tp delete` work; a saved db from before is kept.
- [ ] Step 2: run `.\run-tests.ps1 TalentPlanner` — FAIL (files missing).
- [ ] Step 3: implement TOC + `TalentPlanner.lua` (FishScale's skeleton, plus `ns.Plans`).
- [ ] Step 4: run — PASS.

### Task 2: Plan.lua (pure rules)

**Files:** Create `TalentPlanner/Plan.lua`, `tests/plan_spec.lua`.

**Interfaces — Produces (all pure):**
- `Plan.MAX = 51`, `Plan.LevelOf(n) -> n + 9`
- `Plan.Count(points, tab, i, upto) -> number` (points 1..upto, default all)
- `Plan.TreeCount(points, tab, upto) -> number`
- `Plan.Check(trees, points, tab, i) -> true | false, reason` (can it be appended?)
- `Plan.Add(trees, points, tab, i) -> true | false, reason` (appends)
- `Plan.Validate(trees, points) -> true | false, badIndex, reason`
- `Plan.Remove(trees, points, tab, i) -> true, removedIndex | false, reason` (removes the talent's last planned point only if the rest stays valid; reason names the dependent point)
- `Plan.Undo(points) -> removed point or nil`
- `Plan.Levels(points, tab, i) -> { levels }`
- `Plan.RanksOf(trees) -> ranks[tab][i]`
- `Plan.Next(points, ranks) -> n, tab, i, rankAfter | nil` (first point whose planned count so far exceeds the current rank)
- `Plan.Over(points, ranks) -> set[tab][i] = true` (rank above what the plan has in its first `spent` points, spent = sum of ranks)
- `Plan.Describe(trees, n, point) -> "Point 7 (level 16), Feral Instinct"`

Reasons, verbatim: `"<name> is already at <max>/<max>."`, `"<name> needs <k> points in <tree> first."`, `"<name> needs <prereq> at <max>/<max> first."`, `"The plan is full: 51 points."`, `"Tree <tab> has no talent <i>."`; removal: `"Point 14 (level 23), Feral Charge, depends on it."`

- [ ] Step 1: write `plan_spec.lua` covering: loads into an empty environment (no game); rank cap; tier gate (needs 5 before tier 2, counts only that tree, counts only points before); prerequisite at full rank before; 51 cap (Feral 46 + Balance 5 then 52nd refused); unknown talent refused; levels "12, 14, 16"; Validate names first bad point; Remove last point of a talent; Remove refuses with the dependant (prereq) named; refuses when a later point loses its tier; Remove of an unplanned talent; Undo; Next from ranks and skipping points already learned; Next nil when plan done; Over with an off-plan point.
- [ ] Step 2: run — FAIL.
- [ ] Step 3: implement.
- [ ] Step 4: run — PASS.

### Task 3: Codec.lua (pure)

**Files:** Create `TalentPlanner/Codec.lua`, `tests/codec_spec.lua`.

**Interfaces — Produces:** `Codec.Encode(class, points) -> "TP1:DRUID:21222a"`, `Codec.Decode(text) -> { class = , points = } | nil, reason`. Reasons: `"Not a TalentPlanner string."`, `"The points are cut short."`, `"Point <n> names tree <c>; there are three."`, `"Point <n> names talent 0."`. Index > 35 is refused by Encode (returns nil, reason).

- [ ] Step 1: spec: round trip incl. index 10 -> `a`; empty plan `TP1:DRUID:`; trims and accepts either case; wrong prefix/version; odd length; bad tab; index 0; loads with no game.
- [ ] Step 2: FAIL. Step 3: implement. Step 4: PASS.

### Task 4: Trees.lua and import

**Files:** Create `TalentPlanner/Trees.lua`, `tests/trees_spec.lua`; add `ns.Import(text)` and `ns.Export()` in `TalentPlanner.lua`.

**Interfaces — Produces:** `Trees.Read() -> trees | nil, missing` (missing = list of absent call names), `Trees.Missing() -> list`, `Trees.Unspent() -> number | nil`, `Trees.CALLS`. `ns.Import(text) -> true, name | false, reason` (class check: `"This plan is for a MAGE; you are a DRUID."`; rule check: `"Point 7 (level 16), X: <reason>"`; stores a new plan "Imported", "Imported 2", ... and makes it active). `ns.Export() -> string`.

- [ ] Step 1: spec: reads names, tiers, columns, ranks, prereq index; both tab-info shapes; missing call listed and nil; a raising call gives nil; unspent from either call; import good/other class/broken rule/garbage; export of the active plan.
- [ ] Step 2: FAIL. Step 3: implement. Step 4: PASS.

### Task 5: Planner window

**Files:** Create `TalentPlanner/Planner.lua`, `tests/planner_spec.lua`.

**Interfaces — Produces:** `Planner.Toggle()`, `Planner.Open()`, `Planner.Refresh()`, `Planner.Frame()` (with `.trees[tab].buttons[i]` each with `.count` "2/5", `.level` "12", `.selector`, `.total` "23/51", `.undo`, `.clear`, `.export`, `.import`, `.learn`, `.status`, `.message`), `Planner.Dialog()` (with `.box`, `.text`, `.accept`, `.cancel`), `Planner.OpenMenu(owner)`. Consumes Plan, Codec, Trees, `ns.Plans`, `ns.Import/Export`, `ns.Reminder.LearnNext`.

- [ ] Step 1: spec: `/tp` toggles; BossLoot frame (SettingsFrameTemplate title, logo, opaque background) and Escape; draws three trees, count and level labels; left-click adds, refusal shown in status; right-click removes, refusal names dependant; tooltip SetTalent plus "Planned at levels ..."; Undo; Clear asks then empties; Export dialog holds `TP1:` text selected; Import dialog stores the plan or shows the reason; menu via MenuUtil lists plans and New/Rename/Delete; EasyMenu path; cycling fallback; total "n/51"; client without calls shows the message instead of trees; Learn button shown only with the setting and LearnTalent.
- [ ] Step 2: FAIL. Step 3: implement. Step 4: PASS.

### Task 6: TalentFrame overlay

**Files:** Create `TalentPlanner/TalentFrame.lua`, `tests/talentframe_spec.lua`.

**Interfaces — Produces:** `TalentFrame.Attach()`, `TalentFrame.Refresh()`, `TalentFrame.Overlays()` (by button), `TalentFrame.LearnButton()`.

- [ ] Step 1: spec: attaches on ADDON_LOADED Blizzard_TalentUI; attaches at login when already loaded; PlayerTalentFrame naming; "x planned" label per button by id and selected tab; glow on next; red edge on over-planned; hidden with the setting off; refresh on TalentFrame_Update hook and CHARACTER_POINTS_CHANGED; Learn next button only with setting.
- [ ] Step 2: FAIL. Step 3: implement. Step 4: PASS.

### Task 7: Reminder and Learn

**Files:** Create `TalentPlanner/Reminder.lua`, `tests/reminder_spec.lua`; `/tp probe` in `TalentPlanner.lua`.

**Interfaces — Produces:** `Reminder.Check()`, `Reminder.LearnNext() -> ok, why`, `Reminder.LastLearn()` (`{ name, result = "sent"|"worked"|"refused" }`).

- [ ] Step 1: spec: line at login with an unspent point; not repeated on a second event for the same point; next point after spending gets its own line; silent with setting off, no points, no plan; GetUnspentTalentPoints variant; Learn calls LearnTalent with the next point out of combat; refuses in combat; refuses without LearnTalent; refuses with setting off; a refusal by the client is recorded and the probe says so; probe lists every call present/missing incl. LearnTalent.
- [ ] Step 2: FAIL. Step 3: implement. Step 4: PASS.

### Task 8: Minimap and Settings

**Files:** Create `TalentPlanner/Minimap.lua`, `TalentPlanner/Settings.lua`, `tests/minimap_spec.lua`, `tests/settings_spec.lua`.

- [ ] Step 1: spec (copied shape from FishScale): button on the rim, left-click toggles planner, right-click opens settings, drag saves angle, hidden with `/tp minimap`; page registered as TalentPlanner, logo, four checkboxes showing defaults, each writes its setting (overlay hides labels, learn shows buttons, minimap hides button), rows hang under the hint.
- [ ] Step 2: FAIL. Step 3: implement. Step 4: PASS.

### Task 9: Icon, README, package

- [ ] Re-read `tools/draw-icons.mjs`; add a talent-tree glyph theme and two `writeTga` lines for TalentPlanner only; run `node tools/draw-icons.mjs .`; `git status` shows only `TalentPlanner/*.tga` new among .tga files (restore others with `git checkout`).
- [ ] Write `TalentPlanner/README.md` in the other addons' shape.
- [ ] `.\run-tests.ps1` (all suites pass); `.\package.ps1 TalentPlanner -Install`.
