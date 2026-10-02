# RankUp Design

**Date:** 2026-10-02
**Status:** approved in chat, pending the in-game probe (see "Checked before code")

## Purpose

Put the rank you just trained on your bars without dragging it there.

On WoW Forever, training a new rank leaves the old one on the action bar.
Every few levels a druid trains new ranks of Healing Touch, Rejuvenation,
Maul, Wrath and the rest, and each one means opening the spellbook and
dragging it over the old button. Testers have asked for this to be automatic;
Blizzard has not answered. A `/cast Healing Touch` macro is the usual
workaround, but it costs a macro slot per spell.

## What it is

When a button on your bars holds a lower rank than the highest you know,
RankUp says so in a small popup and, on one click, puts the highest rank in
its place.

```
 RankUp
 Healing Touch    Rank 4 -> Rank 5   (2 buttons)
 Rejuvenation     Rank 3 -> Rank 4   (1 button)
            [ Upgrade ]  [ Not now ]
```

**Every rank of a spell is upgraded**, not only the one that was the top.
The rule is one sentence: every spell button on your bars holds your highest
rank. A low rank kept on purpose for mana is upgraded with the rest; that is
the trade Carl chose for the simpler rule.

**It asks first.** Nothing changes until Upgrade is clicked.

## When it looks

- At login (`PLAYER_ENTERING_WORLD`).
- When a spell is learned (`LEARNED_SPELL_IN_TAB`, or whatever the probe
  shows this client fires; `SPELLS_CHANGED` as the fallback).
- On `/rankup`.

**Not** when a button changes (`ACTIONBAR_SLOT_CHANGED`). Dragging an old
rank onto a bar by hand does not bring the popup back; the next login, the
next spell learned or `/rankup` will.

When a look finds nothing, nothing shows. `/rankup` with nothing to do says
so in chat, since it was asked.

## What it looks at

Every action slot: bars 1 to 8, and the druid's Bear Form and Cat Form pages
that the main bar flips to. Classic uses slots 1 to 120; the newer bars go up
to 180. RankUp walks every slot the probe shows this client uses, skipping
any with nothing in it.

A slot is **outdated** when:

1. `GetActionInfo(slot)` says `"spell"` and gives a spell ID, and
2. that spell's name, looked up by name, gives a different spell ID: the
   highest rank known.

Items, macros, empty slots and spells with one rank are never outdated: an
item or macro is not `"spell"`, and a one-rank spell's name gives back the ID
already there.

Outdated slots are grouped by spell name. Each group carries the name, the
old rank's text, the new rank's text (`C_Spell.GetSpellSubtext` or
`GetSpellSubtext`, e.g. "Rank 5"), the new spell ID and the slots. Buttons
with two different old ranks of one spell share a group; the line then shows
the lowest old rank.

## The popup

A frame of RankUp's own, not a `StaticPopup`: Blizzard's popups are shared
with its own code and are a known route for taint, and taint is exactly the
failure this client already has around action bars (WoWUIBugs #888).

- One line per spell group: name, old rank, new rank, number of buttons.
- **Upgrade** swaps every listed slot, then closes.
- **Not now** closes. It comes back at the next look: next login, next spell
  learned, or `/rankup`.
- Movable by dragging; the position is not saved. It opens centred.

## Combat

Placing an action is refused in combat, so:

- A look that finds something during combat holds the popup until
  `PLAYER_REGEN_ENABLED`, then looks again and shows what it finds then.
- If combat starts with the popup open, Upgrade is disabled and turns back
  on when combat ends. The list stays.
- The swap itself checks `InCombatLockdown()` before each slot and stops
  there if a fight has started; what is left shows again when it ends.

## The swap

For each listed slot, out of combat:

1. `ClearCursor()`.
2. Pick up the new rank: `C_Spell.PickupSpell(id)` or `PickupSpell(id)`,
   whichever the client has.
3. `PlaceAction(slot)`. The old rank comes back onto the cursor.
4. `ClearCursor()`, which drops the old rank.

Then RankUp looks again. A slot that still holds an old rank is named in chat
(`RankUp: could not upgrade Healing Touch on button 14`) instead of being
reported as done. A swap that worked prints one line per spell:
`RankUp: Healing Touch -> Rank 5 (2 buttons)`.

## Architecture

Five files, shaped like the repo's other addons.

| File | Responsibility |
|---|---|
| `RankUp.toc` | Manifest. `Interface: 11509, 16001`, `IconTexture`. No `SavedVariables`: there is nothing to remember. |
| `RankUp.lua` | Namespace, `ns.Print`, events, `/rankup`, holding a look until combat ends |
| `Ranks.lua` | Reading only: the slots, what is in them, and the outdated groups. No frames. |
| `Swap.lua` | The swap above, and the report after it |
| `Popup.lua` | The frame: the list, Upgrade, Not now, combat disabling |

Plus `README.md`, and a row for RankUp in the root README's table.

`Ranks.lua` asks the client and has no frames, so its answers can be tested
without one: the same split as ClickHeal's `Spells.lua`. Every lookup tries
the `C_Spell` call first and the old global second, because this client moved
`GetSpellInfo` into `C_Spell` without warning (ClickHeal, `Spells.lua`).

```
Ranks.Slots()     -- every action slot number this client uses
Ranks.Outdated()  -- { { name, fromRank, toRank, toID, slots = { 3, 75 } }, ... }
                  -- sorted by name; empty when every button is current
```

## Checked before code

None of this is checked on the Forever client yet. Before any code, Carl
runs `/run` lines in game, with an old rank on a button, and the answers go
into this section:

1. `GetActionInfo(slot)` on that button gives `"spell"` and the old rank's
   own spell ID, not the top rank's.
2. `C_Spell.GetSpellInfo(name)` (or `GetSpellInfo`) gives the top rank's ID,
   and `GetSpellSubtext` gives "Rank N" for both.
3. Which of `C_Spell.PickupSpell` / `PickupSpell` and `PlaceAction` exist,
   and the highest slot `HasAction` is true for with bars 2 to 8 on.
4. One swap by `/run`, then a fight: the bars still work and no "Interface
   action failed" appears.
5. Which event fires when a spell is learned at the trainer.

If 4 fails, addon code cannot safely place spells on this client, and the
design goes back to Carl before any code is written.

## Testing

Lua specs, with the runner, helpers and stubbed client from FishScale, one
spec per file:

- **Ranks:** an old rank is listed with its old and new rank text; two
  buttons of one spell share a group; items, macros, empty slots and
  one-rank spells are not listed; the `C_Spell` and global routes both work.
- **Swap:** every listed slot gets the new ID; nothing happens in combat; a
  fight starting halfway stops it; a slot that did not change is reported.
- **Popup:** never opens in combat, and a look held by combat opens it when
  combat ends; Upgrade disables in combat and comes back after; Not now
  closes it until the next look.
- **Events:** login and learning a spell look; a changed button does not;
  `/rankup` with nothing outdated says so.

In game: the probe above, then train a rank (or drag an old one from the
spellbook with all ranks shown) and see the popup and the swap.

## Out of scope

Macros (`/cast` without a rank already casts the top one), pet bars (they
update themselves), keeping chosen low ranks, settings, saved positions.
