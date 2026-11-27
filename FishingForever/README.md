# FishingForever (World of Warcraft AddOn)

One key for the whole fishing loop: cast, pick up the bobber, recast.

| When | The key |
|---|---|
| No line out | Casts Fishing |
| Bobber out | Picks up the bobber |
| Loot window open | Does nothing, so it cannot recast over your loot |

With auto loot on, which FishingForever turns on for you while you fish, the
loop is: press, wait for the splash, press, press.

## Fishing a school

The game picks where your bobber lands, and no addon can aim it. When it
lands outside a school of fish, the quickest fix is a fresh line. The recast
key, Shift-F unless you change it, casts Fishing even while your line is out:
one press, where the fishing key takes two (one to pull the line in, one to
cast). Like the fishing key, it is let go over the loot window and in combat.
Set both to the same key and the fishing key wins, so you can still pick up
the bobber.

## Why not recast by itself?

The game only lets a spell go off from your own key press or click. An addon
that cast by itself would be a fishing bot, and Blizzard blocks exactly that,
so nothing can recast for you. What FishingForever does is make every step
the same key.

## When it takes the key

Only while a fishing pole is in your main hand, and never in combat. The
moment a fight starts, the key goes back to whatever it normally does, and
FishingForever takes it again when the fight ends. Unequip the pole and the
key is yours again.

## Settings it changes while you fish

All of these go back to how they were as soon as FishingForever lets go of
the key.

| Setting | Set to | Why |
|---|---|---|
| Soft target interact | On for everything | Lets the interact key find the bobber without you clicking it |
| Soft target interact range | 30 yards | A cast lands further out than the default range |
| Auto loot | On | So picking up the bobber puts the fish straight in your bags. `/ff autoloot` turns this off |

## The skill bar

The higher your Fishing, the more catches a skill point takes. While a pole is
in your hand, a small bar in two halves shows where you are. The left, in
blue, is your next point: it fills with the catches you have made since your
last point, against how many a point usually takes at your skill. The right,
in green, is your skill itself against its cap:

    ▓▓▓▓▓▓ Next point ░░░░░░│▓▓▓▓▓▓▓▓ Fishing 231/300 ░░

Click it for the numbers: the stats window's Summary has the chance a catch
brings a point ("Chance of a point per catch: 1 in 7"). The game keeps no
progress toward a point. Each catch has a chance to raise your skill, and the
chance shrinks as you go up, so the left half is a count against an average,
not a promise. With bad luck it stays full and the count goes on.

A half only shows while it has something to tell you:

- While every catch raises your skill, which is the case up to 75, the next
  point is always the next catch, so only your skill shows, across the whole
  bar.
- Where your skill is too low for the water (below), the left half says "too
  low here" in red, whatever your skill.
- At a trainer's cap, the left half says "capped" and both go grey: time to
  train.
- At 300, the highest rank, there is nothing left to fill, so the bar is only
  `Fishing 300/300`. A click on it still opens your stats. Only a "too low
  here" brings the halves back, in grey.

The average starts as the old game's rule: every catch below 75, then a chance
of 2500 / (skill - 50) in a hundred, about 1 in 4 at 150 and 1 in 10 near 300.
That is a guess for WoW Forever. FishingForever notes how many catches each
of your points took, and once it has measured five points near your skill, it
uses those instead. Hover over the chance in the stats window to see which
you are seeing. The count is kept for each character, and carries over a
logout.

Drag the bar to move it. Its options page has boxes to hide it and lock it in
place, and a button to put it back under the middle of the screen.

### Where you fish

Every zone has a Fishing minimum, and WoW Forever holds you to it in two
ways. Far below it the game refuses the cast ("Skill not high enough"): a
level 55 zone did at 106. Nearer, it lets you cast but every fish gets away
("Your fish got away!"): Stranglethorn Vale did at 155. Above it, some fish
still get away now and then. A fish that gets away gives no point, so where
many do, a point takes more casts.

The old game had a hundredth more fish land for each point of skill, until
every fish did. Whether WoW Forever does is not known yet: in Hillsbrad
Foothills 92% landed at 126-129, 94% at 130-139 and every one from 140, too
few casts to tell its rule. So FishingForever predicts nothing here; it
counts. Once it
has seen ten of your casts in a zone, the stats window's Summary says what
share of them landed a fish there, the same share as its rows. Where so many
fish get away that a point takes more casts than catches, it says how many
casts too.

