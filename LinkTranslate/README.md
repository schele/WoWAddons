# LinkTranslate (World of Warcraft AddOn)

Shows the quest, item and spell links people post in chat by the names your
game uses, whatever language the sender's game is in.

A player on a French client who links a quest sends its French title:

> [Tranzalorr]: Someoe for : [La fiancée de l'Embaumeur] ?

With LinkTranslate, an English client shows the same line as:

> [Tranzalorr]: Someoe for : [Bride of the Embalmer] ?

Clicking the link opens the same quest as before. Point at a link it changed
and a small tooltip shows what the sender's game called it, for when you
answer them or look it up on a site in their language.

## What it cannot do

- **Translate what people type.** Addons cannot reach the internet, and the
  game has no translator, so the words around a link stay as they were
  written. Only links carry something the game can name in your language: an
  id that is the same in every language.
- **Quests on Classic Era.** That client has no way for an addon to look a
  quest's name up by its id, so quest links stay as sent there. Items and
  spells still work.

## Settings and commands

It has a page in the game's options (Options, AddOns, LinkTranslate) with a
box for each switch: showing links by your game's names, and the tooltip on
a changed link. Both start on.

| Command | What it does |
|---|---|
| `/lt` | Open the settings page |
| `/lt on` | Show links in chat by your game's names |
| `/lt off` | Leave links in chat as they are sent |
| `/lt help` | List the commands |

## How it works

A link in chat is `|Hquest:2945:28|h[La fiancée de l'Embaumeur]|h`: the part
a click opens (`quest:2945:28`) and the text shown between the brackets, which
the sender's client wrote. LinkTranslate filters every line people type (say,
yell, whispers, party, raid, guild, channels) and swaps the text for your
client's own name for that id: `C_QuestLog.GetTitleForQuestID`,
`C_Item.GetItemInfo` (whose link keeps a suffix like "of the Tiger") and
`C_Spell.GetSpellName`. The link part is never touched.

A name your client has not loaded yet is asked for (`RequestLoadQuestByID`
and the like). When it arrives, the lines already in your chat windows are
rewritten through the windows' own `TransformMessages`, which Blizzard leaves
open to addons for this.

Not yet confirmed in the game: that Forever's client does not already show
other languages' item links in your own (if it does, LinkTranslate has nothing
to change for items, and leaves them alone), and that lines are rewritten once
a quest's name loads.

## Install

From the repo root:

    .\package.ps1 LinkTranslate -Install -NoWago

See the [repo README](../README.md) for packaging and test commands.

## Tests

The tests run outside the game against a stand-in for the client
(`tests/wow_stub.lua`) shaped after Forever's own chat code.

```powershell
.\run-tests.ps1 LinkTranslate
```
