# MailHandler Design

**Date:** 2026-10-02
**Status:** approved in chat (with a mockup on Carl's own inbox); checked in game after the build (see "Checked in game")

## Purpose

Open the mails you choose, not all or none.

After a round on the auction house the inbox holds sales (gold) and expired
auctions (items back). The game's Open All takes everything; often the gold
is wanted now and the items are not, because the bags are full or they are
going back up for sale. MailHandler puts a checkbox on every mail and an
**Open** button that opens only the ticked ones.

## What it looks like

On the game's own inbox, changed as little as possible:

- **A checkbox left of each mail's icon**, on every row the inbox shows.
- **Select all**, a checkbox with that label in the dark band under the
  title.
- **Open (N)** beside the game's **Open All** at the bottom, N being how
  many mails are ticked. The game's Open All is moved right, not changed.

The agreed mockup is the inbox from Carl's screenshot with the four
"Auction successful" mails ticked and **Open (4)** beside **Open All**.

## Ticks

- A tick belongs to the mail, not to the row: it survives Prev and Next,
  and stays with its mail when mails above it are taken and the list moves
  up.
- A mail is known by what it holds: sender, subject, gold, cash on delivery
  and item count. Two mails alike in all of these (two equal sales) are
  told apart by their order among themselves.
- **Select all** ticks every mail in the box, on every page; clicking it
  again unticks them all. It shows ticked only while every mail is.
- Ticks are forgotten when the mailbox closes. Nothing is saved.

## Open

**Open (N)** is greyed out while nothing is ticked. Clicked, it works
through the ticked mails, top to bottom, one step at a time:

1. The mail's gold, if any (`TakeInboxMoney`).
2. Each of its items, one at a time (`TakeInboxItem`).
3. The mail is unticked once it holds neither.

Between steps it waits for the server: a step is done when the mail's gold
or item is seen gone, and it waits up to about two seconds (in 0.25-second
looks) before giving that step up. A mail is read afresh before every step,
so mails moving or new mail arriving do not confuse it.

- **Never deletes a mail.** The game itself may remove an empty auction
  mail once its gold is taken; MailHandler does not stop that.
- **Cash on delivery:** such a mail is skipped and unticked, and the line
  says so. MailHandler never pays for one.
- **Bags full:** before taking an item it checks for a free bag slot; with
  none it stops and the line says so. Gold is still taken from mails before
  that point.
- **The mailbox closing** stops it.
- **Clicking Open again while it runs** does nothing.

When it stops, one chat line in the game's coin icons:

`Opened 4 mails: 1g 23s 4c, 3 items.`

with, where they apply, `Skipped 1 cash-on-delivery mail.` and
`Bags are full: 2 ticked mails left.` added. The gold is what the player's
money rose by from start to end.

## Open All

The game's own button, untouched apart from where it sits. On a client
without one (Classic Era may not have it), MailHandler adds its own **Open
All**, which ticks every mail and opens them as **Open** does.

## Architecture

| File | Responsibility |
|---|---|
| `MailHandler.toc` | `Interface: 11509, 16001`, `IconTexture`. No `SavedVariables` |
| `MailHandler.lua` | Namespace, `ns.Print`, `ns.Guarded`, `ns.Money`, login |
| `Inbox.lua` | Reading only: every mail as `{ index, key, sender, subject, money, cod, items }`, its attachments, and free bag slots |
| `Ticks.lua` | The ticked keys, Select all, the count |
| `Opener.lua` | The steps above, the waiting, the stops, the line |
| `Buttons.lua` | A checkbox on each inbox row after every redraw, Select all, Open (N), Open All where missing |

Plus `README.md`, `icon.tga` (an envelope, drawn by `tools/draw-icons.mjs`)
and a row in the root README's table.

The rows are the game's `MailItem1` to `MailItem7`; the checkboxes are laid
on them after each `InboxFrame_Update`, read against
`InboxFrame.pageNum`. Every client call tries the namespaced API first where
one exists (`C_Container.GetContainerNumFreeSlots`), and every read that
could raise goes through `ns.Guarded`.

## Checked in game

After the build, at a mailbox on Forever:

1. The checkboxes appear on the rows and follow Prev and Next.
2. Open takes only the ticked mails' gold and items; the line's gold
   matches the money gained.
3. What the game does with an empty auction mail (removed or kept).
4. Bags full stops it with the line saying so.

The answers go into this section.

## Testing

Lua specs with the repo's runner and a stubbed client (an inbox of mails
with gold and items, a server that answers late, bag slots, the game's
inbox rows and Open All button, timers):

- **Inbox:** mails read with their keys; alike mails told apart; free
  slots counted; a mail that will not read is skipped.
- **Ticks:** a tick survives paging and mails moving up; Select all ticks
  every page and unticks; its own box follows; the count.
- **Opener:** only ticked mails opened, gold then items; never deletes;
  cash on delivery skipped; bags full stops; the mailbox closing stops;
  a late server is waited for; a step the server never answers is given
  up; the line adds up; Open while running does nothing.
- **Buttons:** a box on each row for the right mail after a redraw and a
  page change; Open (N) counts and greys; the game's Open All moved, not
  replaced; Open All added where it is missing.

## Out of scope

Deleting mail, returning mail, sending mail, opening by rules (only sales),
remembering ticks between visits, a settings panel.
