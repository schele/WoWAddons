# StealthWatch (World of Warcraft AddOn)

Warns you when an enemy player near you goes into stealth: a warning sound,
the spell and who cast it in red in the middle of the screen, and a line in
chat.

## What it notices

StealthWatch watches every enemy player who has a nameplate on your screen,
and your target.

- **A stealth spell the game names.** Stealth, Vanish, Prowl, Shadowmeld,
  Lesser Invisibility or Invisibility (any rank) sets it off at once:
  *Vanish: Sneaky, Rogue*.
- **Someone who casts something instant and is gone a moment later.** WoW
  Forever hides which spell other players cast, so most of the time the
  game will not say "Vanish". What it does show is an enemy casting an
  instant spell and then dropping out of sight within a second and a half,
  still alive. That is what going into stealth looks like from outside, so
  that counts too: *Stealth: Sneaky, Rogue*, and in chat "went out of sight
  right after an instant cast: likely stealth".

Things that do not set it off: someone walking or riding out of range (no
cast), a hearthstone or a mage's teleport (they have a cast time), a spell
the game names that is not stealth (a mage's Blink), someone dying, players
on your own side, and NPCs.

The same player sets it off at most once every 10 seconds.

## What it cannot do

- **See someone already in stealth.** Nobody can, short of the game showing
  them to you. StealthWatch catches the moment they go in.
- **See past your nameplates.** It sees enemy players only while their
  nameplates are on screen, so turn enemy nameplates on (V by default). How
  far nameplates reach is how far StealthWatch sees. With them off, it only
  sees your target, and it says so when you log in.
- **Read the combat log.** On WoW Forever the combat log is closed to
  addons, which is why it works from nameplates instead.

## Settings and commands

It has a page in the game's options (Options, AddOns, StealthWatch): a box
each for the sound, the text on screen and the chat line, a Test button, and
whether enemy nameplates are on. The page lists the stealth spells it watches
for, by the names this client gives them.

| Command | What it does |
|---|---|
| `/sw` | Open the settings page |
| `/sw test` | Show what an alert looks like |
| `/sw probe` | Say what this client lets StealthWatch see: enemy nameplates and their range, the stealth spells it knows, whether it hides other players' casts of each, and how many casts it has heard named and hidden since login |
| `/sw help` | List the commands |

## How it works

On WoW Forever, Blizzard moved reading the combat log into its own secure
code. Addons cannot read the combat log there, and the client hides the
spell in another unit's cast events ("secret" values). Who an enemy player
is (their name, class, race and level) is not hidden, and the cast event
itself still fires. StealthWatch registers a frame for each enemy player's
nameplate token, and for the target. When that unit casts an instant spell
it can't read and then leaves (`NAME_PLATE_UNIT_REMOVED`, or the target
clearing), StealthWatch treats it as stealth.

Classic Era hides nothing, so there every cast is named and only real
stealth spells set it off.

Not yet confirmed in the game: that a stealthing player's cast event arrives
before their nameplate goes (the server sends the cast first, so it should).
`/sw probe` after meeting a rogue shows whether casts were heard at all.

## Install

From the repo root:

    .\package.ps1 StealthWatch -Install -NoWago

See the [repo README](../README.md) for packaging and test commands.

## Tests

The tests run outside the game against a stand-in for the client
(`tests/wow_stub.lua`) that hands out secret spell ids the way Forever does.

```powershell
.\run-tests.ps1 StealthWatch
```
