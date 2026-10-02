# AutoVendor Design

**Date:** 2026-10-02
**Status:** approved in chat; checked in game after the build (see "Checked in game")

## Purpose

Sell the junk and fix the gear without clicking either.

Every merchant visit means dragging each grey item to the merchant window and
pressing Repair All. AutoVendor does both the moment a merchant opens, and
says in one chat line what it earned and spent.

## What it does

When a merchant window opens, without asking:

1. **Sells your junk**, one item at a time with a short pause between them.
2. **Repairs your gear**, after the selling, so the junk's gold helps pay.
3. **Says what happened** in one chat line, in the game's coin icons:
   `Sold 7 items for 1g 23s 4c. Repaired for 45s.` Either half is left out
   when it did not happen; nothing is printed when neither did.

## What counts as junk

An item in your bags (backpack and bags 1 to 4) that is all of:

- **grey** (Poor quality, quality 0);
- **worth something** to a merchant: an item with no sell price is skipped,
  since the merchant will not take it, which also spares most quest items;
- **not on the keep list**;
- **not locked** (being traded, moved, or already on its way to a merchant).

White items, trade goods and everything better are never sold.

## Selling

- One item per **0.2 seconds**: a server sent sales too fast refuses some
  ("That object is busy") and leaves greys behind. The in-game check may
  tune the pause.
- Each step reads the bags afresh and sells the first junk slot it has not
  already tried, so loot arriving mid-visit is picked up and nothing is tried
  twice.
- A sale is only asked for: the slot empties when the server answers. The
  next item waits until it has (up to about a second, five pauses), and a sale
  counts only once its slot no longer holds the item. One the merchant hands
  back, or the server never answers, is dropped uncounted. The line reports
  what left the bags, and the repair waits for the junk's gold.
- **Closing the merchant stops it.** The line then reports what had sold, and
  no repair happens (there is no merchant to repair at).
- The merchant opening again starts a new visit. A second open signal during
  a visit is ignored.

"Sold 7 items" counts items, not sales: a stack of 5 Broken Fangs and one
grey sword are 6 items. The gold is each sold item's sell price times its
count.

## Repairing

After selling, only if the merchant can repair (`CanMerchantRepair`) and
something needs it (`GetRepairAllCost` above 0):

- **Enough gold:** `RepairAllItems()`, and the line says
  `Repaired for 45s.` with the cost the merchant quoted.
- **Not enough gold:** nothing is repaired, and the line says
  `Not enough gold to repair (costs 1g 2s).`

Classic has no guild-bank repairs; AutoVendor always pays from your own gold.

## The keep list

Items AutoVendor never sells, by item ID. Account-wide: every character
shares one list, kept in `AutoVendorDB`.

| Command | Does |
|---|---|
| `/av keep <item>` | Adds it. `<item>` is a Shift-clicked link or an item number. Says `Keeping [Broken Fang]: it will not be sold.` |
| `/av unkeep <item>` | Removes it. Says `No longer keeping [Broken Fang].` |
| `/av list` | Every kept item, one per line, or `Nothing is on the keep list.` |
| `/av` or `/av help` | The commands. |

`/autovendor` works the same as `/av`. Adding an item already on the list,
or removing one that is not, says so rather than failing silently. Input
that is neither a link nor a number gets the help.

## Things worth knowing (for the README)

- The merchant's Buyback tab holds your last 12 sales. With more than 12
  greys, the earliest cannot be bought back; that is what the keep list is
  for.
- To pause AutoVendor, disable it in the AddOns list. There is no settings
  panel: everything it does is automatic by design.

## Architecture

Shaped like FishScale: a core file with defaults, `ns.Print`, `ns.Guarded`
and a command registry, and one file per job.

| File | Responsibility |
|---|---|
| `AutoVendor.toc` | `Interface: 11509, 16001`, `SavedVariables: AutoVendorDB`, `IconTexture` |
| `AutoVendor.lua` | Namespace, defaults and `ns.db`, `ns.Print`, `ns.Guarded`, `ns.Money`, command registry, `/av` and `/autovendor`, login |
| `Bags.lua` | Reading only: which slots hold junk. No frames, no selling |
| `Keep.lua` | The keep list, reading an item from a link or a number, and its three commands |
| `Vendor.lua` | The visit: the selling steps, the check, stopping on close, the repair, the line |

Plus `README.md`, `icon.tga` (drawn by `tools/draw-icons.mjs`) and a row in
the root README's table.

Every client call tries the namespaced API first and the old global second
(`C_Container.GetContainerItemInfo` / `GetContainerItemInfo`,
`C_Container.UseContainerItem` / `UseContainerItem`, `C_Item.GetItemInfo` /
`GetItemInfo`), as the repo's other addons do, and every read that could
raise goes through `ns.Guarded`.

```
Bags.Junk(keep)  -- { { bag, slot, itemID, count, price }, ... } in bag order;
                 -- `keep` is the set of kept item IDs
Keep.Has(itemID) -- true when kept
ns.Money(copper) -- "1g 23s 4c", in coin icons where the client has them
```

## Checked in game

Carl prefers trying the built addon to a `/run` probe first (as with
RankUp), and a mistake here costs little: everything sold is in the Buyback
tab. After the build, at a merchant on Forever:

1. Greys sell from addon code (`C_Container.UseContainerItem` at an open
   merchant), and nothing on the keep list does.
2. No "That object is busy" with the 0.2-second pause; if there is, the
   pause goes up.
3. Repair goes through, and "not enough gold" shows when it should.
4. For the record: whether the merchant window has its own "Sell All Junk"
   button.
5. Gold before and after a visit matches the line.
6. Going from one merchant straight to another still sells at the second.

The answers go into this section.

## Testing

Lua specs with the repo's runner and a stubbed client (bags, items, a
merchant, money, timers):

- **Bags:** a valuable grey is listed; white, worthless, kept and locked
  items are not; the `C_Container` and global routes both work.
- **Keep:** keep and unkeep by link and by number; already kept and not kept
  say so; list, empty and not; bad input gets the help; the list survives a
  reload (it lives in `AutoVendorDB`).
- **Vendor:** opening sells one item per pause; a slot that did not empty is
  not counted; closing stops the selling, reports what sold and does not
  repair; a second open during a visit is ignored; repair comes after
  selling; no repair at a merchant that cannot, or with nothing to repair;
  not enough gold names the cost; the line's wording; silence when nothing
  happened.

## Out of scope

Selling white or better items, selling by rules (soulbound, unusable),
guild-bank repairs, a settings panel, a merchant-window button, a
"skip this visit" key.
