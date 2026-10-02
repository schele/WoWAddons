# LFGBoard (World of Warcraft AddOn)

The groups that want you, on one board: recruiting posts from chat and the
listings in the game's group finder, filtered to the roles you play and the
dungeons near your level. Open it with the minimap button or `/lfgb`;
right-click the button, or `/lfgb settings`, for its page in the game's
options.

```
 When  Who            For              Said                     Party
 0:12  Garrok         Deadmines        LF2M DM need heals+dps   [T][D][D][+][+] room for H D   [Whisper]
 0:48  Elandra        Wailing Caverns  LFM WC, have tank        ?/5, needs H D                 [Whisper]
```

## Where the groups come from

- **Chat**, as it is said: every channel you are in except the defence ones,
  and guild chat. A message counts when it is recruiting: `LFM`, `LF2M`,
  `LF tank`, `need heals` and the like. A player's own `LFG DM` (someone
  looking for a group) is left out, and so is guild recruitment in the
  channels.
- **The group finder**, when you click **Refresh**: the game lets an addon
  search it only on a click. The board also picks up the results whenever
  the game's own finder window searches. Listed groups show their real
  members, one square per player in their class colour with their role, and
  what there is room for.

A row drops off ten minutes after it was last seen, at once when its poster
says `full`, `filled`, `nvm` or `no longer`, and at once when a listed group
fills or delists.

From what a chat post says, the Party column gives how many are in the
group (`LF1M` or `need 1 more` for a dungeon or quest is 4/5; a written
`3/5` or `35/40` is taken as it is; a raid's `LF2M` gives no count), the
roles it asks for, and under them the classes it asks for (`LF hunter`,
`need a priest`) in their colours and the ones it turns away (`no hunters`,
`rogue full`) dimmed after "no". Nothing in a link counts, and where a post
is not clear the board says nothing rather than guess.

## Filters

- **Tabs:** All, Dungeons, Quests, Raids, each with a count. Posts for
  something the board does not know show under All as "Other".
- **Dungeon:** click to step through the dungeons on the board, right-click
  to step back.
- **Tank, Healer, Damage:** the roles you play, kept per character. They
  start as your class allows. A group asking only for roles you have turned
  off is hidden; one that does not say stays.
- **Near my level:** hides dungeons and raids more than 3 levels outside
  their range.
- **Hide done quests:** hides a quest group whose linked quests you have
  all handed in. A quest named only in words cannot be checked, so it stays.
  On to begin with.

The same switches, and the minimap button's, are on LFGBoard's page in the
game's options (Options, AddOns).

A green edge marks a group that asks for one of your roles.

## Alerts

When someone posts in chat for a dungeon, raid or quest near your level and
asks for one of your roles or your class, you hear a sound and get one chat
line with a **[Whisper]** link. Once per person and dungeon, never while you
are in a group, never for a post the board cannot place ("Other") or one it
hides as a done quest, never for a group that says it is full (`5/5`), turns
your class away, or asks only for other classes, and off with the board's
Alerts switch. A Refresh never alerts: you are already looking.

## Whisper

The button opens a whisper with the message already typed, so Enter sends
it:

    Hi! Level 20 feral druid, tank or dps. Room for me in Deadmines?

Your level and class, your biggest talent tree, and the roles of yours the
group wants.

## Commands

| Command | Does |
|---|---|
| `/lfgb` | Open or close the board |
| `/lfgb minimap` | Hide or show the minimap button |
| `/lfgb settings` | Open the settings page |
| `/lfgb finder` | Print what the group finder gives, to check it is being read |
| `/lfgb help` | The commands |

## Install

1. Copy this folder into your client's `Interface/AddOns` as `LFGBoard`,
   so the result is `.../Interface/AddOns/LFGBoard/LFGBoard.toc`.
2. Restart the client and enable LFGBoard from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 LFGBoard -Install

See the [repo README](../README.md) for packaging and test commands.
