# TrinketBar Design

**Date:** 2026-09-20
**Status:** approved, pending one probe answer (see "The open question")

## Purpose

Swap trinkets without opening the character screen.

World of Warcraft gives a character two trinket slots. Changing what is in
them means opening the character sheet, finding the trinket in a bag, and
dragging it onto the right square. TrinketBar puts every trinket the
character is carrying on a bar and makes a swap one click.

## What it is

A draggable bar of trinket icons. Every trinket in the character's bags, plus
the two being worn. **Left-click equips into trinket slot 1, right-click into
slot 2.**

Nothing to configure: a trinket appears when it is picked up and goes when it
is sold. Trinkets are ordered by name, so the bar reshuffles only when the
set changes, not when bags are tidied.

## What it is not

- **Not an action bar.** Clicking never fires a trinket's on-use effect. That
  is what action bars are for, and duplicating them would make the same
  button mean two things depending on state.
- **Not a gear manager.** Trinkets only. No sets, no other slots.
- **Not configurable in what it shows.** The bar is whatever is being
  carried. There is no list to curate, because there was nothing to curate
  it *for*: a trinket in the bags is, by definition, one that might go on.

A worn trinket's button is still useful: left-clicking the one in slot 2
moves it to slot 1. That falls out of the design rather than being a case in
it.

## The constraint everything else follows from

**Addon code cannot equip.** Changing gear is protected in the same way
casting is: the reliable route is one of Blizzard's secure buttons carrying
an instruction, which **the player** clicks. This addon writes the
instruction; the game performs it.

Two consequences shape the whole design:

1. **The instruction is a macro, not an item.** A secure button with
   `type="item"` *uses* an equippable item, and the game chooses which slot
   it lands in. This bar has to say which slot. So each button carries
   `type="macro"` with `macrotext` of `/equipslot 13 <item>` or
   `/equipslot 14 <item>`.

2. **Instructions cannot be rewritten mid-fight.** Every secure write --
   attributes, showing, hiding, moving -- is refused in combat. Changes are
   held and applied when combat ends. A trinket looted mid-fight gets its
   button when the fight is over.

This is the same ground ClickHeal covers, and the same shape is used here
deliberately: a fixed pool of buttons built once, re-pointed out of combat,
with a queue for what combat refused.

## Architecture

Four files, following the repo's existing shape.

| File | Responsibility |
|---|---|
| `TrinketBar.toc` | Manifest. `SavedVariables: TrinketBarDB`, `IconTexture` |
| `TrinketBar.lua` | Namespace, defaults, `ns.Print`, `ns.Guarded`, the settings registry, slash commands |
| `Items.lua` | What the client knows about items. Pure lookups: no frame, no layout |
| `Bar.lua` | The frame: button pool, layout, drag anchor, combat queue, events |
| `Settings.lua` | A small panel: three settings |

The split matters in one specific way: `Items.lua` asks the client things and
has no frames in it, so its answers can be tested without one. That is what
made `Spells.lua` testable in ClickHeal, and it is the same trade here.

### `Items.lua`

Every function tries the namespaced API, then the legacy global, then gives
up -- the pattern `Spells.lua` already uses, for the reason it already
exists: this client family moved `GetSpellInfo`, `GetSpellBookItemName` and
the party frames out from under an addon in one week.

```
Items.TRINKET_SLOTS   -- { 13, 14 }, or INVSLOT_TRINKET1/2 where present

Items.Carried()       -- { { name, link, texture, bag, slot }, ... }
                      -- every trinket in the bags, sorted by name

Items.Worn()          -- { [13] = { name, link, texture }, [14] = ... }
                      -- nil for an empty slot

Items.All()           -- one list, sorted by name, of the worn and the
                      -- carried together; a worn entry carries `wornSlot`

Items.Cooldown(entry) -- start, duration -- or nil
```

**Walking the bags.** Bags `0` through `NUM_BAG_SLOTS` (4 where the constant
is absent). For each slot, the item's link, then its equip location:
a trinket is one whose location is `INVTYPE_TRINKET`.

**Identifying by name.** The macro says `/equipslot 13 <name>`, so the name
is what matters, not the bag position -- which means a trinket that moves
between bags keeps working without a rebuild.

**Two of the same trinket** collapse to one entry. `/equipslot` takes the
first match, and two identical icons side by side say nothing a healer can
act on.

### `Bar.lua`

**The pool.** `MAX_BUTTONS = 16` secure buttons, created once, out of combat.
Sixteen is past what anyone carries; the cost of a hidden button is nothing,
and a button that cannot be created mid-fight is one the bar cannot grow.

**Per button, written only out of combat:**

```
type1      = "macro"
macrotext1 = "/equipslot 13 " .. name
type2      = "macro"
macrotext2 = "/equipslot 14 " .. name
```

`RegisterForClicks("AnyUp", "AnyDown")`. Both edges, because this client acts
on the press where others act on the release -- a fact that cost ClickHeal
several rounds to find, recorded here so it costs this addon none.

**Layout.** Buttons wrap into rows of `buttonsPerRow`, left to right, top to
bottom. Sixteen in a line is wider than most screens.

