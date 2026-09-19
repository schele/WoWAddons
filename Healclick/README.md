# Healclick (World of Warcraft AddOn)

A row of spell buttons beside every member of your party, so healing,
dispelling or buffing someone is one click on a button that already knows who
it is for.

Blizzard's party frames make you target first and cast second. Healclick
removes the targeting step.

By default the buttons hang off Blizzard's own unit frames, so a row of icons
sits beside the person it casts on:

```
 (O) Skyler Aldira   [Reju][ MW ]
     122/122
     194/194

 (O) Iuna Tic        [Reju][ MW ]
     73/73
     90/90
```

If your UI has no party frames to hang from — raid-style party frames replace
them, and so do most unit-frame addons — Healclick falls back to a bar of its
own, which draws the names and health itself and can be dragged anywhere:

```
 Skyler    ████████░░   [Reju][ MW ]
 Borgir    ████░░░░░░   [Reju][ MW ]
 Nimue     ██████░░░░   [Reju][ MW ]
```

You can also choose the bar outright — see Settings. (Sketched as text because
this is a text file; in game each box shows the spell's own icon.)

A slot holds any spell you can cast on a friendly unit, so a dispel is not a
special case: Remove Curse, Cleanse and Abolish Poison go in a slot exactly
like Regrowth does. So do buffs — Thorns, Mark of the Wild. Every row shows
the same slots, so slot 3 is the same spell whether it is on your own row or
party member 2's — only who it is cast on changes.

A whole row fades when the person is dead or offline, because every spell on
it is useless at once. Being out of range is judged per icon instead, since a
40-yard heal and a melee-range debuff do not share a reach — the icons that
cannot land go dark while the rest stay lit.

Both depend on the client being willing to answer, and some are not: range in
particular comes back on some clients as a value an addon is not allowed to
read. Healclick does not guess. Where it cannot tell, it leaves the icon lit,
because being told a spell is out of reach when it is not costs you a cast you
had.

Under each icon is how long your own copy of that spell has left on that
person — 7s of Rejuvenation ticking down on one party member, 38m of Mark of
the Wild on another. Blank means it is not on them, which is the signal to
click. It depends on the client being willing to say, on the same terms as
range above.

Buttons show the cooldown sweep, the same one the action bars draw — including
the global cooldown, so a click gives you the feedback you expect.

## Icons, and assigning spells

A button shows the spell's real in-game icon. A slot holding a spell you have
not learned yet shows no button at all, and the icons either side close up
around the gap — so the Remove Curse you set up for level 24 simply appears,
in its slot, the moment you learn it.

That only applies to spells the client will not draw an icon for because you
cannot cast them. A spell you *can* cast but whose icon cannot be looked up
keeps its button and shows a question mark, so a client with a missing lookup
costs you a picture rather than the button.

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
- **Pick it.** Open `/hc settings` and press **Pick** beside a slot. The list
  offers every spell you know that can be cast on a friendly target, so
  passives, attacks and professions stay out of it — as does any spell
  another slot already holds, since two buttons casting the same thing is one
  button wasted. Its first entry empties the slot. Click anywhere else to
  close the list without choosing. The same out-of-combat/mid-fight split as
  dragging applies here too.

  There is no longer anywhere to type a spell's name, which costs the one
  thing typing could do that picking cannot: setting up a spell you have not
  learned yet. A seeded slot can still hold one, and the panel goes on
  showing it — the picker simply will not offer it until you learn it.

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
- `/hc lock` - Stop the bar being dragged
- `/hc reset` - Put the bar back in the middle
- `/hc settings` - Open the settings panel
- `/hc debug` - Print what happens when a spell button is clicked, for
  working out why one is not casting

`lock` and `reset` are about the addon's own bar. Attached to the unit
frames there is nothing to drag: the frames decide where the icons go, and
the two offsets in Settings nudge them from there.

## Settings

| Setting | Does |
|---|---|
| Buttons per player | How many slots each row shows, 1 to 8 |
| Icon size | How big each spell icon is, 12 to 48. Blizzard's own action buttons are 36; these default to 22 because five rows of them sit beside five unit frames |
| Sit beside the party frames | On by default. Hangs the icons off Blizzard's unit frames. Turn it off for the addon's own draggable bar. Falls back to the bar by itself if your UI has no party frames |
| Distance from the frame | How far right of the unit frame the icons sit. Negative puts them on the left |
| Height against the frame | How far above the middle of the unit frame the icons sit. Negative puts them below |
| Show my own icons | Off by default. Turn it on to get a row beside your own frame as well as the party's |
| Put my row at the bottom | Whether you sit above the party or below it. Only affects the bar — attached, the unit frames decide the order |
| Spells | One row per slot. Type a spell's name, or assign it from a row's button instead — drag a spell onto one, or click it up in the spellbook and click the button (see "Icons, and assigning spells" above) |
| Lock the frame | Stops the bar being dragged by accident. Only affects the bar |

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
