# TalentPlanner: design

Plan the order talent points are spent in, see the plan in the game's talent
window, and be told which talent comes next when a point is free.

## The trees

Read from the game, never from a table, so any class and any talent WoW
Forever has changed works: `GetNumTalentTabs()`, `GetTalentTabInfo(tab)`
(name, icon, points spent), `GetNumTalents(tab)`, `GetTalentInfo(tab, i)`
(name, icon, tier, column, rank, maxRank), `GetTalentPrereqs(tab, i)`
(required tier and column). Read when the planner opens, after
`PLAYER_LOGIN`.

## Plans

Saved per character: `TalentPlannerDB.chars["Name-Realm"] = { active =
"Feral levelling", plans = { [name] = { class = "DRUID", points = { {tab,
i}, ... } } } }`. A plan is the ordered list of points; point n is taken at
level n + 9 (first point at 10).

Rules checked on every added point, as the game checks them: the talent is
below its maxRank in the plan so far; the tree has 5 × (tier − 1) points
planned before it; its prerequisite is at full rank before it; no more than
level 60's 51 points.

Removing: right-click a talent removes its last planned point if the plan
stays valid without it; otherwise nothing changes and the planner says which
later point depends on it. Undo removes the last point; Clear empties the
plan (with a confirmation).

## Planner window

`/tp` or minimap left-click. BossLoot's frame, opaque background. Three trees
side by side in the game's grid (tier rows, columns), each talent its icon
with "planned/max" under it and the level of its first planned point. Arrows
for prerequisites as simple lines. Left-click adds the next point; tooltip is
the game's talent tooltip (`GameTooltip:SetTalent(tab, i)`, guarded) plus
"Planned at levels 12, 14, 16". Top bar: plan selector (the game's dropdown
menu; New, Rename, Delete), points planned "23/51", Undo, Clear, Export,
Import.

## In the game's talent window

On `ADDON_LOADED` for `Blizzard_TalentUI` (or at login if already loaded),
for each talent button (`TalentFrameTalent<n>` or `PlayerTalentFrameTalent<n>`,
matched to tab and index through the button's own id): a small "x planned"
label, a glow on the next planned talent, and a red edge on talents with more
points spent than the plan has by now. Toggled by a setting.

## Reminder

When the player has an unspent point (`UnitCharacterPoints("player")` or
`GetUnspentTalentPoints()`, whichever exists) at login, on
`PLAYER_LEVEL_UP` and on `CHARACTER_POINTS_CHANGED`: one chat line, "Talent
point ready: Feral Instinct (2/5)". Not repeated for the same point.

**Learn** (setting, off by default): a "Learn next" button on the planner
and in the reminder line's place on the talent window spends the point on
the planned talent with `LearnTalent(tab, i)`, never in combat, only when the
client has `LearnTalent`. The client may refuse; the button then does nothing
and the probe says so.

## Export and import

A plan as text: `TP1:<CLASS>:<points>` where each point is two characters,
the tab (1-3) and the talent index in base 36. Import checks the class and
every rule, and names the first point that breaks one. No talent-calculator
links (their formats differ by site and version).

## Settings page

Canvas page like the other addons: Remind me when a point is free; Show the
plan in the talent window; Show the Learn next button; Show the minimap
button. Defaults on, except Learn next.

## Files

`TalentPlanner.lua` (database, commands, `ns.Guarded`), `Trees.lua` (reading
the game's trees), `Plan.lua` (rules, add, remove, levels; pure Lua, no game
calls), `Codec.lua` (export/import), `Planner.lua` (window), `TalentFrame.lua`
(overlay), `Reminder.lua` (chat line, Learn), `Minimap.lua`, `Settings.lua`,
`tests/`.

## Failure handling

Every game call through `ns.Guarded`. A client without one of the talent
calls: the planner says so instead of drawing. `/tp probe` prints which talent
calls this client has, including `LearnTalent`.

## Testing

Lua specs with a stub game holding a small made-up three-tree class: the
rules (rank, tier gate, prerequisite, 51 points), removing with and without
dependants, levels, codec round trip and bad strings, reminder lines and not
repeating, Learn out of combat only, overlay counts, settings page.