**The anchor.** One draggable frame with a faint backdrop, as ClickHeal's
standalone bar has: `/tb lock` stops it moving, `/tb reset` puts it back in
the middle, and its position is saved.

**Events:**

| Event | Does |
|---|---|
| `PLAYER_LOGIN` | Build the pool, then apply |
| `BAG_UPDATE_DELAYED` | Re-read the bags and re-point the buttons |
| `PLAYER_EQUIPMENT_CHANGED` | Re-point, and re-mark which are worn |
| `BAG_UPDATE_COOLDOWN` | Redraw the sweeps |
| `PLAYER_REGEN_ENABLED` | Run whatever combat held |

`BAG_UPDATE_DELAYED` rather than `BAG_UPDATE`: the latter fires once per bag
per change, and re-pointing sixteen secure buttons five times for one looted
item is work nobody asked for.

## What a button shows

- **The trinket's own icon.** No text fallback: an icon is how a trinket is
  recognised, and one that cannot be drawn is one the client could not
  identify in the first place.
- **The cooldown sweep**, the same widget the action bars use, drawn from
  `Items.Cooldown`.
- **A marker on the two being worn.** Without it the bar says what could go
  on but not what is on, and the swap is blind -- which defeats the purpose.
  A gold border, matching the picker's "this is the current one" marker.
- **A hover highlight**, so the cursor says what it is over.

## Settings and commands

| Setting | Does |
|---|---|
| Icon size | 12 to 48, defaulting to 24 |
| Buttons per row | 1 to 16, defaulting to 8 |
| Lock the bar | Stops it being dragged by accident |

`/trinketbar`, short `/tb`:

- `/tb` -- list the commands
- `/tb lock` -- stop the bar being dragged
- `/tb reset` -- put the bar back in the middle
- `/tb settings` -- open the panel

A bare `/tb` lists commands rather than doing anything, matching `/fp`,
`/url` and `/ch`. Four addons whose login lines sit together must not
disagree about this.

The panel is written for this addon rather than copied from ClickHeal's.
Three settings need a checkbox, two sliders and a heading; they do not need
the spell tables, key tables, columns and pickers that panel carries.

## Degrading

Every read is guarded, and every failure costs a feature rather than the
addon:

| When | Then |
|---|---|
| The bags cannot be walked | The bar shows the worn two and says so once |
| An item's equip location cannot be read | It is not treated as a trinket |
| A cooldown cannot be read | No sweep on that button |
| A read comes back as a secret value | Treated as unreadable, via `ns.Guarded` |
| The player is in combat | The change is held, not attempted |

Nothing here prints twice. A message that repeats every `BAG_UPDATE` is
worse than the fault it reports.

## Testing

The harness the other three addons use: a stubbed WoW API in
`tests/wow_stub.lua`, specs per file, run by `run-tests.ps1`.

The stub must model, because each has already hidden a defect in this repo
when it did not:

- **Bags** -- a table of bags and slots holding item links
- **Items** -- link to name, equip location, texture
- **Worn slots** -- 13 and 14, readable and changeable
- **Combat** -- refusing `SetAttribute`, `SetPoint`, `SetSize`, `Show` and
  `Hide` while it is on
- **Both API spellings** -- namespaced by default, with a test staging the
  legacy globals itself
- **Mouse enablement and draw layers** -- a frame that takes no mouse takes
  no click, and nothing else about it looks wrong

**What the tests prove** is that the bar asks for the right thing: that
button 3 carries `macrotext1 = "/equipslot 13 Kiss of the Spider"` and that
nothing is written while combat is on. Whether the client honours it is
something only the client can answer -- which is what the probe is for.

## The open question

One assumption is load-bearing and unverified: **that a secure button
carrying `/equipslot 13 <item>` equips on this client.**

A throwaway probe is installed at `Interface/AddOns/TrinketProbe`. It audits
the container, item and inventory APIs, lists the trinkets it finds, and
puts one button on screen wired exactly as the bar's buttons will be.

If the answer is no, the fallback is `type="item"` with the item's name --
which lets the game choose the slot, and collapses the left/right split into
a single button with no say in where the trinket lands. That is a materially
different product, so the answer is worth having before the bar is built.

The rest of the design absorbs whatever the API audit says, because
`Items.lua` tries both spellings of everything regardless.

## Known debt, not addressed here

Three near-identical settings panels already exist in this repo, and this
addon makes a fourth place that renders settings. A small purpose-built
panel avoids a fourth *copy*, but the duplication underneath is real and
growing. Extracting a shared panel across all four is worth doing and is its
own piece of work; folding it into this one would be smuggling.

## Global constraints

- Runtime Lua is 5.1-flavoured: no `goto`, integer division, or
  `table.unpack` in addon files. Test files run under Lua 5.4 and may.
- `run-tests.ps1` and `package.ps1` are shared; neither is modified.
- No addon file may be edited outside `TrinketBar/`.
- Comments explain *why*. No comment that restates the line below it.
- Every secure write happens out of combat or not at all.
- Every client read that could come back secret goes through `ns.Guarded`.
- Target clients: Classic Era 1.15.x (`11509`) and the 1.60.x Classic beta
  (`16001`).
