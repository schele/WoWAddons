# Healclick design

Date: 2026-09-19
Status: approved, ready for an implementation plan

## What it is

A World of Warcraft addon that puts a row of spell buttons beside every member
of your party, so healing, dispelling and buffing someone is one click on a
button that names the spell and the person together.

Blizzard's party frames make you target first and cast second. Healclick
removes the targeting step: the button already knows who it is for.

## The wall, stated up front

**Addon code cannot cast a spell.** Casting on a unit is protected. The only
route is Blizzard's secure templates - a `SecureActionButtonTemplate` button
carrying "cast *this* on *that unit*" as attributes, which the **player**
clicks. Our Lua runs before and after, never instead.

Three things follow, and they shape everything below:

- A secure button's attributes cannot be changed in combat.
- A secure button cannot be shown or hidden in combat either.
- Therefore the roster cannot be re-assigned mid-fight, and any design that
  needs to is a design that does not work.

## Constraints

- Targets `## Interface: 11509, 16001` - Classic Era 1.15.x and the 1.60.x
  Classic beta, matching ForeverPanel and UrlCopy.
- The repo's layout rule: an addon is a top-level folder holding `<name>.toc`,
  and everything it needs lives inside it - Lua, tests, README. `run-tests.ps1`
  and `package.ps1` find addons by that rule and need no edit.
- `package.ps1` takes its file list from the `.toc`, so every Lua file must be
  listed there or it will not ship.
- Runtime Lua is 5.1-flavoured. Tests run under Lua 5.4.
- **Unlike the other two addons in this repo, the riskiest half of this one
  cannot be tested outside the client.** See Testing.

## Scope

**In:** party only - `player` and `party1` through `party4`. One shared bar
configuration, 1 to 8 slots, any spell you can cast on a friendly unit.

**Out, deliberately:** raid; cooldown swipes on buttons; mana or usability
colouring; HoT and buff duration tracking; debuff indicators on the frame;
dragging a spell from the spellbook onto a slot; per-unit bar customisation.

Raid is not a later feature of this design, it is a later piece of work. Forty
units with a five-slot bar each is 200 buttons, taller than a screen stacked
and wider than one in columns. It needs its own layout decision, made by
someone who is raiding and knows what they want from it. Deciding it now would
be guessing.

## Architecture

```
Healclick/
  Healclick.toc
  Healclick.lua   namespace, defaults, database, settings registry, slash commands
  Slots.lua       the spell slots - how many, what is in each. Pure data, no frames
  Row.lua         one unit's row: name, health, and its secure spell buttons
  Group.lua       the five rows, their layout, and the draggable anchor
  Settings.lua    the panel
  README.md
  tests/          runner, stub, helpers, specs
```

`Slots.lua` is to `Row.lua` what `Detect.lua` is to `Chat.lua` in UrlCopy: it
holds the decisions and touches no part of the game, so the half of the addon
that can be wrong on its own terms is testable without a client.

### Responsibilities and interfaces

**`Healclick.lua`** - the namespace every other file receives through `...`, in
the shape the other two addons established:

- `ns.PREFIX`, `ns.Print(message)`
- `ns.applyDefaults(target, source)`, `ns.AddDefaults(extra)`
- `ns.RegisterSetting(definition)`, `ns.SettingValue`, `ns.SetSettingValue`
- `ns.RegisterCommand(name, help, handler)`, `ns.RegisterHelpLine(line)`
- `ns.OnLogin(handler)`, `ns.ensureDatabase()`, `ns.db`

**`Slots.lua`** - `ns.Slots`:

- `Slots.MAX` - 8. The number of buttons built per row, regardless of how many
  are in use.
- `Slots.Count()` - how many slots are configured, 1 to `MAX`.
- `Slots.Spell(index)` - the spell name in that slot, or nil.
- `Slots.Set(index, spellName)` - stores, and returns `ok, message`. A name
  the client does not know is still stored; `message` carries the warning. An
  empty string clears the slot. Only a slot number outside 1..`MAX` returns
  false.
- `Slots.Seed(class)` - fill empty slots with a sensible starting set for that
  class, taken from `UnitClass("player")` at login. See Defaults.

**`Row.lua`** - `ns.Row`:

- `Row.Create(unit)` - builds one row's frame, health bar, name and `MAX`
  secure buttons, and returns it. Called once per unit at load.
- `Row.ApplySpells(row)` - writes the `spell` attribute on each button and
  shows or hides buttons past the configured count. **Out of combat only.**
- `Row.Refresh(row)` - health, name, class colour, and the dim state. Safe in
  combat; touches nothing secure.

### When a row refreshes

`Row.Refresh` is driven by events where the game provides one, and by a ticker
where it does not:

- `UNIT_HEALTH` and `UNIT_MAXHEALTH` - the row whose unit matches.
- `UNIT_CONNECTION`, `PLAYER_FLAGS_CHANGED` - offline and away states.
- `GROUP_ROSTER_UPDATE`, `PLAYER_ENTERING_WORLD` - every row, since names and
  classes change wholesale.
