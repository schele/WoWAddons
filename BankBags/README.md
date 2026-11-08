# BankBags (World of Warcraft AddOn)

Your bank, and every character's, from anywhere in the world.

The game only sends a bank's contents while you stand at a banker, so
BankBags saves a copy each time you open your bank, and again after every
change while it is open. Open the window with `/bb` or the minimap button to
see it anywhere: the main bank first, then each bank bag under its name. Hover
an item for its tooltip; shift-click links it in chat. The search box dims
everything that doesn't match. The button under the title steps through each
character whose bank is saved (right-click to go back); the footer says when
the copy was made.

## Quest items in the bank

The saved copy also goes on the quest tracker. Forever's objective count is
no guide to your bank: it can say `14/14 Golem Isospring` with 7 of them
banked, or `0/3 Boar Intestines` with 12 of them banked. Whenever your bags
hold too few for an item objective, BankBags adds how many are in the bank:

```
0/3 Boar Intestines (12 in bank)
```

- It counts this character's saved bank, so it knows nothing until you have
  opened the bank once with BankBags installed.
- **Your other characters' banks** on the same realm, the ones you can mail
  from, are added when your bags and your own bank together still fall short:
  `0/3 Boar Intestines (1 in bank, 5 on Morwen)`, each by name, the one
  with the most first.
- **A ticked objective you can't hand in yet is red.** When the tracker shows
  an objective as done but your bags hold too few, the note is red, and if
  nothing is banked anywhere it says how many you carry:
  `14/14 Golem Isospring (7 carried)`.
- Nothing is added when your bags hold enough, and only item objectives get
  a note.
- It follows the items: take them out of the bank, or put some in, and the
  note updates.
- It never makes a tracker line taller. A note that would wrap is written
  short (`(12 bank)`, `(5 Morwen)`), then drops the alts from the end, and if even
  the shortest would wrap, nothing is added.
- It only changes the words on the line, after the tracker has drawn it. The
  tracker's quest item buttons use items, which only the game's own code may
  do, and an addon that meddles with the tracker's data can break them in
  combat.

**At the bank**, as it opens, chat lists what to take out for the quests in
your log, one line each, never more than the bank holds or than your bags
fall short by:

```
BankBags Take out 3 Boar Intestines for Thelsamar Blood Sausages (12 in the bank).
```

## Bank counts in tooltips

Item tooltips get a line for each saved bank holding the item: yours first,
then your other characters' on the same realm, by name.

```
Bank          12
Morwen's bank  5
```

They show on the item's own tooltip and on a linked item's, not on the
comparison tooltips beside them.

## Settings

Each of these is a checkbox on the settings page (`/bb settings`), all on to
begin with:

| Setting | Does |
|---|---|
| Show quest items in the bank on the quest tracker | The tracker notes |
| Count my other characters' banks on this realm | Adds alts to the notes |
| Mark ticked objectives I can't hand in yet in red | The red notes, and `(7 carried)` |
| At the bank, list the quest items to take out | The list in chat at a banker |
| Show bank counts in item tooltips | The tooltip lines |

## Commands

- `/bb` or `/bankbags` - open or close the window
- `/bb forget <name>` - forget a character's saved bank
- `/bb minimap` - hide or show the minimap button
- `/bb settings` - open the settings page in the game's options, which also lists the saved banks, each with a Forget button
- `/bb help` - list the commands

## Install

    .\package.ps1 BankBags -Install

See the [repo README](../README.md) for packaging and test commands.
