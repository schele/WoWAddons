# FishingForever: the skill bar in two halves, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The skill bar shows the next point (left) and the skill against its cap (right) as two fills in the one frame, each half only while it has something to say.

**Architecture:** `SkillBar.Frame()` stays the one frame everything finds the bar by, but becomes a plain container holding two `StatusBar` fills, a divider, and an overlay frame that carries the labels (a child frame is drawn over its parent's own text, so labels on the container would hide behind the fills). A `mode()` decision (`both`, `skill`, `strip`) picks what shows and `layout(mode)` places it from the bar's current width, re-run when the stats window resizes the bar.

**Tech Stack:** WoW addon Lua (Classic client, Lua 5.1 semantics); specs run on Lua 5.4 through `tests/runner.lua` against `tests/wow_stub.lua`.

**Spec:** [docs/superpowers/specs/2026-11-27-fishingforever-skillbar-halves-design.md](../specs/2026-11-27-fishingforever-skillbar-halves-design.md)

## Global Constraints

- The bar stays 220 x 18 on its own (`SkillBar.WIDTH`); the stats window hard-codes 18 and widens the bar to its inside (`StatsPanel.lua` `attach`/`detach`). `StatsPanel.lua` is not changed.
- Exact words: left half `Next point`; right half `Fishing 27/175` (the existing `title()`: name, rank/cap); warnings `too low here` and `capped`.
- Colours: next point is FishingForever's blue `{ 0.4, 0.8, 1 }` as today; skill is a green distinct from it; capped is grey `{ 0.5, 0.5, 0.5 }`; `too low here` is red `{ 1, 0.3, 0.3 }`; a thin dark divider between the halves when both show.
- "300" is the highest Fishing rank: a cap of 300 reached is the final cap; a lower cap reached is a trainer's.
- No new settings, no new commands, no version bump.
- Do not commit. The user commits and publishes themselves.
- Code runs on the WoW client's Lua 5.1: no `//`, `goto` or bit operators.
- Run the suite from the repo root: `.\run-tests.ps1 FishingForever`.

## Review Focus

The spec implies these inputs; each has a test in the task named.

1. A cap of 0, or a rank above its cap: the skill fill stays within 0..1 with no division by zero (Task 1).
2. States left live without stale text or colour: a trainer raising the cap, leaving the water that was too low (Task 1).
3. A measured catches-per-point of 0 with the left half brought back by a warning: the fill is a number in 0..1, not NaN or infinity (Task 2).
4. The stats window open while the mode changes under it: the fills keep filling the widened bar (Task 2).
5. At 300 the stats still open and close, by click and by `/ff stats`, and the bar goes back to 220 wide (Task 3).

---

### Task 1: Two halves in the one bar

**Files:**
- Modify: `FishingForever/SkillBar.lua` (the frame in `create`, `draw`, new `layout`; `title`, drag, click and tooltip handlers stay)
- Modify: `FishingForever/tests/wow_stub.lua` (a size change fires `OnSizeChanged`, as the client does)
- Modify: `FishingForever/tests/skillbar_spec.lua` (replace the tests at lines 29-66 and 108-126, which read `bar.label`, `bar.count`, `bar.value`)
- Test: `FishingForever/tests/statspanel_spec.lua`

**Interfaces:**
- Consumes: `ns.Skill.Rank() -> rank, maxRank`, `ns.Skill.Catches()`, `ns.Skill.Expected(rank) -> average, source, points`, `ns.Skill.Capped()`, existing `tooLowHere()` and `title()` in `SkillBar.lua`.
- Produces, on the frame `SkillBar.Frame()` returns (a `Frame`, no longer a `StatusBar`):
  - `bar.pointFill`, `bar.skillFill`: `StatusBar`s, range 0 to 1, `EnableMouse(false)`.
  - `bar.pointLabel`, `bar.skillLabel`: `FontString`s on a full-size overlay frame above the fills.
  - `bar.divider`: `Texture`, 1 px wide.
  - local `fraction(value, whole) -> number`: `math.min(1, value / math.max(whole, 1))`, never NaN for a whole below 1.
  - local `layout(mode)`: sizes and anchors the fills, divider and labels from `bar:GetWidth()`; the left fill is `math.floor(width / 2)` wide, the right fill the rest. Task 1 knows only `"both"`.
  - `bar:SetScript("OnSizeChanged", ...)` calls `layout` with the mode last drawn.
  - stub: `widget:SetWidth` and `widget:SetSize` call `scripts.OnSizeChanged(widget, width, height)` when set.

- [ ] **Step 1: Stub support.** In `wow_stub.lua`, make `SetWidth` and `SetSize` call the widget's `OnSizeChanged` script after storing the size. Run `.\run-tests.ps1 FishingForever`; expected: still 168 passed.

- [ ] **Step 2: Write the failing tests.** At the top of `skillbar_spec.lua` add `BLUE = { 0.4, 0.8, 1 }`, `GREY = { 0.5, 0.5, 0.5 }` and `colourIs(got, want) -> boolean` (nil-safe, compares the three components). Replace the old tests with these (literals are the spec's):

```lua
it("shows the next point on the left and the skill on the right", function()
    local ns, env, bar = loggedIn()
    for _ = 1, 3 do catch(env) end
    assertEqual("Next point", bar.pointLabel.text)
    assertEqual("Fishing 231/300", bar.skillLabel.text)
    assertEqual(3 / ns.Skill.Expected(231), bar.pointFill.value)
    assertNear(231 / 300, bar.skillFill.value, 1e-9)
    assertTrue(colourIs(bar.pointFill.barColor, BLUE))
    assertFalse(colourIs(bar.skillFill.barColor, BLUE), "the halves are told apart by colour")
end)

it("fills the left half by the catches over what a point takes, and no further", function()
    -- as the old test: minValue 0, maxValue 1, then 10 more catches -> 1
end)

it("empties the left half at a point, and moves the right", function()
    -- rank 231 -> 232 on SKILL_LINES_CHANGED: skillLabel "Fishing 232/300",
    -- pointFill.value 0, skillFill.value ~ 232/300
end)

it("says capped on the left at a trainer's cap, both fills grey, and follows a trainer raising it", function()
    local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 150, maxRank = 150 } end)
    assertEqual("capped", bar.pointLabel.text)
    assertEqual("Fishing 150/150", bar.skillLabel.text)
    assertEqual(1, bar.pointFill.value); assertEqual(1, bar.skillFill.value)
    assertTrue(colourIs(bar.pointFill.barColor, GREY)); assertTrue(colourIs(bar.skillFill.barColor, GREY))
    env.__fishing.maxRank = 225
    helpers.fire(env, "SKILL_LINES_CHANGED")
    assertEqual("Next point", bar.pointLabel.text)
    assertNear(150 / 225, bar.skillFill.value, 1e-9)
    assertFalse(colourIs(bar.pointFill.barColor, GREY), "no grey left over")
end)

it("says too low here in red on the left, and is plain again in another zone", function()
    -- the refusal events of the old test at 106/150: pointLabel.text "too low here",
    -- pointLabel.textColor { 1, 0.3, 0.3 }; after ZONE_CHANGED_NEW_AREA to Westfall:
    -- "Next point" and textColor { 1, 1, 1 }
end)

it("keeps the right fill within the bar for a cap of 0 or a rank above its cap", function()
    local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 5, maxRank = 0 } end)
    assertEqual(1, bar.skillFill.value)
end)

it("is two halves of the bar's width, following it when it is widened", function()
    local ns, env, bar = loggedIn()
    assertEqual(110, bar.pointFill.width); assertEqual(110, bar.skillFill.width)
    bar:SetWidth(307)
    assertEqual(153, bar.pointFill.width); assertEqual(154, bar.skillFill.width)
end)
```

In `statspanel_spec.lua` add: opening the window (`click(bar)`) leaves `bar.pointFill.width + bar.skillFill.width == bar.width`, and closing it (`click(bar)` again) gives `110` and `110`.

- [ ] **Step 3: Run to verify they fail.** `.\run-tests.ps1 FishingForever`; expected: the new tests FAIL with `attempt to index a nil value (field 'pointLabel')` or similar, nothing else red.

- [ ] **Step 4: Implement.** In `SkillBar.lua`: `create` builds the container `CreateFrame("Frame", "FishingForeverSkillBar", UIParent)` keeping `SetSize`, background texture, border, movable/drag/click scripts and `place()`; adds the two fills, the overlay frame (`SetAllPoints`, frame level above the fills) with the two labels and the divider, and the `OnSizeChanged` script. `draw` sets, for the left half: label `too low here` (red) if `tooLowHere()`, else `capped` if `ns.Skill.Capped()`, else `Next point` (white); fill `fraction(catches, expected)` in blue, or `1` in grey when capped (the warning does not change the fill). Right half: label `title()`, fill `fraction(rank, maxRank)` in green, grey when capped. Remove `bar.label`/`bar.count`. Delete the old early returns.

- [ ] **Step 5: Run to verify they pass, then the whole suite.** `.\run-tests.ps1 FishingForever`; expected: all green. Then `.\run-tests.ps1`; expected: every addon green.

---

### Task 2: The skill alone while every catch raises it

**Files:**
- Modify: `FishingForever/SkillBar.lua`
- Test: `FishingForever/tests/skillbar_spec.lua`, `FishingForever/tests/statspanel_spec.lua`

**Interfaces:**
- Consumes: Task 1's `layout(mode)`, `fraction`, `bar.pointFill/skillFill/pointLabel/skillLabel/divider`.
- Produces: local `mode() -> "both" | "skill"` (Task 3 adds `"strip"`): `"both"` when `ns.Skill.Capped()` or `tooLowHere()`; otherwise `"skill"` when `(ns.Skill.Expected(rank)) <= 1`, else `"both"`. `layout("skill")` hides the left fill, left label and divider and makes the right fill the bar's full width, its label at the bar's left edge. The mode last drawn is what `OnSizeChanged` re-lays-out.

- [ ] **Step 1: Write the failing tests** in `skillbar_spec.lua`:

```lua
it("shows the skill alone, full width, while every catch raises it", function()
    local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 50, maxRank = 75 } end)
    assertFalse(bar.pointFill:IsShown()); assertFalse(bar.pointLabel:IsShown()); assertFalse(bar.divider:IsShown())
    assertEqual(220, bar.skillFill.width)
    assertEqual("Fishing 50/75", bar.skillLabel.text)
    assertNear(50 / 75, bar.skillFill.value, 1e-9)
end)

it("brings the left half back once a point takes more than one catch", function()
    local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 50, maxRank = 150 } end)
    env.__fishing.rank = 100            -- the old rule: a point takes 2 catches here
    helpers.fire(env, "SKILL_LINES_CHANGED")
    assertTrue(bar.pointFill:IsShown()); assertTrue(bar.divider:IsShown())
    assertEqual(110, bar.pointFill.width); assertEqual(110, bar.skillFill.width)
end)

it("goes by the measured catches per point where there are enough", function()
    -- five points at rank 100 that took one catch each: skill alone at 100
    local ns, env, bar = loggedIn(POLE, function(e)
        e.__fishing = { rank = 100, maxRank = 150 }
        e.FishingForeverDB = { skillUps = { [100] = { points = 5, catches = 5 } } }
    end)
    assertFalse(bar.pointFill:IsShown())
end)

it("brings the left half back for a warning even while every catch raises the skill", function()
    -- rank 50/75, then the refusal events of the "too low here" test (UNIT_SPELLCAST_SENT,
    -- UI_ERROR_MESSAGE 300 "Skill not high enough")
    -- pointFill shown, pointLabel.text "too low here", widths 110 and 110
end)

it("keeps the left fill a number from 0 to 1 when a measured point took no catches", function()
    -- rank 100/150, skillUps [100] = { points = 5, catches = 0 }, then the refusal events:
    local v = bar.pointFill.value
    assertTrue(v >= 0 and v <= 1, "a number in range, not NaN or infinity: " .. tostring(v))
end)
```

In `statspanel_spec.lua`: with `rank = 74, maxRank = 150`, open the window (`click(bar)`): `bar.skillFill.width == bar.width`; then `env.__fishing.rank = 76` and fire `SKILL_LINES_CHANGED` with the window still open: `bar.pointFill.width + bar.skillFill.width == bar.width` and the left fill is shown.

- [ ] **Step 2: Run to verify they fail.** Expected: the new tests FAIL (the left half is always shown); the Task 1 tests stay green.

- [ ] **Step 3: Implement `mode()` and extend `layout`/`draw`** as the Interfaces block says. Remember the mode drawn for `OnSizeChanged`.

- [ ] **Step 4: Run the suite.** `.\run-tests.ps1 FishingForever`; expected: all green.

---

### Task 3: A strip at 300

**Files:**
- Modify: `FishingForever/SkillBar.lua`
- Test: `FishingForever/tests/skillbar_spec.lua`, `FishingForever/tests/statspanel_spec.lua`

**Interfaces:**
- Consumes: Task 2's `mode()` and `layout`.
- Produces: local `FINAL_CAP = 300`; `mode()` returns `"strip"` when `ns.Skill.Capped()` and `maxRank >= FINAL_CAP`, checked before the other rules. `layout("strip")` hides both fills, the divider and the left label; the right label, `Fishing 300/300`, shows at the bar's left edge over the bar's own dark background. The bar stays shown, so a click still toggles the stats.

- [ ] **Step 1: Write the failing tests.**

```lua
-- skillbar_spec.lua
it("is only a label at 300, the highest rank", function()
    local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 300, maxRank = 300 } end)
    assertTrue(bar:IsShown())
    assertEqual("Fishing 300/300", bar.skillLabel.text)
    assertFalse(bar.pointFill:IsShown()); assertFalse(bar.skillFill:IsShown())
    assertFalse(bar.pointLabel:IsShown()); assertFalse(bar.divider:IsShown())
end)

it("turns into the label with the last point, and not before", function()
    local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 299, maxRank = 300 } end)
    assertTrue(bar.skillFill:IsShown())
    env.__fishing.rank = 300
    helpers.fire(env, "SKILL_LINES_CHANGED")
    assertFalse(bar.skillFill:IsShown())
end)

-- statspanel_spec.lua, with e.__fishing = { rank = 300, maxRank = 300 }
it("still opens the stats at 300 on a click, and gives the bar back at its own width", function()
    -- click(bar): panel shown, bar:GetParent() == panel, bar.skillLabel.text "Fishing 300/300"
    -- click(bar) again: panel hidden, bar.width == 220, bar:IsShown()
end)

it("opens the stats at 300 with /ff stats too", function()
    -- helpers.command(env, "stats"): panel shown with the bar inside
end)
```

The trainer's-cap test of Task 1 (150/150 keeps both halves, `capped`) stays as the check that a cap below 300 is not the strip.

- [ ] **Step 2: Run to verify they fail.** Expected: the 300 tests FAIL (the fills show); everything else green.

- [ ] **Step 3: Implement** `FINAL_CAP`, the `"strip"` mode and its `layout`.

- [ ] **Step 4: Run the suite.** `.\run-tests.ps1 FishingForever`; expected: all green.

---

### Task 4: The tooltip and the README

**Files:**
- Modify: `FishingForever/SkillBar.lua` (`showTooltip`)
- Modify: `FishingForever/README.md` (the "The skill bar" section, lines 49-75)
- Test: `FishingForever/tests/skillbar_spec.lua`

**Interfaces:**
- Consumes: `mode()` from Tasks 2 and 3.
- Produces: `showTooltip` adds one grey line after the title, by mode: `both`, "Left: catches toward your next skill point. Right: your skill against its cap."; `skill`, "Your skill against its cap."; `strip`, no extra line. The existing "Click to open or close..." and "Drag to move it." lines stay. No line may contain "since your last point" or "1 in" (existing tests forbid them: the count and the chance belong to the stats window).

- [ ] **Step 1: Write the failing tests** in the tooltip `describe` of `skillbar_spec.lua` (using the existing `hover` and `tooltipText`):

```lua
it("says what each showing half is", function()
    local ns, env, bar = loggedIn()
    hover(bar)
    assertMatch("next skill point", tooltipText(env))
    assertMatch("against its cap", tooltipText(env))
end)

it("does not describe a half that is not there", function()
    local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 50, maxRank = 75 } end)
    hover(bar)
    assertMatch("against its cap", tooltipText(env))
    assertFalse(tooltipText(env):find("next skill point", 1, true) ~= nil)
end)

it("says nothing about halves at 300", function()
    local ns, env, bar = loggedIn(POLE, function(e) e.__fishing = { rank = 300, maxRank = 300 } end)
    hover(bar)
    assertFalse(tooltipText(env):find("against its cap", 1, true) ~= nil)
end)
```

- [ ] **Step 2: Run to verify they fail**, then **implement** the mode-dependent line in `showTooltip`.

- [ ] **Step 3: Rewrite the README's skill-bar section** to match the spec: the bar's two halves (diagram as in the spec), when each shows, `too low here` and `capped` on the left, the strip at 300, and a click on it opening the stats. Keep the paragraphs on the average catches per point and the options page. No test: it is prose.

- [ ] **Step 4: Run every suite.** `.\run-tests.ps1`; expected: every addon green. Then mutation-check the new code: break `mode()`'s order (strip after the others), drop the `OnSizeChanged` relay, return `"both"` always, and clamp nothing in `fraction`; each must turn a test red. Restore after each.

---

## In-game check (the stub cannot draw)

After `.\package.ps1 FishingForever -Install -NoWago` and a `/reload` (no new files, so no restart): the labels read over the fills in both halves; a click still opens the stats window and a drag still moves the bar (the fills must not swallow the mouse); inside the stats window the halves fill the widened bar and the labels are not behind the fills; the divider is visible; at skill 300 the strip reads `Fishing 300/300` and opens the stats. If the fills draw over the labels or hide inside the stats window, the frame levels of the fills and the overlay are the place to look.
