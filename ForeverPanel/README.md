# ForeverPanel (World of Warcraft AddOn)

A full-width bar across the top of the screen showing at-a-glance information.

Out of the box:

| Side | Module | Shows |
|---|---|---|
| Left | `money` | Gold, silver and copper with the in-game coin icons; click to flip to the money made this session (green for a gain, red for a loss), click again for the purse. The session survives /reload and ends on a real login, or when you right-click the block and pick `Reset session money` |
| Left | `bags` | Bag slots used out of the total with a bag icon (`30/38`), or just the free slots with the total turned off; click to open your bags |
| Left | `xp` | `xx.xx% XP` through the current level, click to count down to the next one instead; hidden at max level or with XP turned off |
| Left | `honor` | Honor points with the currency's own icon (`1,234`); click to open the currency tab, hover for the game's tooltip for it, cap included. Hidden on a character that has never had honor |
| Right | `clock` | Local time, click to toggle 12/24 hour |

Honor here is WoW Forever's spendable honor, the currency its PvP vendors
take, not the rank points that set your PvP rank. Forever's interface code
never names the honor currency, so the block tries the game's two honor ids
(`CLASSIC_HONOR_CURRENCY_ID` 1901, `HONOR_CURRENCY_ID` 1792) and then looks
for a currency called Honor in the currency tab. `/fp honor` says how much
there is and which currency id it came from. Not yet confirmed in the game.

The bar reserves its own strip of screen: it insets `UIParent` from the top, so
top-anchored Blizzard frames move down with it instead of being covered.

Right-click anywhere on the bar for `Settings...` and `Reset module order`.

The settings panel carries every option, including a switch per module to hide
one without removing it, and seven tweaks to Blizzard's own UI: hiding the
gryphons either side of the action bar, turning on the game's health and
mana numbers on the unit frames, showing the sell price on quest rewards,
showing the XP a quest gives (`+1,234 XP (8.2% of level)`) beside the quest
window's Accept and Complete Quest buttons, putting the backpack first in the
Combined Backpack, and keeping the player portrait
a set gap under the bar and from the left edge. The game saves the portrait's
place to the account, measured from the middle of the screen, so one placed
right on a laptop can overlap the bar, and sit near the middle, on a 4K
desktop; ForeverPanel decides both from the screen's own edges, on each screen
(and stays out of Edit Mode while it is open). Turn off "Keep it at the left
edge" to leave left and right where Edit Mode put them. The
chat box's place and size are saved to the account too, so ForeverPanel keeps
them per screen: where and how big you last saved it in Edit Mode on that
screen. On a screen you have not placed it on, the layout has it.

The action bars' places are kept per screen as well, for each Edit Mode
layout: every bar stays where it was the first time ForeverPanel saw that
screen, or where you last saved it there in Edit Mode, so moving a bar on the
laptop leaves the desktop's alone. A screen not seen before starts from the
layout as it is then. Only the game can put a bar into the stack along the
bottom or down the right, so a bar moved out of the stack on another screen
stays out on this one too. The bars are moved out of combat and never while
Edit Mode is open, and turning "Keep the action bars' places for each screen"
off gives them back to the layout.

WoW Forever's 1.60.1 (70291) patch put the backpack at the bottom of the
Combined Backpack and the last bag on top. "Backpack first in the combined
bags", on by default, lays the same slots out again on the game's own grid.
The backpack's first slot goes in the top-left corner, each bag follows in
order, and any gap goes at the bottom right by the money. Separate bags and
the gamepad layout are left alone.

### Quests

On WoW Forever the settings panel has a group for quest tracking, under the
layout options. Classic Era's quest log is another window, so there it has
none of this.

- **Untrack-all box in the quest log** (on). A tick box at the top of the
  quest log, between the quest count and the settings gear, drawn like the
  box beside each quest. It is ticked while any quest is tracked; click it
  and every quest comes off the tracker, with the sound of clearing one
  quest's box. The quests stay in your quest log. Hover it to see how many
  are tracked. The search box is a little narrower to make room, and gets
  its width back when the box is turned off.
- **Track only the quests where you are** (off). Each time you arrive in a
  zone or dungeon (a new zone, a loading screen, logging in), the tracker
  swaps over to that place's quests: the ones under the quest log header
  with the zone's name ("Hillsbrad Foothills", or "Gnomeregan" inside the
  dungeon), and any quest whose objectives the game shows on the map you
  are on, wherever it sits in the log. In a cave or building with a map of
  its own, the zone around it counts; inside a dungeon only the dungeon
  does. Everything else is untracked first, so a full tracker has room.
  Your own ticks stand until you move on, and a quest you take here is
  tracked even with the game's automatic tracking off.