- **Range has no event.** `UnitInRange` is polled on a ticker, five times a
  second, which is fast enough to be useful and slow enough not to matter. This
  is the only polling in the addon and it exists because the API offers nothing
  better.

**`Group.lua`** - `ns.Group`:

- `Group.Units()` - the five units in display order. `party1` through `party4`
  keep party order; `player` goes first or last according to `bar.selfBottom`.
  A function rather than a constant, because the order is the player's choice.
- `Group.Build()` - creates the anchor and one row per unit, once, at login.
- `Group.Layout()` - stacks the rows and sizes the anchor.
- `Group.ApplyAll()` - `Row.ApplySpells` for every row, or queues it if in
  combat.

**`Settings.lua`** - renders whatever `ns.RegisterSetting` has collected and
registers the category, as in UrlCopy. Adds one control type: a slot table.

## A row

```
 (o) Skyler    ████████░░   [H][R][T][C]
  ^    ^          ^            ^
  |    |          |            +- MAX secure buttons; unit attribute fixed forever
  |    |          +- health bar, class-coloured
  |    +- name
  +- row dims when the unit is dead, offline, or out of range
```

Five rows, in `Group.Units()` order - the party in party order, with your own
row above them or below them as you prefer.

The dimming is not decoration. Clicking a heal on someone dead or out of range
burns a global cooldown and returns nothing. `UnitIsDeadOrGhost` and
`UnitInRange` are a handful of lines and remove the most irritating wasted
cast in the addon's whole surface.

## The secure mechanism

Every button carries the same three attributes, written once, out of combat:

```lua
button:SetAttribute("type", "spell")
button:SetAttribute("spell", "Regrowth")    -- from Slots
button:SetAttribute("unit", "party2")       -- never changes again
```

That is the entire mechanism, and it is why "also dispel, also buff" costs
nothing: Cleanse, Remove Curse, Thorns and Mark of the Wild are Regrowth with
a different string in one attribute.

### Fixed unit slots

A row's `unit` attribute is set at creation and never written again. Blizzard
will not let us re-point a secure button in combat, and the usual answer -
`SecureGroupHeaderTemplate`, which assigns units inside secure code - carries
its children's construction in `initialConfigFunction`, a *string* of Lua
executed in the restricted environment. That is miserable to write, impossible
to unit-test, and buys nothing for five known units. It is the right answer for
raid, and raid is out of scope.

Fixing the binding guarantees the property that matters: **a button can never
cast on someone other than the person whose row it sits in.**

### Visibility belongs to Blizzard

Rows for absent party members are not hidden by us. `RegisterUnitWatch` shows
and hides a frame based on whether its `unit` attribute resolves to anyone, and
it runs in the secure environment, so it keeps working when the party changes
mid-fight. Ours is the one call; the combat-legal part is Blizzard's.

### One rule, everywhere

**No secure change happens in combat.** Writing a spell attribute, changing the
slot count, showing or hiding a button, **and re-ordering the rows** - all of
it waits. Healclick holds any pending change and applies it on
`PLAYER_REGEN_ENABLED`, the same shape `ChatKeys.Apply` already uses for
bindings in ForeverPanel.

Row order is in that list because moving a row moves the secure buttons inside
it. Whether the client actually refuses a `SetPoint` on a frame that merely
*contains* protected children, as opposed to on a protected frame itself, is
something this document assumes rather than knows - see the spike.

This is also why every row builds `Slots.MAX` buttons at load rather than the
configured number: growing the bar later must never need a frame created at a
moment the client forbids it.

## Configuration

One bar configuration, shared by all five rows.

Stored in `HealclickDB`:

```lua
{
    version = 1,
    bar     = {
        slots      = 4,
        locked     = false,
        selfBottom = false,    -- your own row: top by default
        spells     = {},       -- index -> spell name
    },
    anchor  = { point = "CENTER", x = 0, y = -200 },
    seeded  = false,
}
```

The panel, in declaration order:

| Control | Store | Default | Does |
|---|---|---|---|
| Buttons per player | `bar.slots` | 4 | Slider, 1-8. Applies out of combat |
| Put my row at the bottom | `bar.selfBottom` | off | Whether you sit above the party or below it |
| Spells | `bar.spells` | seeded | A row per slot; type the spell name |
| Lock the frame | `bar.locked` | off | Stops the anchor being dragged |

Where your own row sits is a checkbox rather than a dropdown, because a
two-way choice does not need a new control type and the panel already renders
checkboxes. Sorting the other four - by class, by name, by role - is out of
scope: party order is the order you already know from Blizzard's frames.

Every configured value lives under one `bar` store, because
`ns.RegisterSetting` addresses settings as `store` plus `key` and asserts a
default exists for the pair. `anchor` and `seeded` are state rather than
settings - dragged and computed respectively - so they sit outside it.

**An empty slot's button is hidden**, not shown and inert. A button that looks
pressable and does nothing is the same failure as a slot wired to a spell the
client does not know.

A spell name is checked against `GetSpellInfo` as it is entered, and **kept
either way**, with a warning when the client does not recognise it.

