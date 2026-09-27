# BankBags: design

Date: 2026-09-26. Status: approved (Carl's standing "take the recommended option").

## What it is

A WoW Forever addon (client `_classic_beta_` 1.60, interface 16001) that shows
the character's bank, its main slots and its bank bags, in a window, anywhere
in the world. It adds a minimap button and an icon in the AddOns list.

## How: a saved copy

The server sends bank contents only while a banker is open, so no addon can
read the bank from afar. BankBags keeps a copy instead:
- It saves the bank when `BANKFRAME_OPENED` fires.
- It saves again while the bank is open, when `PLAYERBANKSLOTS_CHANGED`,
  `PLAYERBANKBAGSLOTS_CHANGED`, or `BAG_UPDATE` for a bank bag fires. The
  window shows the copy.

Saved variables (`BankBagsDB`) are per account, so the copy is kept per
character, `"<realm>-<name>"`, and the window can show any of them:

```lua
BankBagsDB = {
    characters = {
        ["Stormwind-Carl"] = {
            name = "Carl", realm = "Stormwind", class = "DRUID",
            saved = 1790000000,              -- time() of the last save
            containers = {
                { id = -1, name = "Bank", size = 24,
                  slots = { [3] = { link = "|cff...|Hitem:2589::|h[Linen Cloth]|h|r", count = 20, icon = 132889, quality = 1 } } },
                { id = 5, name = "Mooncloth Bag", icon = 133652, link = "...", size = 16, slots = { ... } },
            },
        },
    },
    minimap = { angle = 200, hide = false },
    window = { point = "CENTER", x = 0, y = 0 },
}
```

## Reading the bank

- **Containers:** the main bank is container `BANK_CONTAINER` (-1). The bank
  bags are containers `NUM_BAG_SLOTS + 1` to
  `NUM_BAG_SLOTS + NUM_BANKBAGSLOTS`, using the client's globals, or 4 and 6
  when they are missing.
- **Slots:** each container's size comes from `C_Container.GetContainerNumSlots`,
  and each slot from `C_Container.GetContainerItemInfo`: a table with
  `iconFileID`, `stackCount`, `quality` and `hyperlink`. Clients with the old
  globals (`GetContainerNumSlots`, `GetContainerItemInfo`) use those instead.
- **A bank bag itself:** its inventory slot is
  `C_Container.ContainerIDToInventoryID(id)`. That slot gives the bag's link
  and icon (`GetInventoryItemLink`, `GetInventoryItemTexture`), and its name
  comes from the link.
- **Unbought slots:** a bag slot that isn't bought, or holds no bag, has size 0
  and is left out.
- **Safety:** every call is feature-checked. The save happens only while the
  bank is open (`BANKFRAME_OPENED` until `BANKFRAME_CLOSED`), so a
  `BAG_UPDATE` away from the bank never overwrites the copy with empties.

## The window

- **Header:** a title bar reading "BankBags", a character picker defaulting to
  the one you play (it cycles through the saved characters, each named in its
  class colour), a search box and a close button.
- **Sections:** "Bank" first, then each bank bag under its icon and name,
  with slots 12 to a row. The list scrolls with the mouse wheel when it is
  longer than the window.
- **Slots:**
  - A slot shows its item's icon, its stack count above 1, and an edge in its
    quality colour for uncommon and better. An empty slot shows the empty-slot
    picture.
  - Hovering shows the item's tooltip (`GameTooltip:SetHyperlink`).
  - A modified click is passed to `HandleModifiedItemClick`: shift-click links
    the item in chat, ctrl-click previews it.
- **Search:** items whose names don't contain the search text (ignoring case,
  plain text) are dimmed. An empty search dims nothing.
- **Footer:** "Saved 2 hours ago" (in minutes, hours or days), or, for a
  character never saved, "Visit a banker to save your bank".
- **Other:** Escape closes the window, and it can be dragged, remembering
  where it was left.

## Minimap button and commands

- **Minimap button:** a round button on the minimap's rim, built as
  BossLoot's is. Click to open or close, drag to move round the rim.
  `/bb minimap` hides or shows it.
- **Commands:**
  - `/bankbags` or `/bb` opens or closes the window.
  - `/bb forget <name>` removes a saved character.
  - `/bb help` lists the commands.

## Icons

Drawn with `tools/draw-icons.mjs`, in the house style:
- `BankBags/icon.tga`: the AddOns-list icon, a teal money sack on the dark
  glowing tile with the ring. The TOC names it in `## IconTexture:`.
- `BankBags/minimap.tga`: the sack alone on a transparent background, filling
  the frame, for the minimap button, which supplies its own dark disc and gold
  ring.

## Testing

Lua specs with the repo's WoW stub, run as the other addons' are:
- a bank is saved with its slots, bags and time, and only while the bank is
  open;
- the old container globals work too;
- unbought bag slots are left out;
- each character is kept apart, and the picker cycles through them;
- the window draws items, counts, quality edges and empty slots;
- search dims non-matching items;
- the footer shows the time since the save, or the hint;
- tooltips and modified clicks work;
- the minimap button's angle maths;
- `/bb forget`.

## Out of scope

- The character's own bags (the game's bags already open anywhere).
- Reagent banks and guild banks (WoW Forever's Classic client has neither).
- Money.
- Sorting, and moving items.
