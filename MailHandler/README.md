# MailHandler (World of Warcraft AddOn)

Open the mails you choose, not all or none. Every mail in your inbox gets a
checkbox; **Open** takes the gold and items of the ticked ones only, beside
the game's own **Open All**.

```
 [x] Alliance Auction House   Auction successful: Rough Stone (46)
 [x] Alliance Auction House   Auction successful: Copper Bar (60)
 [ ] Alliance Auction House   Auction expired: Bronze Bar (12)
        [ Open (2) ]  [ Open All ]
```

Collect your auction sales and leave the expired items in the mailbox for
when you have bag space, or relist them later.

## Ticking

- A checkbox left of each mail. A tick stays with its mail across pages
  and as mails above it are taken.
- **Select all**, under the title, ticks every mail on every page; click it
  again to untick them all.
- Ticks are forgotten when you close the mailbox.

## Open

**Open (N)** takes the gold, then each item, of every ticked mail, one at a
time so the server keeps up, starting with the oldest at the bottom. When it
is done, one chat line:

    Opened 4 mails: 1g 23s 4c, 3 items.

- It **never deletes a mail**. The game itself may remove an empty auction
  mail once its gold is taken.
- A **cash-on-delivery** mail is skipped and the line says so: MailHandler
  never pays for one.
- When your **bags are full** it stops and says how many ticked mails are
  left. Closing the mailbox stops it too.

**Open All** is the game's own button, moved over to make room. On a
client without one, MailHandler adds its own.

## Install

1. Copy this folder into your client's `Interface/AddOns` as `MailHandler`,
   so the result is `.../Interface/AddOns/MailHandler/MailHandler.toc`.
2. Restart the client and enable MailHandler from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 MailHandler -Install

See the [repo README](../README.md) for packaging and test commands.
