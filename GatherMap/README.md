# GatherMap (World of Warcraft AddOn)

Pins on the world map and the minimap for every vein you have mined and every
herb you have picked, so you can find your way back. Nothing else: no
database of spawns, no guesses.

## How it records

Mine or pick as usual. When a loot window opens from a herb or vein,
GatherMap saves the spot where you stand. It knows about 75 kinds of herb and
vein by name; anything else you gather straight after a Mining or Herbalism
cast is saved too, named after what it dropped. A vein you mine three times
counts once per visit. Saved per account, so every character adds to the
same map.

Hover a pin for what grows there, the skill it needs (in its skill-up
colour) and how often you have gathered there. **Shift-right-click** a pin to
forget that place. A left click or a plain right-click on a world map pin
does what it would on the map itself.

## Filters

Each has a box for the world map and one for the minimap, in `/gmap`:

- Show pins on this map: turn the world map's or the minimap's pins off
  on their own.
- Herbs, ore; open a kind with **+** to pick its nodes one by one, or
  **All** / **None**.
- Hide nodes your skill cannot gather yet (on by default).
- Hide grey nodes, the ones that give no more skill-ups.
- Pin size.

If you have collapsed the Professions header in your skill list, GatherMap
keeps the skills it last saw until you open it again.

## Commands

| Command | What it does |
|---|---|
| `/gmap` | Open the settings |
| `/gmap toggle` | Show or hide every pin |
| `/gmap toggle map` | Show or hide the world map's pins |
| `/gmap toggle minimap` | Show or hide the minimap's pins |
| `/gmap minimap` | Hide or show the minimap button |
| `/gmap where` | Where the game and GatherMap put you on the map |
| `/gmap debug` | What GatherMap has, step by step, if pins are missing |
| `/gmap reset gathered` | Forget every place you have gathered (asks first) |
| `/gmap help` | List the commands |

The minimap button: click to show or hide every pin, Shift-click for just
the minimap's pins, right-click for the settings, drag to move it.

## Install

    .\package.ps1 GatherMap -Install

See the [repo README](../README.md) for packaging and test commands.
