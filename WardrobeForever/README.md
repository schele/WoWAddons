# WardrobeForever (World of Warcraft AddOn)

Hover a slot on the character sheet to see everything else you could wear
there, and click one to put it on.

Blizzard's character sheet already has this list. Hold Alt over a slot and
it pops out beside the slot with every item in your bags that fits.
WardrobeForever opens that same list when you simply rest the mouse on the
slot. No Alt, and nothing new to learn: the look, the paging and the
click-to-wear are all Blizzard's.

## How it behaves

- **It opens when you hover a slot you can change.** If anything you are not
  wearing fits the slot, the list opens. If not, you just get the slot's
  tooltip, same as before. Your other ring or trinket does not count as
  something to change to.
- **It stays open while the mouse is on the slot or the list.** Moving
  across the small gap between them is fine. It closes about a third of a
  second after the mouse has left both.
- **Clicking an item puts it on and closes the list.** Hover the slot again
  to open it again.
- **Moving to another slot moves the list with you.** A slot with nothing to
  change to closes it straight away, so its tooltip is not left sitting
  beside the old list.
- **Alt still works the way it always did.** WardrobeForever does not touch
  the Alt setting, so turning the addon off puts everything back as it was.
- **A list you pinned with the arrow stays pinned.** The arrows beside each
  slot on the equipment manager tab pin a list open, and WardrobeForever
  leaves a pinned list alone.

What is in the list is what Blizzard puts in it: what is in your bags, plus
"put in bags" for the item you are wearing. In combat, Blizzard only lets
you change weapons, and it shows an error if you try anything else.

## How it works

Blizzard keeps the list open without Alt in one case: when the slot's arrow
is pinned. Hovering a slot that has something to change to pins it the same
way, so Blizzard's own code opens the list, lays it out and moves the tooltip.
WardrobeForever only adds closing it again once the mouse has moved away.

## Install

From the repo root:

    .\package.ps1 WardrobeForever -Install

See the [repo README](../README.md) for packaging and test commands.

Built for the Forever client (1.60.x, `16001`). On a client without
Blizzard's equipment list it loads and does nothing.

## Tests

The tests run outside the game against a stand-in for the character sheet
(`tests/wow_stub.lua`). The pop-out's open, stay-open and close decisions in
that stand-in are copied from Blizzard's own code for this client, because
the hard part is surviving Blizzard's every-frame check that hides the list
when Alt is not held.

```powershell
.\run-tests.ps1 WardrobeForever
```

What the tests prove is that WardrobeForever asks Blizzard's list to open and
close at the right moments. Whether it looks right on screen is something
only the client can answer.
