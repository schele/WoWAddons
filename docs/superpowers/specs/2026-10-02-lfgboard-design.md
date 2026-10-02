# LFGBoard Design

**Date:** 2026-10-02
**Status:** approved in chat (with a mockup); checked in game after the build (see "Checked in game")

## Purpose

Find a group that wants you without reading chat as it scrolls past.

On WoW Forever groups form in chat and in the game's group finder, a list
you browse and whisper from. Chat moves too fast to read while playing, and
the finder shows little and needs opening. LFGBoard gathers both into one
window, filtered to the dungeons near your level and the roles you play,
shows who is already in a group where the game says so, and opens a whisper
with the message already typed.

Carl plays a level-20 feral druid, so his roles are tank and damage; the
board is not healer-only.

## The window

```
 LFG Board                                                           [x]
 [All 9] [Dungeons 6] [Quests 2] [Raids 1]  Dungeon: Any v
 Roles: [T] [ ] [D]   [x] Near my level   [x] Alerts   [Refresh]
 When  Who          For              Said                    Party           
 0:12  Garrok 22    Deadmines        LF2M DM need heals+dps  T D D + +  [Whisper]
 0:48  Elandra      Wailing Caverns  LFM WC, have tank       ?/5        [Whisper]
```

The mockup that was agreed is a dark, gold-titled window in the game's
style, as in the chat of 2026-10-02.

