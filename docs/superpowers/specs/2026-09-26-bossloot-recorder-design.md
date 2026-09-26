# BossLoot loot recorder: design

Date: 2026-09-26. Status: approved (Carl chose "take the recommended option" for
every open decision).

## Why

WoW Forever is not vanilla 1.12. Icy Veins' WoW Forever guides (checked
2026-09-26, updated 24 Sep 2026): "WoW Forever has completely reworked dungeon
loot and item stats, meaning Classic equipment lists can not be used to
determine best-in-slot gear for the beta." In game the server answered not one
of 4,661 requests for BossLoot's vanilla gear items, and said "no such item" to
3,900 of them. No public WoW Forever item database exists yet.

So BossLoot's loot tables, built from vMaNGOS's vanilla database, are likely
wrong for WoW Forever. The instances, bosses and maps are likely still right.
The only accurate source of WoW Forever loot is the game itself. BossLoot will
record what really drops, and what quests, merchants and professions offer, as
the player plays. Recordings from several players can be baked into releases.

This is the first of two projects. The second, the gear finder (best gear per
class, spec and level), will score the items this one learns. Its decisions so
far are listed at the end so they are not lost.

## Goals

- Record, per account, into saved variables:
  1. **Loot**: from bosses, trash and chests in instances, and from mobs and
     objects in the open world, with where and how often.
  2. **Boss fights**: as they end, with the boss's name as the game gives it.
  3. **Quest rewards**: the fixed and the choice items in quest windows.
  4. **Merchant goods**: with price.
  5. **Crafted items**: what the player's profession recipes make.
- Show recorded loot in the Dungeons and Raids tabs, first, with how often it
  was seen, and the vanilla list dimmed below it.