- **Automatic quest tracking** (the game's own, on by default). While it is
  on, the game tracks each quest you take and each one you make progress
  on, so untracked quests come back. WoW Forever's options have no switch
  for it; this is the game's `autoQuestWatch` setting itself, not a copy.

`/fp untrack` untracks every quest and says how many. `/fp quests` says where
you are (the names headers are matched against, and the map), which quests
in your log count as here and why, and the headers in your log: if a place's
quests are not picked up, it shows whether the header's name differs from
the zone's.

Where you are is the zone's name (`GetRealZoneText`, `GetZoneText`) and the
player's map (`C_Map.GetBestMapForUnit`), walked out to the zone while the
map is a cave or building (`Enum.UIMapType.Micro`); a quest's own map is
`GetQuestUiMapID`. Not the quest log's `isOnMap`, which follows whichever map
the world map last showed. Not yet confirmed in the game: how the box lines
up with the gear and the quest count, and whether every header's name
matches its zone's.

Modules are rearranged by dragging them along the bar. The bar reorders live
while you hold one, so it is its own drag preview, and the layout is saved
between sessions. Which third of the bar you drop in picks the side, so a
module can move from the right group to the centre or left. `/fp bar lock`
stops accidental drags and `/fp bar reset` puts everything back.

## Install

1. Copy this folder into your client's `Interface/AddOns` as `ForeverPanel`,
   so the result is `.../Interface/AddOns/ForeverPanel/ForeverPanel.toc`.
2. Restart the client and enable ForeverPanel from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 ForeverPanel -Install

See the [repo README](../README.md) for packaging and test commands.

Built against Classic Era 1.15.x (`11509`) and the 1.60.x Classic beta
(`16001`). For retail, change `## Interface` in the .toc to the current retail
interface version.

## Commands

`/foreverpanel` or the short `/fp`:

- `/fp` - Show help
- `/fp bar` - Show or hide the bar
- `/fp bar height <16-48>` - Set the bar height
- `/fp bar push` - Toggle reserving space (off = overlay the UI instead)
- `/fp bar lock` - Stop modules being dragged
- `/fp bar reset` - Restore the default module order
- `/fp settings` - Open the settings panel
- `/fp bar debug` - Print the bar's screen rect and module widths
- `/fp money reset` - Start the money made this session over from now
- `/fp xp` - Toggle XP between counting up and counting down
- `/fp honor` - How much honor you have, and which currency the bar reads it from
- `/fp clock` - Toggle 12/24 hour time
- `/fp clock blizzard` - Show or hide Blizzard's own clock
- `/fp untrack` - Untrack every quest (WoW Forever)
- `/fp quests` - Where you are, and which quests in your log belong here (WoW Forever)
- `/fp status` - Show launch and note counts
- `/fp note <text>` - Save a persistent note
- `/fp last` - Show most recent note
- `/fp clear` - Remove all notes

## Adding a module

`Bar.lua` owns the frame, layout and event plumbing. A module just describes
itself, so adding one means a new file in `Modules/` and a line in the .toc —
no edits to `Bar.lua`.

```lua
local addonName, ns = ...

ns.Bar:RegisterModule({
    name     = "durability",
    side     = "LEFT",              -- LEFT | CENTER | RIGHT
    order    = 20,                  -- ascending within a side
    events   = { "UPDATE_INVENTORY_DURABILITY" },
    interval = nil,                 -- optional polling, in seconds

    OnCreate = function(module)
        module.text = module.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        module.text:SetPoint("LEFT")
    end,

    OnUpdate = function(module)
        module.text:SetText("100%")
        module:SetWidth(module.text:GetStringWidth())
    end,

    OnClick = function(module, button) end,   -- optional

    -- Optional: actions of its own for the right-click menu, added under the
    -- bar's when it is opened over this module.
    OnMenu = function(module, root)
        root:CreateButton("Reset durability log", function() end)
    end,
})
```

The bar gives every module a container `Button` at `module.frame`, plus:

- `module:SetWidth(width)` - report your content width so the bar can lay out
- `module:SetShown(shown)` - hide yourself; the bar closes the gap
- `module:Refresh()` - re-run `OnUpdate`
- `module:MarkDirty()` - request a re-layout

To put your config on the settings panel, declare it next to the code that uses
it — `Modules/Settings.lua` renders whatever has been registered, so it needs no
edit:

```lua
ns.RegisterSetting({
    store = "durability",   -- ns.db.durability.showPercent
    key   = "showPercent",
    type  = "checkbox",     -- checkbox | slider (slider takes min/max/step)
    name  = "Show a percentage",
    onChange = function() ns.Bar:GetModule("durability"):Refresh() end,
})
```

Registering a setting with no matching `AddDefaults` entry is an error, since it
would render a control that silently does nothing. A value the game keeps, such
as a console variable, brings its own `get` and `set` instead of a default, and
is read and written there rather than copied into `ForeverPanelDB`.

Every module also gets a `Show <name>` checkbox on the panel automatically, so
you do not declare that one yourself.

Name your font string `module.text`. The bar uses it to colour your text (the
bar owns that, so a module cannot make itself unreadable against the bar's
background) and to re-measure you after the first frame, which is the only point
at which the client can measure text at all.

Layout rules: `LEFT` flows left-to-right from the left edge, `RIGHT` flows
right-to-left from the right edge, and `CENTER` is laid out as one group
centred on the bar. Hidden modules take their spacing with them.

`side` and `order` here are only the defaults. Once a module has been dragged,
the position saved in `ForeverPanelDB.bar.layout` wins, until `/fp bar reset`.

## Tests

The formatting, layout and registry logic is covered by unit tests that run
outside the game against a stubbed WoW API (`tests/wow_stub.lua`).

From the repo root:

```powershell
.\run-tests.ps1 ForeverPanel
```

Or by hand, from this folder:

```
lua tests/runner.lua tests/format_spec.lua tests/addon_spec.lua
```

Frame behaviour and the `UIParent` inset can only really be confirmed in the
game client; the tests cover the logic around them.