Rejecting an unrecognised name was this document's first answer and it was
wrong. `GetSpellInfo` only knows spells the character has actually learned, so
a level 5 Druid would be refused the Remove Curse they get at 24 - and the
seeded defaults below would be refused wholesale, since a Druid has none of
them at level 5. Setting up a spell you are levelling towards is sensible, not
a typo.

So the warning exists to catch the typo without blocking the plan: Healclick
says "that is not a spell you know yet" once, and keeps what you typed.

### Defaults, and a risk that turned out to be temporary

ForeverPanel's code records that this client discards SavedVariables between
sessions, and the spike confirmed it: the probe reported "loaded 0 times
before this one" on a reload that followed a successful earlier load.

**It is a beta-client artifact, not a property of the game.** SavedVariables
persist normally on live Classic; this particular 1.60 beta is not writing
them back. So Healclick stores its configuration the ordinary way and is not
contorted around the bug - a design bent around a temporary restriction would
be wrong the moment the restriction lifted, which is the worse failure of the
two available.

What the addon does take from it is one thing it would want anyway:

**Seed a starting set per class**, the way `ChatKeys` seeds `CTRL-S`, so a
configuration that has never been saved is still immediately usable.
`Slots.Seed(class)` fills empty slots from a small table - for a Druid,
Regrowth, Rejuvenation, Remove Curse, Mark of the Wild - and sets `seeded` so
a player who deliberately empties a slot does not have it refilled next login.
That is good first-run behaviour on any client, and on this one it happens to
mean the bar works every login even while the beta forgets everything else.

ForeverPanel's comments assert the discarding as though it were permanent, and
several of its defaults are chosen because of it. Those comments are now known
to be about a beta quirk rather than the game. Correcting them is a separate
job in a separate addon, not this design's business, but it should not be
forgotten.

## Commands

`/healclick`, short form `/hc`:

| Command | Does |
|---|---|
| `/hc` | Show the command list |
| `/hc settings` | Open the panel |
| `/hc lock` | Stop the anchor being dragged |
| `/hc reset` | Put the frame back in the centre |

A bare `/hc` lists the commands, matching `/fp` and `/url`. UrlCopy learned
that one the hard way: two addons whose login lines sit one above the other
must not disagree about what a bare command does.

## Testing

Lua 5.4, outside the game, against a stubbed API, driven by the repo's
`run-tests.ps1`. `tests/runner.lua` and `tests/helpers.lua` come from UrlCopy;
`tests/wow_stub.lua` is UrlCopy's extended with `SetAttribute`/`GetAttribute`,
`RegisterUnitWatch`, `InCombatLockdown`, `GetSpellInfo`, and the `Unit*`
family - `UnitExists`, `UnitName`, `UnitClass`, `UnitHealth`, `UnitHealthMax`,
`UnitInRange`, `UnitIsDeadOrGhost`, `UnitIsConnected`.

| File | Covers |
|---|---|
| `addon_spec.lua` | Defaults, the command dispatch, the setting registry |
| `slots_spec.lua` | Count clamping; a spell the client knows; a spell it does not, kept with a warning; seeding; a deliberately emptied slot staying empty |
| `row_spec.lua` | The three attributes per button, with the right unit; buttons past the count hidden; dim state for dead, offline and out of range |
| `group_spec.lua` | Five rows; your row first by default and last when `selfBottom` is set, with the party in party order either way; layout arithmetic; `RegisterUnitWatch` called once per row |
| `combat_spec.lua` | A change during combat is held and not written; it is applied on `PLAYER_REGEN_ENABLED`; nothing secure is touched in the meantime |
| `settings_spec.lua` | The panel renders one control per registered setting; the slot table writes through |

**What the tests prove and what they do not.** They prove we asked for the
right thing: that party2's slot 3 carries `type="spell"`, `spell="Remove
Curse"`, `unit="party2"`. They cannot prove Blizzard honours it. That is one
login, once - and it is why the implementation plan opens with a spike rather
than a file.

### The spike comes first

Before any of the above is built, thirty throwaway lines in the client:

1. One `SecureActionButtonTemplate` button, hardcoded `Regrowth` on `player`.
   Click it. Does it cast?
2. `RegisterUnitWatch` on a frame bound to `party1`. Does it appear and
   disappear with the party member, including in combat?
3. Can a frame holding secure buttons be moved with `SetPoint` while in
   combat, or does containing them make it as untouchable as they are? This
   decides whether dragging the anchor and re-ordering rows need the pending
   queue or can happen freely.
4. Does `HealclickDB` survive a logout?

If `SecureActionButtonTemplate` behaves differently on Interface 11509/16001
than this document assumes, every task after it is built on sand. Five minutes
at the start beats discovering it at the end, and the harness cannot discover
it at all.

## Install and packaging

Nothing to add: the repo's scripts find the addon by its `.toc`.

```powershell
.\run-tests.ps1 Healclick
.\package.ps1 Healclick -Install
```

The root `README.md` gains a row in its addon table.
