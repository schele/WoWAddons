# AutoVendor (World of Warcraft AddOn)

Open a merchant and your junk is sold and your gear repaired, without a
click. One chat line says what happened:

```
AutoVendor Sold 7 items for 1g 23s 4c. Repaired for 45s.
```

At the auction house, the asking price for a new auction lands one copper
under the cheapest listing instead of tying with it.

## What it sells

Grey (Poor quality) items in your bags that a merchant will pay for, and
the items you have put on your junk list. Never a white item, trade good or
anything better that is not on the junk list, never an item with no sell
price (which spares most quest items), and never anything on your keep list.

Items go one at a time, a fifth of a second apart, because the server
refuses sales that come faster. Close the merchant partway and it stops, and
says what had sold.

## Repairs

After selling, so the junk's gold helps pay. If this merchant can repair and
something needs it, everything is repaired from your own gold. If you cannot
afford it, nothing is repaired and the line says what it would cost.

## Undercutting at the auction house

When you put an item up for auction, the game fills the price in with the
cheapest listing already up. AutoVendor nudges that copy one copper down, so
your auction sorts ahead of the one it was copied from. The same happens
when you click a listing in the sell list: you go one copper under that one.

A price you type yourself is never touched, and a listing already asking a
single copper is matched rather than undercut to nothing.

## Turning any of it off

All of it happens unless you say otherwise. Like the keep list, the switches
are shared by all your characters.

| Command | Does |
|---|---|
| `/av sell` | Turn selling grey items and your junk list off, or on again |
| `/av repair` | Turn repairing off, or on again |
| `/av undercut` | Turn undercutting at the auction house off, or on again |

With repairs off, the line only says what sold.

## The keep list

Items AutoVendor never sells, shared by all your characters.

| Command | Does |
|---|---|
| `/av keep` then Shift-click an item | Never sell it |
| `/av unkeep` then Shift-click an item | Sell it again |
| `/av list` | Show the keep list and the junk list |

An item number works in place of a Shift-clicked link: `/av keep 7073`.
`/autovendor` is the same as `/av`.

## The junk list

Items AutoVendor always sells, along with the greys, whatever their
quality: the low-level white items you have outgrown, say. Shared by all
your characters, like the keep list. An item is on one list at most, so
putting a kept item on the junk list takes it off the keep list, and the
other way round.

| Command | Does |
|---|---|
| `/av junk` then Shift-click an item | Always sell it |
| `/av unjunk` then Shift-click an item | Stop selling it |

An item number works here too: `/av junk 2589`.

## The settings page

`/av settings`, or Options, AddOns, AutoVendor. It has the three switches as
checkboxes, the keep list with a button beside each item to sell it again,
and the junk list with a button beside each item to stop selling it.

Under the lists, **In your bags** shows the items in your bags that could go
on the junk list, once each, as their icons: not greys (those are sold
anyway), not items no merchant pays for, and nothing already on a list.
Hover one for its tooltip; click it to always sell it. The icons follow your
bags while the page is open.

## Worth knowing

The merchant's Buyback tab holds your last 12 sales. With more than 12 items
to sell, the earliest cannot be bought back, so put anything you might want
on the keep list before you visit.

To pause AutoVendor altogether, disable it in the AddOns list, or turn both
switches off.

## Install

1. Copy this folder into your client's `Interface/AddOns` as `AutoVendor`,
   so the result is `.../Interface/AddOns/AutoVendor/AutoVendor.toc`.
2. Restart the client and enable AutoVendor from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 AutoVendor -Install

See the [repo README](../README.md) for packaging and test commands.
