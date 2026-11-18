# AutoVendor: a junk list, picked from your bags

## Why

AutoVendor sells grey items only. Carl also wants items he chooses sold at
every merchant, typically low-level white items he has outgrown, and wants
to choose them on AutoVendor's options page by picking from what is in his
bags, not by typing a command.

## Goals

- A junk list: items sold at a merchant along with the greys, whatever
  their quality.
- Built on the options page: the items in your bags are shown there as
  icons, and a click puts one on the list.
- The list is shown on the same page, each item with a button to take it
  off.

## Non-goals

- No rules such as "white items more than 10 levels below me". Only items
  the player picked are sold.
- No picking for the keep list from the bag grid (it could come later: the
  grid would need a second action).
- No drag-and-drop, no clicking items in the bag windows themselves.

## Anti-goals

- Selling anything the player did not put on the list, or a grey they put
  on the keep list.
- Selling an item with no sell price, or one that is locked (the same
  rules greys follow).

## Approaches

1. **Your bags shown on the options page (picked).** A grid of icons, one
   per kind of item. Hover for the tooltip, click to add. Self-contained;
   most work; the page must scroll.
2. A slot on the page to drag items onto from the open bags. Quick to build,
   but needs the bags open beside the Options window, which is unverified on
   Forever.
3. An "Add from bags…" button opening a menu of bag items. Compact, but long
   with full bags, and leans on the game's menu system.

Carl picked 1: it is literally "choose an item from my bags" and does not
depend on how the Options window and the bags get along.

## The design

**Carl's choices:** a junk list of items he picks; picked from a grid of his
bag items on the options page.

**Calls made here** (correct any):

- The list is per account, like the keep list: `AutoVendorDB.junk`,
  `{ [itemID] = name }`. Saved variables persist on Forever now, so it is
  remembered.
- An item is on one list at most. Adding it to the junk list takes it off
  the keep list and the other way round, and says so in chat.
- Selling: a bag slot is sold when it holds a grey or an item on the junk
  list, has a sell price, is not locked, and is not on the keep list. Same
  pace, same chat line ("Sold 7 items for …"), same Buyback caveat.
- The existing "Sell grey items" switch (and `/av sell`) covers both, and
  reads "Sell grey items and my junk list".
- The grid shows each kind of item in the bags once: not grey (sold
  anyway), with a sell price, not already on either list. Sorted by name.
  Hover shows the item's tooltip; a click adds it. It redraws when the bags
  change while the page is open, and after every add or remove.
- The page, top to bottom: description, the three switches, "Never sold"
  (keep list, as now), "Always sold" (junk list, each row with a
  "Stop selling" button), "In your bags (click to always sell)" (the grid).
  The page scrolls, as ForeverPanel's options page does, since the grid and
  two lists can outgrow the window.
- Commands, for parity with the keep list and for chat links:
  `/av junk` and `/av unjunk` with a Shift-clicked item or an item number;
  `/av list` shows both lists.

```
Never sold
 [Sell again]   [Ironforge Ale]
Always sold
 [Stop selling] [Tough Jerky]
 [Stop selling] [Small Pouch]
In your bags (click to always sell)
 [ico][ico][ico][ico][ico][ico][ico][ico]
 [ico][ico][ico]
```

## Left to the builder

Icon size and spacing, how the grid wraps to the page width, the empty
texts ("Nothing is always sold…", "Nothing else in your bags can be sold"),
README and `.toc` Notes wording, and the version number (0.3.0) at release.
