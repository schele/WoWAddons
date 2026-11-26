# WardrobeForever stance buttons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Clicking a stance bar button shifts and swaps the set's weapons in the same click, mid-fight included.

**Architecture:** New `Stance.lua` lays secure macro buttons over `StanceBar.actionButtons`; `Forms.lua` exposes what the macros need and calls `ns.Stance.Refresh()` after each update.

**Tech Stack:** WoW Lua (Forever 16001), Lua 5.4 specs against `tests/wow_stub.lua`.

**Spec:** `docs/superpowers/specs/2026-11-26-wardrobeforever-form-sets-design.md` (Addendum)

## Global Constraints
- `.toc` order: WardrobeForever.lua, Forms.lua, Stance.lua, Settings.lua. Version 0.2.0 (unreleased).
- No `SetAttribute`/`CreateFrame` of secure buttons while `InCombatLockdown()`.
- Macro lines exactly: `/cast <name>`, `/equipslot [form:i] <slot> <item>`, `/equipslot [noform:i] <slot> <item>`, `/equipslot <slot> <item>`.
- One commit at the end (Wago changelog line).

## Review Focus
1. A set or normal weapon changing mid-fight: the macro must not change until the fight ends, with no error.
2. The click's swap landing before UPDATE_SHAPESHIFT_FORM: Forms must still remember the normal weapon.
3. Edit Mode / Quick Keybind: overlays out of the way.
4. Forms with no weapons in any set: no overlays at all.
5. A set weapon that is gone from the bags: no line for it.

### Task 1: Forms exposes weapons; home weapons; the click's swaps understood
- Files: `Forms.lua`, `tests/forms_spec.lua`, stub/helpers.
- Produces: `Forms.SetItems(setID) -> {[slot]=guid|false}`, `Forms.Normal(slot) -> guid|false|nil` (db.normal or db.home), `db.home[16..18]`.
- Specs: "remembers the weapons you wear in normal form"; "takes the home weapon for normal when the click swapped first"; "does not take the form's own set weapon for a change by hand".

### Task 2: Stance.lua overlays and macro text
- Files: `Stance.lua` (new), `.toc`, `tests/stance_spec.lua` (new), stub (StanceBar, secure buttons, GameTooltip, EditModeManagerFrame, QuickKeybindFrame, C_Item.GetItemName).
- Produces: `ns.Stance.Refresh()`, `ns.Stance.MacroFor(index) -> string|nil`, `ns.Stance.buttons[i]`.
- Specs: no overlays without set weapons; one per stance button when a set holds a weapon; Cat/Bear macro text; unconditional line when equal; no line for a missing item; no change in combat, updated when it ends; hidden in Edit Mode / Quick Keybind; tooltip shows the form.

### Task 3: Words, install, in-game check, commit
- README, options text; `.\run-tests.ps1`; `package.ps1 WardrobeForever -Install -NoWago`; Carl checks Bear→Cat and Cat→caster mid-fight by clicking the stance bar; commit "WardrobeForever: the stance bar swaps your set's weapons with the shift, even in a fight".