- List instances BossLoot does not know (WoW Forever's new ones) with the
  bosses the game named.
- Let the build merge saved-variables files into the shipped data, so a
  release carries everyone's recordings.

## Non-goals

- The gear finder. It comes next, as its own project.
- Loot seen only in chat ("Tim receives loot: ..."): chat does not say which
  corpse an item came from.
- Swapping recordings between players in game.
- A screen for quest, merchant or crafted recordings. They are recorded now
  for the gear finder. For now `/bl recorded` prints counts.

## 1. What is recorded, and how

A new file, `Recorder.lua`, listens to game events. Every API call is feature
checked, so a client without one records the rest and never errors.

**Loot.** On `LOOT_OPENED`, for each slot holding an item
(`GetLootSlotLink(slot)`), `GetLootSourceInfo(slot)` gives the GUID of each
corpse or object the item came from, and how many.
- A GUID gives its kind and id. For example,
  `Creature-0-<server>-<instance>-<zone>-<npcID>-<spawn>` gives `npc` and the
  npc id, and `GameObject-...` gives `object` and the object id. Any other kind
  (such as `Item-`, a container like a clam) is not recorded.
- Each GUID counts once: the first time its loot is opened it adds one kill or
  opening, and its items are counted. Reopening the same corpse adds nothing.
  The last 500 GUIDs are kept in saved variables, so a reload does not recount.
- Where: `GetInstanceInfo()` gives the instance name, its type (`party`,
  `raid`, or something else meaning the open world) and its map id.
  `GetRealZoneText()` gives the zone.
- The source's name: the loot target's name when `UnitGUID("target")` is the
  source's GUID, otherwise the name already recorded for that source,
  otherwise none. Names are filled in whenever they become known.

**Boss fights.** On `ENCOUNTER_END` with success, the encounter's name is
remembered for 60 seconds. A creature looted in that time whose name matches it
is marked as that encounter's boss (`encounter = <name>`). This identifies
bosses in instances BossLoot does not know.

**Quest rewards.** On `QUEST_DETAIL` and `QUEST_COMPLETE`: the quest id
(`GetQuestID()`), its title (`GetTitleText()`), and the items from
`GetQuestItemLink("reward", i)` for `GetNumQuestRewards()` and
`GetQuestItemLink("choice", i)` for `GetNumQuestChoices()`. The recorder's
faction (`UnitFactionGroup("player")`) is noted.

**Merchant goods.** On `MERCHANT_SHOW`: the merchant (`UnitGUID("npc")`, which
gives the npc id, and `UnitName("npc")`), the zone, and for each item
`GetMerchantItemLink(i)` and its price and how many it buys, from
`C_MerchantFrame.GetItemInfo(i)` on newer clients (WoW Forever's) or
`GetMerchantItemInfo(i)` on older ones. Rank and reputation needs stay in the
item's own data, for the gear finder.

**Crafted items.** On `TRADE_SKILL_SHOW`, and a moment after the list updates
(`TRADE_SKILL_LIST_UPDATE`, `TRADE_SKILL_UPDATE`): the profession and what
each recipe makes. WoW Forever's client has the newer `C_TradeSkillUI`: the
profession from `GetBaseProfessionInfo()`, the recipes from
`GetAllRecipeIDs()`, and each one's item from `GetRecipeSchematic(id)` or
`GetRecipeItemLink(id)`. Older clients: `GetTradeSkillLine()`, and for each
recipe that is not a header (`GetTradeSkillInfo(i)`),
`GetTradeSkillItemLink(i)`.

**Items.** For every item recorded, its name, quality, type, subtype and slot
come from the game (`LootRow.ItemInfo`). They are saved with the recording,
because they are real WoW Forever items and the server describes them.

## 2. Storage

In `BossLootDB.recorded`. Saved variables are per account.

```lua
recorded = {
    recorder = "a1b2c3d4",      -- random, made once: whose recordings these are
    sources = {                  -- loot, by "<kind>:<id>@<map>": one id can stand in several places
        ["npc:6910@70"] = {
            kind = "npc", id = 6910, name = "Revelosh", encounter = "Revelosh",
            map = 70, instance = "Uldaman", instanceType = "party", zone = "Uldaman",
            kills = 5,                         -- kills, or openings for objects
            items = { [9387] = 2, [9388] = 1 },
        },
    },
    quests = { [2279] = { title = "...", faction = "Alliance", rewards = { 9587 }, choices = { 9588, 9589 } } },
    merchants = { ["npc:1234"] = { name = "...", zone = "...", items = { [2901] = { price = 81 } } } },
    crafts = { ["Blacksmithing"] = { [2862] = true } },
    items = { [9387] = { "Revelosh's Boots", 2, "Armor", "Plate", "INVTYPE_FEET" } },
    seen = { "Creature-0-...", ... },         -- the last 500 GUIDs looted
}
```

## 3. Matching recordings to BossLoot's instances and bosses

- The build adds ids to the generated data: the instance's `map` id, and on
  each boss its creatures' npc ids (`npcs`) and, for a chest boss, its chests'
  object ids (`objects`).
- A recorded source belongs to a known instance when its `map` matches. It
  belongs to a boss when its id is one of the boss's `npcs` or `objects`, or
  when its name or encounter matches the boss's name.
- A boss's recorded loot sums the item counts of its sources. Its kills are the
  most kills of any one of its sources, so a council of three creatures does
  not count three kills a fight.
- In a known instance, sources that are not a boss's make up the recorded
  notable lists: creatures under **From trash**, objects under
  **Chests & objects**. As in the vanilla lists, only rare or better items,
  recipes and keys count.
- A recorded map id BossLoot does not know becomes a **recorded instance**:
  - Its name and kind (dungeon for `party`, raid for `raid`) come from the
    recording.
  - Its bosses are the sources marked with an encounter, in the order first
    recorded. Its notable lists are made the same way as a known instance's.
  - It has no level range, map or pins. It is listed in its tab after the
    known instances, and the right-click hide works on it too.

## 4. The loot list

For a boss or notable list, the entries are:
1. **Recorded items**, most seen first.
   - A boss's items show `seen/kills` in the chance column (for example
     `3/5`). A small sample is shown as counts, not dressed up as a percentage.
   - Notable items show `×count`, with the sources' names on their grey line,
     as the vanilla notable list does.
2. A heading row across the grid: "Classic loot, not seen on WoW Forever yet".
3. **The vanilla entries**, less the recorded ones, dimmed (alpha 0.45). They
   are shown as before otherwise.

When nothing is recorded, the heading and the dimmed vanilla list show alone.
A heading starts a new line of the two-column grid, so the grid gets blank
cells to line it up. Blank cells show nothing and take no clicks.

## 5. Baking recordings into releases

- Saved-variables files (`WTF/Account/<name>/SavedVariables/BossLoot.lua`,
  yours or sent by friends) go in `BossLoot/tools/recordings/`. The build reads
  every `*.lua` file there.
- A small parser in `tools/lib/savedvars.mjs` reads the subset of Lua that the
  game writes: tables, strings, numbers, booleans, `nil`, `["key"] =` and
  `[number] =` keys, and `-- [n]` comments.
- The build writes `Data/Recorded.lua`. Each recorder's recordings are kept
  apart, keyed by recorder id: `ns.AddRecordings("a1b2c3d4", { ... })`, with
  `sources`, `quests`, `merchants`, `crafts` and `items`, but not `seen`.
  The file is always written, even when empty, so the TOC is stable.
- At runtime, the merged view sums the baked recorders' data and the player's
  own live recordings. It leaves out the baked copy of the player's own
  recorder id, so a player's own loot is never counted twice.
- Baked recorded items are an item-info layer. The order is:
  1. the client's copy;
  2. the player's saved copy;
  3. a baked recorded item;
  4. the vanilla built-in item.
  So a WoW Forever item's real name wins over a vanilla item with the same id.

## 6. Diagnostics

- `/bl probe` prints, for each call the recorder uses, whether this client has
  it. This is the check to run in game before trusting the recorder.
- `/bl recorded` prints counts: sources (bosses, mobs, chests), items, quests,
  merchants and professions.

## 7. Testing

- **Lua specs**, with the WoW stub given loot, instance, unit, quest, merchant
  and trade-skill calls:
  - the recorder records each kind;
  - it counts each GUID once;
  - it marks encounter bosses;
  - it skips non-item slots;
  - it survives a client missing any call.
- **Lua specs for the merged view and the loot list**: recorded loot first with
  `seen/kills`; the dimmed classic list under its heading; the baked copy of
  one's own recordings left out; a recorded instance listed with its bosses.
- **Node tests**:
  - the saved-variables parser: nested tables, escapes, comments and numeric
    keys;
  - merging recordings files into `Data/Recorded.lua`;
  - the instance data carrying `map`, `npcs` and `objects`.
- **In game**: `/bl probe`, then loot a few mobs, bosses and a chest, open a
  merchant, a quest and a profession, and `/reload`; `/bl recorded` shows the
  counts, and the boss's loot list shows its recorded drops.

## Carried forward to the gear finder (project 2)

Agreed on 2026-09-26, to be designed properly once the recorder has data:
- **Layout:** a Gear tab beside Dungeons and Raids, in the same three columns.
  - Left: class, spec, a PvE or PvP build, a level (defaulting to the
    character's), and switches for Dungeons, Raids, Quests, Crafted, World drops
    and PvP.
  - Middle: the slots, each with its best item.
  - Right: the chosen slot's best three, with their sources.
- **Scoring:** fixed, built-in stat weights per class and spec, PvE and PvP,
  from published community values. Research is in
  `docs/superpowers/research/2026-09-26-gear-finder-research.md` (vanilla 1.12
  formulas; the level-60 lists there are vanilla items).
- **Enchants:** recommended per build and slot.
- **Guide picks:** a mark where the guides name an item, and a test that the
  scoring agrees with them for most slots.
- **Rules:** two-handers in their own row beside Main Hand and Off Hand;
  random-suffix items left out; set bonuses ignored; an item counts at level N
  when its required level is N or lower.
- **Items:** the items the recorder learns, with stats from the game.