The bar's left half says "too low here", and the Summary says why in red, where the game
refused your cast at your skill or above, or where every fish of five casts
or more at your skill or above got away. It clears when your skill rises past
those, or when a fish lands there.

A lure or fishing gear counts for landing a fish and for a zone's minimum, by
the old game's rule, so FishingForever measures those at your skill with the
bonus. Points still go by your own skill.

## Your fishing stats

Click the skill bar to open your fishing stats (or `/ff stats`, or the box on
the options page). The window opens around the bar, which moves inside it,
across the top, without moving on the screen. Another click on the bar, or
the red X, closes it and leaves the bar on its own where it was; dragging
either moves both. It shows one zone at a time, the one you are fishing in,
with page arrows to turn to the others:

    [=========== Fishing 129/150 ================]
    <       Hillsbrad Foothills (20-30)        >
        48         6          2         89%
      Caught    Got away   Refused     Landed
    Skill    Caught  Got away  Refused  Landed
    130-137      26         2        0     93%
    120-129      22         4        0     85%
    Summary
      Chance of a point per catch       1 in 3
      Fish that land here                  94%
    Fish caught here
    [icon] Oily Blackmouth                  ×20
    [icon] Raw Rainbow Fin Albacore         ×15

A row covers ten skills, on round numbers (120-129, 130-139), from the
lowest to the highest you fished at in it. Landed is the share of casts that
landed a fish rather than having it get away. The zone's level is coloured
as the world map colours it against your level, where the game gives the
zone one. The row you are in now is gold, and noughts are grey. Hover over a
row for how many catches each of its points took, next to what the old
game's rule says, and for the fish caught in it, the subzones, any lure's
bonus and your character's level; hover over a fish for its tooltip. The
mouse wheel scrolls through the rows.

Behind the stats is a log of every cast that ended, kept for the account (the
newest 10,000): when, which character at what level, the Fishing skill, its
cap and any bonus, the zone, its level range, the subzone and where in it,
how the cast ended (caught, got away, refused), the fish, and whether it
brought a point. It is in
`WTF/Account/<account>/SavedVariables/FishingForever.lua` after a `/reload`
or logout: send it in to help work out WoW Forever's fishing rules.

## Settings

FishingForever has a page in the game's options (Esc, Options, AddOns,
FishingForever): turn it on or off, set the fishing key by clicking the key
button and pressing the key you want (with Shift, Ctrl or Alt if you like;
Escape cancels), turn the recast key on or off and set it the same way, turn
auto loot on while fishing, and show, lock or reset the
skill bar and open the stats around it.

The minimap button opens and closes that page. Right-click it to turn
FishingForever on or off; its tooltip says which it is. Drag it to move it
round the minimap.

## Commands

| Command | Does |
|---|---|
| `/ff settings` | Open the settings page |
| `/ff key F` | Set the fishing key. Anything the game accepts as a binding: `F`, `SHIFT-F`, `BUTTON4` |
| `/ff recast` | Turn the recast key on or off |
| `/ff recast SHIFT-G` | Set the recast key, and turn it on |
| `/ff on` / `/ff off` | Turn FishingForever on, or off and give the key back |
| `/ff autoloot` | Toggle turning auto loot on while fishing |
| `/ff status` | Show what the key is doing right now |
| `/ff minimap` | Hide or show the minimap button |
| `/ff bar` | Hide or show the skill bar |
| `/ff bar lock` | Lock the skill bar in place, or unlock it to drag it |
| `/ff bar reset` | Put the skill bar back under the middle of the screen |
| `/ff stats` | Open or close your fishing stats around the skill bar |

The key defaults to `F`, and the recast key to `SHIFT-F`.

## Install

1. Copy this folder into your client's `Interface/AddOns` as `FishingForever`,
   so the result is `.../Interface/AddOns/FishingForever/FishingForever.toc`.
2. Restart the client and enable FishingForever from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 FishingForever -Install

See the [repo README](../README.md) for packaging and test commands.
