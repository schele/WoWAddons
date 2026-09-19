# Healclick (World of Warcraft AddOn)

A row of spell buttons beside every member of your party, so healing,
dispelling or buffing someone is one click on a button that already knows who
it is for.

Blizzard's party frames make you target first and cast second. Healclick
removes the targeting step.

```
 (o) Skyler    ████████░░   [Regr][Reju][ RC ][ MW ]
 (o) Borgir    ████░░░░░░   [Regr][Reju][ RC ][ MW ]
 (o) Nimue     ██████░░░░   [Regr][Reju][ RC ][ MW ]
```

(Sketched here as text because this is a text file. In game each box normally
shows the spell's own icon — see "Icons, and assigning spells" below for when
it does not.)

A slot holds any spell you can cast on a friendly unit, so a dispel is not a
special case: Remove Curse, Cleanse and Abolish Poison go in a slot exactly
like Regrowth does. So do buffs — Thorns, Mark of the Wild. Every row shows
the same slots, so slot 3 is the same spell whether it is on your own row or
party member 2's — only who it is cast on changes.

A row dims when the person is dead or offline, because clicking a heal on
them burns a global cooldown and gives you nothing back. It dims for being
out of range too, but only on a client willing to tell an addon that — some
will not, and Healclick does not guess: on a client that stays quiet about
range, it would rather leave a row bright than risk dimming one you could
actually heal.

## Icons, and assigning spells

A button shows the spell's real in-game icon whenever the client can produce
one. If it cannot — an unusual spell, or an older client missing the lookup —
the button falls back to a short text tag instead: the spell's first four
letters if its name is one word (`Regrowth` becomes `Regr`), or one letter per
significant word if it is more than one (`Remove Curse` becomes `RC`, `Mark of
the Wild` becomes `MW`, skipping small connecting words like "of" and "the").
You should rarely see the text version — it exists so a button is never
blank, not as the normal look of one.

There are three ways to put a spell in a slot, and they store the same thing:

- **Drag it there.** Pick up a spell from your spellbook and drop it on any
  button. The slot it lands in takes that spell, on every row. Out of
  combat the button's icon updates right away. Mid-fight it does not: the
  spell is saved, but the button — icon, cast target, everything about it —
  is left exactly as it was until the fight ends (see "What it cannot do,
  and why" below). A healer who drags a replacement heal onto a button
  mid-fight will see nothing happen, and that is expected, not a dropped
  click.
- **Click it there.** Click a spell in your spellbook to pick it up instead
  of dragging it, then click a button — no click-and-hold needed. Out of
  combat this assigns the spell exactly as a drag does. Mid-fight it does
  not, and not merely by being held: the game will not let Healclick
  intercept that click at all, so it falls through to an ordinary click
  instead — the button casts whatever spell it already had, on that party
  member, and the spell you picked up is left sitting on your cursor for
  you to place once the fight is over.
- **Type it.** Open `/hc settings` and type the spell's name into that slot's
  row under Spells. The same out-of-combat/mid-fight split as dragging
  applies here too.

Dropping something that is not a spell — an item, a macro — onto a button
does nothing: the button is unchanged and whatever you were carrying stays
exactly where it was, on your cursor.

Clicking a button while carrying one of those is different, not nothing:
Healclick has no way to tell that click apart from an ordinary one, so the
button casts normally, on whoever its row is for, while the item or macro is
left sitting on your cursor, unplaced, for you to deal with afterward.

A spell you have not learned yet is kept, not rejected — setting up the Remove
Curse you get at level 24 is sensible, not a typo. Healclick says so once and
keeps it.

## What it cannot do, and why

**Addon code cannot cast a spell in this game.** Casting on a unit is
protected: the only route is one of Blizzard's secure buttons carrying "cast
*this* on *that unit*", which **you** click. Healclick sets those attributes;
the game does the rest.

Three consequences you will notice:

- **Changes take effect out of combat.** Editing a spell — by typing or by
  dragging — changing the number of buttons, or moving your own row to the
  bottom is held until the fight ends. The game refuses those changes
  mid-fight, so Healclick waits rather than putting an error on your screen.
  Picking a spell up and clicking a button, rather than dragging it, is the
  exception: mid-fight the game will not even let Healclick suppress that
  click, so instead of holding the assignment for later it lets the click
  through as an ordinary cast and leaves the spell on your cursor — see
  "Icons, and assigning spells" above.
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
- `/hc lock` - Stop the frame being dragged
- `/hc reset` - Put the frame back in the middle
- `/hc settings` - Open the settings panel

## Settings

| Setting | Does |
|---|---|
| Buttons per player | How many slots each row shows, 1 to 8 |
| Put my row at the bottom | Whether you sit above the party or below it |
| Spells | One row per slot. Type a spell's name, or assign it from a row's button instead — drag a spell onto one, or click it up in the spellbook and click the button (see "Icons, and assigning spells" above) |
| Lock the frame | Stops the bar being dragged by accident |

Slots are seeded with a starting set the first time you log in, for four
classes: Druid (Regrowth, Rejuvenation, Remove Curse, Mark of the Wild),
Priest (Flash Heal, Renew, Dispel Magic, Power Word: Fortitude), Paladin (Holy
Light, Flash of Light, Cleanse, Blessing of Might) and Shaman (Healing Wave,
Lesser Healing Wave, Cure Poison, Lightning Shield). Any other class starts
with every slot empty — fill them by typing or dragging, same as anyone else
would to change a seeded slot. A slot you deliberately empty afterward stays
empty; it is seeded once, not refilled at every login.

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
