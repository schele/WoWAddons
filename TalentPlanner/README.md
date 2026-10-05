# TalentPlanner (World of Warcraft AddOn)

Plan the order your talent points go in, see the plan in the game's talent
window, and be told which talent comes next when a point is free.

## The planner

`/tp`, or a click on the minimap button, opens the planner: your class's three
trees side by side, laid out as the game lays them out. Under each talent is
how many points the plan puts in it (`2/5`) and the level its first point is
taken at. Lines join a talent to the one it needs.

| Do | And |
|---|---|
| Left-click a talent | The plan's next point goes in it |
| Right-click a talent | Its last planned point comes out |
| Hover a talent | The game's tooltip, plus "Planned at levels 12, 14, 16" |

Point 1 is taken at level 10, point 2 at 11, and so on to point 51 at 60.
Every point is checked as the game checks it: no more ranks than the talent
has, 5 points in the tree for each tier above it, its prerequisite at full
rank first, and no more than 51 points. A point that breaks a rule is not
added, and the line under the trees says why.

A point that a later one depends on (by a prerequisite, or by the points its
tier needs) does not come out on a right-click: the planner names the later
point instead. **Undo** takes out the last point; **Clear** empties the plan
once you say so.

The talents themselves are read from the game each time the planner opens,
never from a table of TalentPlanner's own, so any talent WoW Forever has
changed shows as the client has it.

## Plans

Each character has its own plans. The button at the top left is the plan's
name: click it for the list, to switch plans, or for **New plan**, **Rename**
and **Delete**. The count beside it is the points planned, `23/51`.

## Export and import

**Export** shows the plan as a line of text, selected for Ctrl+C:

    TP1:DRUID:21212121212223

**Import** takes one pasted with Ctrl+V. It is checked against your class and
every rule above; a string that breaks one is refused, naming the first point
that does. An imported plan is added as a new plan, "Imported", and does not
replace the one you had. Talent-calculator links are not read: every site
writes them differently.

## In the talent window

With the game's talent window open, each talent in the plan shows how many
points the plan puts in it, the plan's next talent glows, and a talent with
more points than the plan had by now has a red edge. The window also names
the next talent.

## The reminder

When you have a talent point to spend, at login, on a level up, or after
spending one, a chat line names the plan's next talent:

    Talent point ready: Feral Instinct (2/5)

It is said once for each point.

## Learn next

Off by default. Turned on in the settings, a **Learn next** button on the
planner and on the talent window spends a free point on the plan's next
talent. Never in combat, and only on a client that has `LearnTalent`. If the
client refuses, the button does nothing; `/tp probe` says so.

## Settings

TalentPlanner has a page in the game's options (Esc, Options, AddOns,
TalentPlanner):

- Remind me when a point is free (on)
- Show the plan in the talent window (on)
- Show the Learn next button (off)
- Show the minimap button (on)

The minimap button opens and closes the planner; right-click it for the
settings, drag it to move it round the minimap.

## Commands

| Command | Does |
|---|---|
| `/tp` | Open or close the planner |
| `/tp new <name>` | Start a new, empty plan |
| `/tp rename <name>` | Rename the plan |
| `/tp delete` | Delete the plan |
| `/tp settings` | Open the settings page |
| `/tp minimap` | Hide or show the minimap button |
| `/tp probe` | Show which talent calls this client has, including `LearnTalent`, and what Learn next last did |

## Install

1. Copy this folder into your client's `Interface/AddOns` as `TalentPlanner`,
   so the result is `.../Interface/AddOns/TalentPlanner/TalentPlanner.toc`.
2. Restart the client and enable TalentPlanner from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 TalentPlanner -Install

See the [repo README](../README.md) for packaging and test commands.