- **Opening:** a minimap button (built like BankBags') or `/lfgb`. The board
  keeps collecting while closed. The window is movable, remembers where it
  was put, and Escape closes it.
- **Rows,** newest first: how long ago (`0:12`), who (in their class colour,
  with a level when the group finder gives one; chat does not), what for,
  what they said, the party, and a Whisper button.
- **Party:** for a group listed in the finder, one square per member in its
  class colour with its role letter (T, H, D), empty squares for the open
  places, and "room for:" the roles still wanted. For a group only posted in
  chat: the size the post gives ("3/5" from "LF2M", "?/5" when it gives
  none) and the roles it asks for.
- **Source:** a row from the finder, from chat, or both, says so under the
  name ("group finder", "chat only", "group finder + chat").
- **Green edge:** a row that explicitly asks for one of your roles.

## Filters

- **Tabs:** All, Dungeons, Quests, Raids, each with the number of rows it
  holds under the other filters.
- **Dungeon picker:** Any, or one dungeon or raid.
- **Roles you play:** Tank, Healer, Damage switches, saved per character.
  The first time a character opens the board, they start as its class can
  play: tank for warrior, paladin and druid; healer for priest, paladin,
  druid and shaman; damage for every class. A row shows if it needs one of
  your roles or does not say what it needs; a row asking only for roles you
  have switched off is hidden.
- **Near my level:** hides dungeons and raids whose level range, widened by
  3 at each end, does not include your level. Quest groups and rows with an
  unknown activity are not hidden by it.

## Where the rows come from

### Chat, live

Every channel you are in (General, Trade, LookingForGroup, World, custom
channels), except LocalDefense and WorldDefense, and guild chat. A message
becomes a row only when it is **recruiting**:

- it says `LFM`, `LF1M` to `LF4M` (also `LF 2M`, `lf2m`), `LF more`,
  `looking for more`, or `LF`/`need` followed by a role (`LF tank`,
  `need heals`);
- `LFG` on its own is a *player* looking for a group, and is skipped;
- a channel message mentioning `guild` is skipped (guild recruitment, not
  groups); in guild chat the word means nothing and is not skipped.

From a recruiting message, read case-insensitively and word by word:

- **What for:** one of the dungeons and raids below by name or abbreviation,
  or a quest group (`quest`, `quests`, `q` followed by a name, `elite`). A
  recruiting message naming none of them becomes an "Other" row, shown only
  under All, since Forever may add dungeons this list does not know.
- **Roles wanted:** `tank`/`tanks`; `heal`/`heals`/`healer`/`healers`;
  `dps`/`dd`/`damage`; `all` or `need all` means every role. None of these
  means unknown.
- **Size:** `LF1M` is 4/5, `LF2M` 3/5, `LF3M` 2/5, `LF4M` 1/5 for a dungeon
  or quest; an explicit `3/5` is taken as written. Raids: only an explicit
  `31/40`.
- **Done:** `full`, `group full`, `filled`, `nvm`, `no longer lf` removes that
  person's row at once.

A newer recruiting message from the same person replaces their row. A row
from chat drops off **10 minutes** after its message.

### The game's group finder, on Refresh

The game lets an addon search the group finder only from a click, so the
board searches when **Refresh** is clicked, for the current tab's category
(All searches Dungeons). It also takes the results whenever the game's own
finder window searches.

For each listed group: the leader, the activity, the comment, and each
member's class and role (and level, where the finder gives it). A group that
reaches 5 of 5, or delists, is removed as soon as the game reports it. A new
search replaces the finder rows from the last one; chat rows are untouched. A finder row also
drops off 10 minutes after the search that last saw it.

A finder listing and a chat message from the same leader share one row: the
finder's party, the chat message's words and time.

## Dungeons and raids

From BossLoot's data, with the abbreviations players type. "DM" alone is
the Deadmines; Dire Maul is `DME`, `DMW`, `DMN`, `DM east/west/north` or
`dire maul`.

| Name | Kind | Levels | Also typed as |
|---|---|---|---|
| Ragefire Chasm | dungeon | 13-18 | rfc, ragefire |
| Wailing Caverns | dungeon | 17-24 | wc, wailing |
| The Deadmines | dungeon | 17-26 | dm, vc, deadmines |
| Shadowfang Keep | dungeon | 22-30 | sfk, shadowfang |
| Blackfathom Deeps | dungeon | 24-32 | bfd, blackfathom |
| The Stockade | dungeon | 24-31 | stocks, stockade, stockades |
| Gnomeregan | dungeon | 29-38 | gnomer, gnomeregan |
| Razorfen Kraul | dungeon | 29-38 | rfk, kraul |
| Scarlet Monastery | dungeon | 26-45 | sm, scarlet, cath, cathedral, armory, armoury, library, lib |
| Razorfen Downs | dungeon | 37-46 | rfd, downs |
| Uldaman | dungeon | 41-51 | ulda, uldaman |
| Zul'Farrak | dungeon | 44-54 | zf, zulfarrak |
| Maraudon | dungeon | 46-55 | mara, maraudon |
| The Temple of Atal'Hakkar | dungeon | 50-56 | st, sunken |
| Blackrock Depths | dungeon | 52-60 | brd |
| Blackrock Spire | dungeon | 55-60 | lbrs, ubrs, brs |
| Dire Maul | dungeon | 55-60 | dme, dmw, dmn, dire maul |
| Scholomance | dungeon | 58-60 | scholo, scholomance |
| Stratholme | dungeon | 58-60 | strat, strath, stratholme |
| Onyxia's Lair | raid | 60 | ony, onyxia |
| Molten Core | raid | 60 | mc |
| Zul'Gurub | raid | 60 | zg |
| Blackwing Lair | raid | 60 | bwl |
| Ruins of Ahn'Qiraj | raid | 60 | aq20 |
| Temple of Ahn'Qiraj | raid | 60 | aq40 |
| Naxxramas | raid | 60 | naxx |

Rows show the name without a leading "The".

## Whisper

The button opens a whisper to that person with the message already typed;
Enter sends it, or it can be edited first:

`Hi! Level 20 feral druid, tank or dps. Room for me in Deadmines?`

- **Level and class:** yours.
- **"feral":** the talent tree with the most points, by its first word in
  lower case, with the usual short forms (Restoration `resto`, Protection
  `prot`, Beast Mastery `bm`, Discipline `disc`, Elemental `ele`,
  Enhancement `enh`, Demonology `demo`, Destruction `destro`, Affliction
  `affli`). Left out with no points spent.
- **Roles:** your roles that the row wants, joined by "or"; all your roles
  when it does not say. Words: `tank`, `healer`, `dps`.
- **Activity:** the row's name; "your quest group" for a quest group,
  "your group" for Other.

## Alerts

For a new row that **explicitly** asks for one of your roles and passes
Near my level:

- a short sound, and one chat line:
  `LFG Board: Garrok wants a tank or dps for Deadmines. [Whisper]`, where
  `[Whisper]` is a link that opens the same whisper as the button (a chat
  link of our own, handled the way UrlCopy's are);
- at most once per person and activity;
- never while you are in a group;
- never for your own messages;
- off with the board's Alerts switch (saved).

## Architecture

| File | Responsibility |
|---|---|
| `LFGBoard.toc` | `Interface: 11509, 16001`, `SavedVariables: LFGBoardDB`, `IconTexture` |
| `LFGBoard.lua` | Namespace, defaults, `ns.Print`, `ns.Guarded`, commands, `/lfgb`, login |
| `Activities.lua` | Data: the table above, and finding an activity in words |
| `Parse.lua` | Reading one chat message: recruiting or not, activity, roles, size, done. No frames |
| `Posts.lua` | The rows: adding, replacing, expiring, merging chat with finder, removing, filtering, counting per tab |
| `Finder.lua` | The group finder: Refresh's search, reading results and members, updates, removal |
| `Whisper.lua` | The message and opening chat with it |
| `Alerts.lua` | When to alert, the sound, the chat line and its link |
| `Chat.lua` | Listening to the channels and guild chat, and sweeping out rows past ten minutes |
| `Window.lua` | The board: tabs, picker, switches, rows, Refresh |
| `Minimap.lua` | The minimap button |

Plus `README.md`, `icon.tga` and `minimap.tga` (drawn by
`tools/draw-icons.mjs`), and a row in the root README's table.

`Parse.lua` and `Activities.lua` have no frames and hold most of the logic,
so most of the tests are theirs. `Finder.lua` is the only file that knows the
group finder's calls: if Forever's turn out different, only it changes, and
the board still works from chat alone.

```
LFGBoardDB = {
    window = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    minimap = { angle = 125, hide = false },
    alerts = true,
    nearLevel = true,
    roles = { ["Skyler-Aldira"] = { tank = true, healer = false, dps = true } },
}
```

Every client call tries the namespaced API first and the old global second,
and every read that could raise goes through `ns.Guarded`, as in the repo's
other addons.

## Checked in game

After the build, on Forever, the group finder first, since the "party"
column rests on it:

1. Refresh searches the finder from the button, and the board shows the
   listed groups with their members' classes and roles (and whether the
   finder gives levels). Then `/lfgb finder` prints what the finder
   gave, raw; that output comes back with the answers.
2. A listed group that fills or delists leaves the board.
3. Chat posts appear, with the right activity and roles, and old ones go.
4. Whisper opens chat with the message typed, and the alert's [Whisper]
   link does the same.
5. An alert sounds for a tank or dps group near your level, once, and not
   while in a group.

If the finder cannot be read by an addon on Forever, `Finder.lua` is turned
off and the board runs on chat alone; that goes back to Carl.

## Testing

Lua specs with the repo's runner and a stubbed client (chat events, the
group finder's calls, units, talents, sounds, chat frames, timers):

- **Parse:** a table of real-looking messages: lower and upper case,
  run-together abbreviations (`lf1m sfk tank`), `LFG` posts skipped, guild
  posts skipped, `DM` vs `DME`, `need all`, sizes, `full`/`nvm`, unknown
  activity as Other, quest groups.
- **Posts:** replace by person, expire at 10 minutes, done removes, finder
  and chat merge by leader, a new search replaces finder rows, each filter
  and tab count, role defaults by class.
- **Finder:** results read with members and roles, 5 of 5 and delisted
  removed, Refresh searches the tab's category, the game's own searches are
  taken.
- **Whisper:** the message for each case (spec words, no points, unknown
  roles, Other), and chat opened with it.
- **Alerts:** only explicit role asks near your level, once per person and
  activity, not in a group, not your own, off by the switch, the link
  whispers.
- **Window:** rows, tabs and counts, switches saved, Refresh.

## Out of scope

Listing your own group, applying through the finder, inviting, players
looking for groups (LFG posts), other languages, Discord, channels other
than chat channels and guild, a settings panel beyond the board's own
switches.
