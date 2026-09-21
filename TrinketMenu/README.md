# TrinketMenu (World of Warcraft AddOn)

Every trinket you are carrying, on a bar. Left-click one to equip it in
trinket slot 1, right-click for slot 2.

```
 [Badge][Heart][DHK][Zandalarian]
```

No more digging through bags to find the trinket you want, or opening the
character pane to swap it in. TrinketMenu puts every trinket you own — worn or
not — on one bar, and a click equips it.

## How a click maps to a slot

Each button carries both slots at once: left-click runs
`/equipslot 13 <trinket>`, right-click runs `/equipslot 14 <trinket>` — 13 and
14 being the game's own trinket slots. Which one a click lands in is entirely
up to you; TrinketMenu does not decide it for you and does not care what is
already there. Equipping over a full slot works exactly as it does from your
bags: the trinket that was in it comes off, into your bags — see "What is on
the bar" below.

The two trinkets you are already wearing get a gold wash over their icon, so
you can tell at a glance what is on before you click anything.

## What it will not do, and why

**TrinketMenu only equips.** It does not fire your trinket's on-use effect, and
it does not touch any slot but the two trinket slots — not your weapon, not
your armor, nothing else in your bags.

Both are the same reason: **addon code cannot use an item or cast a spell in
this game.** Using an item, like casting a spell, is protected — the only
route is a secure button that says "do *this*", which **you** click.
TrinketMenu's buttons say "equip this trinket", nothing more. A separate click
on the trinket once it is on you is what fires its effect, same as it always
has.

Restricting itself to the two trinket slots is a choice, not a limit of the
same kind: a bar that could put a ring on your finger or a sword in your hand
is a different, much bigger addon. TrinketMenu does one job.

## What combat changes

**Changes take effect out of combat.** Equipping a trinket by clicking still
works mid-fight — that part is an ordinary secure click, same as any action
bar button. What does not work mid-fight is anything that would create or
re-point a button:

- **A trinket looted mid-fight does not get a button until the fight ends.**
  Every button TrinketMenu will ever need is built at login, before you can be
  in combat, but pointing an unused one at a freshly-looted trinket is a
  secure write, and the game refuses that mid-fight the same as anything else.
  The bar catches up the moment combat ends.
- **`/tm reset` is held until combat ends**, then puts the bar back in the
  middle the instant you leave the fight — moving it is the same secure write
  as anything else here.
- **Starting a drag while you are already in combat is refused outright, not
  queued.** Moving the anchor would move every secure button hanging off it,
  so the game blocks the drag before it begins and TrinketMenu says so in chat;
  let go and the bar has not moved.
- **A drag already underway when combat starts is not cut short, and dropping
  it mid-fight works exactly as it would outside one.** Only moving the bar's
  frame is a secure write; letting go of the mouse is not, so the new
  position is saved the instant you release it — the bar is exactly where you
  dropped it, combat or not.
- **`/tm lock` takes effect immediately, combat or not.** It flips a plain
  setting rather than touching the bar itself, so there is nothing for combat
  to hold.

TrinketMenu prints when it refuses to start a drag or holds a reset, so a bar
that did not move is not left unexplained.

## What is on the bar

The bar shows what you are **carrying** — bags and both trinket slots
together, one button per trinket, sorted alphabetically. It is not a fixed
loadout: swap a trinket in and the one that comes off the character pane
appears on the bar too, because it is now sitting in your bags like any other
trinket. Two copies of the same trinket collapse into one button, since
equipping either one does the same thing.

If a trinket you are carrying does not show up right after logging in, give it
a moment — some clients have not looked up its icon yet, and the bar catches
up as soon as they do.

On a client that cannot read your bags at all, TrinketMenu says so once in
chat — *"This client will not let me read your bags, so the bar shows only
what you are wearing."* — and falls back to showing only the two trinkets you
have equipped.

If your bags can be read but one particular trinket cannot, that one trinket
is left off the bar instead — everything else you are carrying still shows,
and TrinketMenu says so with a different line: *"This client would not read
some of what you are carrying, so the bar may be missing a trinket."* Each of
these two messages prints once, not every time your bags change; if you see
either one, it is not a bug, it is what this client will let TrinketMenu do.

## Install

1. Copy this folder into your client's `Interface/AddOns` as `TrinketMenu`, so
   the result is `.../Interface/AddOns/TrinketMenu/TrinketMenu.toc`.
2. Restart the client and enable TrinketMenu from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 TrinketMenu -Install

See the [repo README](../README.md) for packaging and test commands.

Built against Classic Era 1.15.x (`11509`) and the 1.60.x Classic beta
(`16001`).

## Commands

`/trinketmenu` or the short `/tm`:

- `/tm` - Show the command list
- `/tm lock` - Stop the bar being dragged
- `/tm reset` - Put the bar back in the middle
- `/tm settings` - Open the settings panel

## Settings

`/tm settings` opens a panel with a gem beside the title and four settings,
each of which takes effect as you move it:

| Setting | Does |
|---|---|
| Icon size | How big each trinket icon is, 12 to 48 |
| Buttons per row | How many icons sit side by side before the bar wraps onto another row, 1 to 16 |
| Lock the bar | Stops the bar being dragged around by accident |
| Hide the backdrop | Hides the faint square behind the bar. On by default |

## Tests

The item lookups, the button pool, the layout and the combat queue are
covered by unit tests that run outside the game against a stubbed WoW API
(`tests/wow_stub.lua`).

From the repo root:

```powershell
.\run-tests.ps1 TrinketMenu
```

Or a single suite by hand, from this folder:

```
lua tests/runner.lua tests/bar_spec.lua
```

What the tests prove is that TrinketMenu asks for the right thing: that the
button for Hand of Justice carries `macrotext1="/equipslot 13 Hand of
Justice"`. Whether the client honours it is something only the client can
answer.
