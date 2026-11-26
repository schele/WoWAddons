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

## Gear for each form

Pick one of your equipment sets for a form, say Cat Form, and shifting into
the form puts it on. Shifting out puts back what you had on.

- **The sets are the game's own.** Make them on the character sheet: the
  arrow at its top right, then the Equipment Manager tab (New Set, then
  Save). Choose one for each form in Options, AddOns, WardrobeForever.
  "Leave gear alone" is the default.
- **Only the slots in the set change.** Slots the set ignores stay as they
  are.
- **Shifting out puts back what you had on before.** Your gear in any form
  is your normal gear with that form's set on top, so Cat to Travel (no set)
  brings your normal gear back, and Cat to Bear goes straight to Bear's set.
- **In a fight, it all waits for the fight to end.** The game lets no
  addon change gear in combat, weapons included (you can still swap by
  hand), so WardrobeForever does not try. When the fight ends, the gear
  for whichever form you are in by then goes on.
- **It waits while you cast or are dead**, and carries on when the cast
  ends or you are back on your feet.
- **Your own changes win.** A slot you change by hand while shifted stays
  as you left it until your next shift, and is not put back when you leave
  the form.
- **A swap the game keeps turning down** (say, no bag space for the
  off-hand a two-hander pushes off) is tried three times, then left until
  your next shift.
- **It survives /reload and logging out.** Reload in Cat Form and your
  normal gear still comes back when you leave it.
- **It keeps your choices.** Bear Form's set carries over to Dire Bear Form
  at level 40. A set you delete stops being worn, and a renamed set keeps
  working.

Works for any class's forms or stances: whatever is on your stance bar.

It has a page in the game's options (Options, AddOns, WardrobeForever): what
hovering does, and the set to wear in each form.

## How it works

Blizzard keeps the list open without Alt in one case: when the slot's arrow
is pinned. Hovering a slot that has something to change to pins it the same
way, so Blizzard's own code opens the list, lays it out and moves the tooltip.
WardrobeForever only adds closing it again once the mouse has moved away.

The form sets (`Forms.lua`) work out the gear wanted: the normal gear,
remembered when a set first changes a slot, with the current form's set on
top. It is put on when something asks for it (a shift, the end of a fight,
a new choice, a change to the sets); any other gear change only finishes
that work or notices a slot changed by hand. Items move one slot at a time
with the cursor, the way Blizzard's pop-out does. The game answers each
swap a moment later, so a slot counts as done only once the item is seen in
it, and neither weapon hand moves while the other is on its way. Items are
known by GUID, so two of the same ring are told apart. The remembered gear
is saved per character (`WardrobeForeverCharDB`). Nothing is tried while
`InCombatLockdown()`: Forever blocks addons from equipping then, weapons
too ("Interface action failed because of an AddOn").

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

The form sets run against the same stand-in, which also holds worn and
bagged items, the cursor's swap, Forever's block on equipping in combat,
the stance bar and the equipment sets. It swaps at once by default; `helpers.async` makes
it answer later the way the client does (items locked until `land` or
`refuse`), and the specs for in-flight swaps use that. What the client
really sends, and in which order, is still for the game to prove.
