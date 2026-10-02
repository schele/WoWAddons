# RankUp (World of Warcraft AddOn)

When you train a new rank of a spell, the game leaves the old rank on your
action bars. RankUp notices, asks, and puts the new rank on every button that
still holds an old one.

```
 Healing Touch: Rank 4 -> Rank 5 (2 buttons)
 Rejuvenation: Rank 2 -> Rank 3 (1 button)
            [ Upgrade ]  [ Not now ]
```

## When it asks

- When you log in, if any button holds an older rank.
- A moment after a trainer teaches you a spell.
- When you type `/rankup`. With nothing to change, it says so in chat.

Moving buttons yourself never brings it up: an old rank you drag onto a bar
stays there until the next login, the next spell you learn, or `/rankup`.

**Upgrade** puts the highest rank on every listed button and says in chat
what it changed, naming any button the game would not change. **Not now**, or
Escape, closes it until the next time it looks.

## What it changes

Every spell button on every bar: the main bar, Bars 2 to 8, and the bars a
druid's Bear and Cat Form switch to. **Every rank** of a spell is upgraded,
including a low rank kept on purpose to save mana.

Items, macros and spells with a single rank are never touched. A macro such
as `/cast Healing Touch`, with no rank, already casts your highest one.

## Combat

The game does not let an addon change a bar during combat, so RankUp waits:
the popup does not open until the fight is over, and its Upgrade button is
greyed out while one is on. A fight that starts partway through an upgrade
stops it, and the popup lists what is left once the fight ends.

## Install

1. Copy this folder into your client's `Interface/AddOns` as `RankUp`, so the
   result is `.../Interface/AddOns/RankUp/RankUp.toc`.
2. Restart the client and enable RankUp from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 RankUp -Install

See the [repo README](../README.md) for packaging and test commands.
