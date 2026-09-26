# BankBags (World of Warcraft AddOn)

Your bank, and every character's, from anywhere in the world.

The game only sends a bank's contents while you stand at a banker, so
BankBags saves a copy each time you open your bank, and again after every
change while it is open. Open the window with `/bb` or the minimap button to
see it anywhere: the main bank first, then each bank bag under its name. Hover
an item for its tooltip; shift-click links it in chat. The search box dims
everything that doesn't match. The button under the title steps through each
character whose bank is saved (right-click to go back); the footer says when
the copy was made.

## Commands

- `/bb` or `/bankbags` - open or close the window
- `/bb forget <name>` - forget a character's saved bank
- `/bb minimap` - hide or show the minimap button
- `/bb help` - list the commands

## Install

    .\package.ps1 BankBags -Install

See the [repo README](../README.md) for packaging and test commands.
