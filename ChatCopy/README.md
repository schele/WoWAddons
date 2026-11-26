# ChatCopy (World of Warcraft AddOn)

Copy text out of chat. A chat window's lines open in a box where you mark any
part with the mouse, and the links people post become clickable, each opening
in a box with the whole address selected.

WoW's chat frame cannot be selected with the mouse, so a guild message, a
group's plan or a link someone types is readable but out of reach. ChatCopy
closes that gap.

**WoW has no clipboard API.** No addon can copy anything for you, and any that
claims to is doing something else. What ChatCopy can do is put the text in a
focused box, a link already selected, so Ctrl+C is one keystroke. That is the
ceiling for the whole category, and it is what this addon does.

## Copying chat

Move the mouse over a chat window and a small ChatCopy button shows in its
top-right corner. Click it, or type `/cc chat` in the tab you want, and that
window's lines open in a box:

- The lines are plain text, oldest first, with the newest at the bottom.
  Colours and icons are gone, and links read as their `[Name]`.
- Drag with the mouse to mark any part, then press Ctrl+C. Escape closes the
  box.
- Typing into the box changes nothing.

The box holds every line the chat window still keeps. The combat log gets no
button. This client can keep some chat lines from addons. Any line ChatCopy
may not read is left out, and the box says how many it left out.

## Copying links

A web address in chat turns blue and clickable. Click it and it opens in a
box, selected, ready for Ctrl+C. `/cc 1` does the same for the most recent
link, and `/cc list` shows the last few, so a link that has scrolled away is
still in reach.

| Written as | Example |
|---|---|
| A full URL | `https://example.com/a/b?c=d` |
| A `www.` address | `www.example.co.uk/path` |
| A server address | `62.109.4.12:3724` |
| A bare domain | `example.com`, `discord.gg/abcdef` |

Bare domains are only picked up for a list of common top-level domains.
`.no`, `.it`, `.me`, `.at`, `.is` and their like are deliberately left out:
they are real domains, but they also end ordinary sentences, and turning
"wait.no" into a link is a worse failure than missing an unusual address.
Written with `https://` or `www.`, they work anywhere.

A bare `1.14.4.2` is left alone too — in this game that is a patch number far
more often than it is a server.

## Closing a linked item

Click an item, spell or quest link in chat and its tooltip opens; click the
same link again and it closes. The game means to do this itself but never
does, so without ChatCopy the second click just draws the tooltip again.

## Install

1. Copy this folder into your client's `Interface/AddOns` as `ChatCopy`, so the
   result is `.../Interface/AddOns/ChatCopy/ChatCopy.toc`.
2. Restart the client and enable ChatCopy from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 ChatCopy -Install

See the [repo README](../README.md) for packaging and test commands.

Built for WoW Forever (1.60.x, `16001`) and Classic Era 1.15.x (`11509`).

Before its first release it was called UrlCopy. Its settings do not carry
over, and an old `Interface/AddOns/UrlCopy` folder should be deleted, or both
run at once.

## Commands

`/chatcopy` or the short `/cc` (the old `/url` still works):

- `/cc` - Show the command list
- `/cc chat` - Open the chat tab you are looking at, to mark and copy its text
- `/cc 1` - Copy the most recent link
- `/cc <n>` - Copy the nth link from `/cc list`, newest first
- `/cc list` - List the links being remembered
- `/cc clear` - Forget them
- `/cc on` / `/cc off` - Whether links in chat are made clickable at all
- `/cc minimap` - Hide or show the minimap button
- `/cc settings` - Open the settings panel

## Settings

In the game's Options under AddOns, or from the minimap button:

| Setting | Does |
|---|---|
| Make URLs in chat clickable | The master switch for links. Off leaves chat exactly as it arrives |
| Shorten long links | Show just the site's name in chat for a long link; the box still gets the whole URL |
| Links to remember | How many `/cc list` keeps, from 5 to 25 |
| Copy button on chat windows | The button in a chat window's corner. `/cc chat` works with it off |
| Click a link again to close it | A second click on the link a tooltip is showing closes it. Off leaves the game's own behaviour |
| Show the minimap button | The round button on the minimap's rim |

Links are remembered whether or not chat is being rewritten, so `/cc 1` keeps
working with the master switch off. That is what makes the switch safe to
reach for if the rewriting ever gets in your way.

The list is kept for the session only and is never saved.

## How it works

`Detect.lua` finds URLs in a string and touches no part of the game, which is
what lets the fiddly half of this addon be tested outside the client.

`Chat.lua` registers a `ChatFrame_AddMessageEventFilter` on the chat events and
rewrites each URL it finds into `|Hchatcopy:<url>|h|cff66ccff[<display>]|r|h`,
one of the game's own hyperlinks with a type of our own. Clicks arrive through
a `hooksecurefunc("SetItemRef", ...)`, which leaves every other link type
reaching the client's handler untouched.

`ChatText.lua` reads a chat window's lines back with the frame's own
`GetNumMessages` and `GetMessageInfo`, and strips the markup off them. It reads
each line inside a `pcall`, so a line the client will not let it read is
skipped and counted, and never stops the rest. The buttons are parented to the
chat frames, and a light `OnUpdate`, ten times a second, shows each one while
the mouse is over its window.

`LinkTooltip.lua` puts right a slip in Forever's own `ItemRefTooltip`. Its
`SetHyperlink` hides the tooltip when asked for the link it already holds,
but compares the new link against one packed with `SafePack`, whose extra `n`
field `tCompare` counts as a difference, so it never matches. A
`hooksecurefunc` after `SetHyperlink` remembers the link while the tooltip
stays open and hides the tooltip on a repeat. A client that gets the check
right has already hidden it, and the hook then does nothing.

The URL travels inside the link rather than as an index into the history, so a
link that has scrolled up still works long after the history has moved on.

A URL can never contain a `|`. That is the game's escape character, and a link
holding one would let a crafted message close our link early and write its own
markup into your chat frame. The character appears in none of the classes the
scanner matches with, so a pipe ends a match instead of being swallowed by it.

## Tests

The detection, rewriting, history, chat text and settings logic is covered by
unit tests that run outside the game against a stubbed WoW API
(`tests/wow_stub.lua`).

From the repo root:

```powershell
.\run-tests.ps1 ChatCopy
```

Or a single suite by hand, from this folder:

```
lua tests/runner.lua tests/detect_spec.lua
```

The chat frame itself can only really be confirmed in the game client; the
tests cover the logic around it.
