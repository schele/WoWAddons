# ThreatForever (World of Warcraft AddOn)

A window with a bar for everyone in your group on the threat list of the mob
you are fighting, filled to how close each one is to pulling aggro, and a
warning before you pull it yourself.

## The window

- **Which mob.** Your target. With a friend targeted, as a healer on the tank
  has, whatever that friend has targeted.
- **Whose threat.** You and your pet, your party or raid and their pets:
  everyone who is on that mob's threat list. Up to ten rows.
- **The bars.** Each fills to the share of what it takes to pull aggro, so a
  full bar is the tank, or someone about to take over. Each is in its class
  colour, with the percentage at the right end. The most threat comes first.
- **When.** Only in combat, out of the way otherwise. Turn "Only in combat"
  off to keep it up, for instance to drag it where you want it. Its place is
  remembered. The red X turns it off; `/threat` brings it back.

## A part for each mob

On by default: the window shows your target and the other mobs you or your
group are fighting, each in a part of its own under its name, up to three
at once. Your target comes first. The others are ordered by how close each
is to changing hands: one where someone is over the tank comes first
(which the game says even on a boss), then the one where someone not
tanking has the most threat. With nothing targeted, the mobs alone.

- One mob gets all ten rows; with more, each gets five.
- **It sees the other mobs by their nameplates**, so keep enemy nameplates
  on (V). The game gives threat on a nameplate's mob like on your target:
  the numbers, but for a boss.
- The warning covers every mob shown, not only your target.
- On the settings page: the switch **A part for each mob you fight**, and
  under it **Mobs at once**, one to five.

## The warning

The raid warning sound and "You are about to pull aggro!" in red in the
middle of the screen, when either:

- the game says you have more threat than the tank without having pulled
  yet (it still takes 110% in melee range, 130% beyond), or
- you reach 90% of what pulls while still under the tank.

Once per scare: it comes again after you drop back under 80%, on a new
target, or in the next fight. Never while you are the one tanking.

## Bosses

WoW Forever hides threat numbers from addons when the mob is a boss (the
game's `SecretWhenUnitThreatValuesRestricted`). It still says who is tanking
and who is over the tank, so on a boss:

- the bars still fill (a status bar can draw a hidden number), but the list
  cannot be sorted by them: it shows the tank, anyone over the tank, you, and
  then the group in its own order;
- where the game will not write the hidden number as text, the row says
  "Tanking" or "Over tank" instead, and the window says the game hides the
  numbers;
- the warning still comes when the game says you are over the tank, but not
  at 90%, since that needs the number.

Not yet confirmed in the game: that the numbers show on ordinary mobs as
the game's own documentation says, that a hidden number fills a bar, and
whether it can be written as text. `/threat check` says what the game shows
on your target.

## Settings and commands

It has a page in the game's options (Options, AddOns, ThreatForever): a box
each for the window, "Only in combat" and the warning, and a Test button for
the warning.

| Command | What it does |
|---|---|
| `/threat` | Turn the window on or off |
| `/threat settings` | Open the settings page |
| `/threat check` | Say what the game tells about threat on your target: whether it shows the numbers, and each one's |
| `/threat test` | Show what the warning is like |
| `/threat demo` | Show the window with made-up mobs and a party, to see how it looks out of combat or alone; again, or a fight, ends it |
| `/threat help` | List the commands |

## Install

From the repo root:

    .\package.ps1 ThreatForever -Install -NoWago

See the [repo README](../README.md) for packaging and test commands.

## Tests

The tests run outside the game against a stand-in for the client
(`tests/wow_stub.lua`) that hands out a boss's threat numbers secret, the way
Forever does.

```powershell
.\run-tests.ps1 ThreatForever
```
