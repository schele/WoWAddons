# LFGBoard (World of Warcraft AddOn)

The groups that want you, on one board: recruiting posts from chat and the
listings in the game's group finder, filtered to the roles you play and the
dungeons near your level. Open it with the minimap button or `/lfgb`.

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

A green edge marks a group that asks for one of your roles.

## Alerts

When a group asks for one of your roles in a dungeon near your level, you
hear a sound and get one chat line with a **[Whisper]** link. Once per
person and dungeon, never while you are in a group, and off with the
board's Alerts switch.

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
| `/lfgb help` | The commands |

## Install

1. Copy this folder into your client's `Interface/AddOns` as `LFGBoard`,
   so the result is `.../Interface/AddOns/LFGBoard/LFGBoard.toc`.
2. Restart the client and enable LFGBoard from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 LFGBoard -Install

See the [repo README](../README.md) for packaging and test commands.
