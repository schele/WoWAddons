# FishScale (World of Warcraft AddOn)

One key for the whole fishing loop: cast, pick up the bobber, recast.

| When | The key |
|---|---|
| No line out | Casts Fishing |
| Bobber out | Picks up the bobber |
| Loot window open | Does nothing, so it cannot recast over your loot |

With auto loot on, which FishScale turns on for you while you fish, the loop
is: press, wait for the splash, press, press.

## Why not recast by itself?

The game only lets a spell go off from your own key press or click. An addon
that cast by itself would be a fishing bot, and Blizzard blocks exactly that,
so nothing can recast for you. What FishScale does is make every step the same
key.

## When it takes the key

Only while a fishing pole is in your main hand, and never in combat. The
moment a fight starts, the key goes back to whatever it normally does, and
FishScale takes it again when the fight ends. Unequip the pole and the key is
yours again.

If your client lets you fish without a pole, `/fs nopole` makes FishScale take
the key regardless.

## Settings it changes while you fish

All of these go back to how they were as soon as FishScale lets go of the key.

| Setting | Set to | Why |
|---|---|---|
| Soft target interact | On for everything | Lets the interact key find the bobber without you clicking it |
| Soft target interact range | 30 yards | A cast lands further out than the default range |
| Auto loot | On | So picking up the bobber puts the fish straight in your bags. `/fs autoloot` turns this off |

## Commands

| Command | Does |
|---|---|
| `/fs key F` | Set the fishing key. Anything the game accepts as a binding: `F`, `SHIFT-F`, `BUTTON4` |
| `/fs on` / `/fs off` | Turn FishScale on, or off and give the key back |
| `/fs nopole` | Take the key even without a fishing pole equipped |
| `/fs autoloot` | Toggle turning auto loot on while fishing |
| `/fs status` | Show what the key is doing right now |

The key defaults to `F`.

## Install

1. Copy this folder into your client's `Interface/AddOns` as `FishScale`,
   so the result is `.../Interface/AddOns/FishScale/FishScale.toc`.
2. Restart the client and enable FishScale from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 FishScale -Install

See the [repo README](../README.md) for packaging and test commands.
