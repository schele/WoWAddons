# UrlCopy (World of Warcraft AddOn)

Makes URLs spoken in chat clickable, and opens the one you click in a box you
can copy from.

WoW's chat frame cannot be selected with the mouse, so a link someone types is
readable but out of reach. UrlCopy closes that gap. It does the same for the
rest of chat: a chat window's text opens in a box where you mark any part of
it with the mouse and copy it.

**WoW has no clipboard API.** No addon can copy anything for you, and any that
claims to is doing something else. What UrlCopy can do is put the link in a
focused, fully selected box, so Ctrl+C is one keystroke. That is the ceiling
for the whole category, and it is what this addon does.

## What it picks up

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

## Copying chat

Move the mouse over a chat window and a small UrlCopy button shows in its
top-right corner. Click it, or type `/url chat` in the tab you want, and that
window's lines open in a box:

- The lines are plain text, oldest first, with the newest at the bottom.
  Colours and icons are gone, and links read as their `[Name]`.
- Drag with the mouse to mark any part, then press Ctrl+C. Escape closes the
  box.
- Typing into the box changes nothing.

The box holds every line the chat window still keeps. The combat log gets no
button. This client can keep some chat lines from addons. Any line UrlCopy
may not read is left out, and the box says how many it left out.

## Install

1. Copy this folder into your client's `Interface/AddOns` as `UrlCopy`, so the
   result is `.../Interface/AddOns/UrlCopy/UrlCopy.toc`.
2. Restart the client and enable UrlCopy from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 UrlCopy -Install

See the [repo README](../README.md) for packaging and test commands.

Built against Classic Era 1.15.x (`11509`) and the 1.60.x Classic beta
(`16001`). For retail, change `## Interface` in the .toc to the current retail
interface version.

## Commands

`/urlcopy` or the short `/url`:

- `/url` - Show the command list
- `/url 1` - Copy the most recent link
- `/url <n>` - Copy the nth link from `/url list`, newest first
- `/url list` - List the links being remembered
- `/url clear` - Forget them
- `/url chat` - Open the chat tab you are looking at, to mark and copy its text
- `/url on` / `/url off` - Whether chat is rewritten at all
- `/url settings` - Open the settings panel

## Settings

| Setting | Does |
|---|---|
| Make URLs in chat clickable | The master switch. Off leaves chat exactly as it arrives |
| Shorten long links | Show just the site's name in chat for a long link; the box still gets the whole URL |
| Links to remember | How many `/url list` keeps, from 5 to 25 |
| Copy button on chat windows | The button in a chat window's corner. `/url chat` works with it off |

Links are remembered whether or not chat is being rewritten, so `/url` keeps
working with the master switch off. That is what makes the switch safe to
reach for if the rewriting ever gets in your way.

The list is kept for the session only and is never saved.

## How it works

`Detect.lua` finds URLs in a string and touches no part of the game, which is
what lets the fiddly half of this addon be tested outside the client.

`Chat.lua` registers a `ChatFrame_AddMessageEventFilter` on the chat events and
rewrites each URL it finds into `|Hurlcopy:<url>|h|cff66ccff[<display>]|r|h`,
one of the game's own hyperlinks with a type of our own. Clicks arrive through
a `hooksecurefunc("SetItemRef", ...)`, which leaves every other link type
reaching the client's handler untouched.

`ChatCopy.lua` reads a chat window's lines back with the frame's own
`GetNumMessages` and `GetMessageInfo`, and strips the markup off them. It reads
each line inside a `pcall`, so a line the client will not let it read is
skipped and counted, and never stops the rest. The buttons are parented to the
chat frames, and a light `OnUpdate`, ten times a second, shows each one while
the mouse is over its window.

The URL travels inside the link rather than as an index into the history, so a
link that has scrolled up still works long after the history has moved on.

A URL can never contain a `|`. That is the game's escape character, and a link
holding one would let a crafted message close our link early and write its own
markup into your chat frame. The character appears in none of the classes the
scanner matches with, so a pipe ends a match instead of being swallowed by it.

## Tests

The detection, rewriting, history and settings logic is covered by unit tests
that run outside the game against a stubbed WoW API (`tests/wow_stub.lua`).

From the repo root:

```powershell
.\run-tests.ps1 UrlCopy
```

Or a single suite by hand, from this folder:

```
lua tests/runner.lua tests/detect_spec.lua
```

The chat frame itself can only really be confirmed in the game client; the
tests cover the logic around it.
