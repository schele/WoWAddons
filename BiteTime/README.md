# BiteTime (World of Warcraft AddOn)

For a druid in Cat Form: lights up your Ferocious Bite the moment a Bite, with
the combo points and energy you have, would kill your target. There is a
pulsing orange border on every action button that holds a Bite, and the Bite's
icon above the middle of the screen.

## When it lights

- **A Bite would kill.** It works out the least your Bite does from the
  game's own tooltip: the low end of the damage for your combo points, plus
  the tooltip's 0.7 damage for each point of energy over the Bite's cost.
  It lights when the target has that much health or less.
- **Counted at a share, 80% by default.** Armor takes part of a Bite's damage,
  and the glow should mean the Bite kills, not that it might. You set the
  share on the options page, from 50% to 100%. It ignores attack power, which
  only adds damage.
- **Each button by its own rank.** A button that still holds rank 1 lights by
  rank 1's numbers. The icon in the middle goes by the weakest rank on your
  bars, or by your highest rank when no Bite is on them.

It stays dark when you are out of Cat Form, have no combo points, have no
target or a dead one, or target an enemy player. The game doesn't show
addons an enemy player's health, so BiteTime only weighs mobs.

## Why there is no sound

WoW Forever hides a mob's health from addons, and its max health too. An addon
may hand those numbers to the screen but not compare them. So BiteTime doesn't
compare them: the game's own status bars do. Every piece of the glow is a
status bar. BiteTime hands it the target's health and what a Bite takes, set
up so the game draws it full when the health is at most that and empty when it
is more (`Gate.lua` explains how). So the glow lights itself. BiteTime never
learns whether it did, and a sound or a chat line would need it to know.

Classic Era hides nothing, so there it compares the health itself.

## Settings and commands

It has a page in the game's options (Options, AddOns, BiteTime). It has a box
for the button glow and one for the icon in the middle, the share slider, a
Test button, and a line saying how many of your buttons hold a Bite.

| Command | What it does |
|---|---|
| `/bt` | Open the settings page |
| `/bt test` | Light the buttons and the icon for three seconds, through the same status bars a kill lights |
| `/bt probe` | Say what BiteTime can see: your Bite's numbers as it read them, how many buttons hold it, whether the game hides your target's health, your combo points or your energy, what a Bite does now, and whether the game's bars work as BiteTime needs |
| `/bt help` | List the commands |

## Not yet confirmed in the game

- That the game's status bars compare as BiteTime needs: that a bar keeps its
  value inside its range, and that a bar whose range is nothing draws full
  with the `StandardNoRangeFill` style. `/bt probe` checks the first, and
  `/bt test` lights through both.
- That the game shows addons your combo points. It may hide them
  (`SecretWhenUnitPowerRestricted`); then nothing lights, and `/bt probe`
  says so.
- How much of the tooltip a Bite really does. The game's damage meter knows,
  out of combat, and could set the share for you later.
- On Classic Era: whether mobs' health comes as real numbers or only as a
  percentage. With a percentage it stays dark.

## Install

From the repo root:

    .\package.ps1 BiteTime -Install -NoWago

See the [repo README](../README.md) for packaging and test commands.

## Tests

The tests run outside the game against a stand-in for the client
(`tests/wow_stub.lua`). Like Forever, it hands out a mob's health and max
health as secrets that can't be compared, and draws status bars as the game
does.

```powershell
.\run-tests.ps1 BiteTime
```
