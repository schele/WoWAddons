# MailHandler (World of Warcraft AddOn)

Open the mails you choose, not all or none. Every mail in your inbox gets a
checkbox; **Open** takes the gold and items of the ticked ones only, beside
the game's own **Open All**, and **Forward** sends them on to someone else.

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

## Forward

The game has no forward, so MailHandler makes one: a new mail from you
with the forwarded mails' gold and items.

```
 [x] Select all                        [ Forward (2) ]
```

- **Forward (N)**, top right of the inbox, forwards the ticked mails.
- **Forward**, left of Reply on an open mail, forwards that one, with its
  text (an auction house invoice is written out: what was bought, from
  whom).

Either way MailHandler switches to the **Send Mail** tab, takes each
mail's gold and items, oldest first, and puts the items on the tab as
they come. The subject says what is forwarded (`FW: Linen Cloth (20)`, or
`FW: 6 mails`), the text lists each mail's sender and subject, and the
gold goes in as gold sent, never as cash on delivery. The name is the
one this character last forwarded to, or else your default recipient;
type another over it if you like.
**You press Send.** When it has gone, one chat line:

    Forwarded 6 mails to Brakka: 1g 23s 4c, 6 items.

- **Twelve items fit in a mail.** With more, MailHandler fills one, says
  so, and once you have sent it fills the next, to the same name. Full
  bags do the same: send what is on the tab, and the rest follows.
- An item that topped up a stack of your own is split back off, so the
  mail carries just what the mail you forwarded did.
- A **cash-on-delivery** mail is skipped. An item that cannot be mailed
  (soulbound) stays in your bags, and the chat line says so.
- On WoW Forever, the game may ask before sending items or gold to a
  player it counts as a stranger: accept its warning to send.
- Open and Forward wait for each other. Closing the mailbox stops a
  forward; what was taken is in your bags.

## Who new mail goes to

Pick a default recipient, usually your bank character, and every new mail
starts with that name in **To**.

- **The arrow** at the right end of the To box lists your other characters
  on this realm and side, each in its class colour, with the default
  picked. Pick one and it becomes the default and goes in To now. A name
  you have typed in To is on the list too, for a character MailHandler
  has not seen yet; **Nobody** takes the default away.
- The name goes in To when the Send Mail tab opens, and again once a mail
  has gone, ready for the next. It is selected, so typing another name
  replaces it. A name already in To is left alone, and Reply still fills
  in the sender.
- **Shared** by your characters on the realm and side, since they all send
  to the same bank character. That character's own To stays empty: nobody
  mails themselves.
- **Your characters:** the game has no list of an account's characters, so
  MailHandler notes each one as it logs in. Log in on each once and they
  are on the list; until then, type the name in To and pick it.
- A forward goes to whom this character last forwarded to, as before, or
  else to the default.

The settings page (Options, AddOns, MailHandler) shows the default under
**New mail goes to**, and changes it from the same list.

## Subject

The game will not send a mail without a subject, and on WoW Forever it
never writes one for you. MailHandler does, on the **Send Mail** tab,
while the subject is empty:

    Chunk of Boar Meat (77), Lean Venison (4) and 2 more

- Every item on the mail, its stacks added up, in the order they went
  on, as many as fit in the subject, then how many more.
- A mail with gold and no items gets the gold: `1g 23s 45c`.
- It follows the items as you put them on and take them off. Type a
  subject of your own and it is left alone; so is a reply's, and a
  forward's.
- A letter with nothing in it keeps an empty subject, for you to write.
- On Classic Era, where the game names the first stack, MailHandler
  names every item instead.

## Install

1. Copy this folder into your client's `Interface/AddOns` as `MailHandler`,
   so the result is `.../Interface/AddOns/MailHandler/MailHandler.toc`.
2. Restart the client and enable MailHandler from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 MailHandler -Install

See the [repo README](../README.md) for packaging and test commands.
