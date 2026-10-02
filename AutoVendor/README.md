# AutoVendor (World of Warcraft AddOn)

Open a merchant and your junk is sold and your gear repaired, without a
click. One chat line says what happened:

```
AutoVendor Sold 7 items for 1g 23s 4c. Repaired for 45s.
```

## What it sells

Grey (Poor quality) items in your bags that a merchant will pay for. Never
white items, trade goods or anything better, never an item with no sell
price (which spares most quest items), and never anything on your keep list.

Items go one at a time, a fifth of a second apart, because the server
refuses sales that come faster. Close the merchant partway and it stops, and
says what had sold.

## Repairs

After selling, so the junk's gold helps pay. If this merchant can repair and
something needs it, everything is repaired from your own gold. If you cannot
afford it, nothing is repaired and the line says what it would cost.

## Turning either off

Both happen unless you say otherwise. Like the keep list, the switches are
shared by all your characters.

| Command | Does |
|---|---|
| `/av sell` | Turn selling grey items off, or on again |
| `/av repair` | Turn repairing off, or on again |

With repairs off, the line only says what sold.

## The keep list

Items AutoVendor never sells, shared by all your characters.

| Command | Does |
|---|---|
| `/av keep` then Shift-click an item | Never sell it |
| `/av unkeep` then Shift-click an item | Sell it again |
| `/av list` | Show the list |

An item number works in place of a Shift-clicked link: `/av keep 7073`.
`/autovendor` is the same as `/av`.

## The settings page

`/av settings`, or Options, AddOns, AutoVendor. It has the two switches as
checkboxes, and the keep list with a button beside each item to sell it again.

## Worth knowing

The merchant's Buyback tab holds your last 12 sales. With more than 12 greys,
the earliest cannot be bought back, so put anything you might want on the
keep list before you visit.

To pause AutoVendor altogether, disable it in the AddOns list, or turn both
switches off.

## Install

1. Copy this folder into your client's `Interface/AddOns` as `AutoVendor`,
   so the result is `.../Interface/AddOns/AutoVendor/AutoVendor.toc`.
2. Restart the client and enable AutoVendor from the AddOns list.

The repo's `package.ps1` does step 1 for you, from the root:

    .\package.ps1 AutoVendor -Install

See the [repo README](../README.md) for packaging and test commands.
