# WardrobeForever: a gear set for each form

Date: 2026-11-26. Status: short design, awaiting approval in chat.

## Why

A druid wants different gear in Cat Form than out of it (and possibly in
Bear, Travel and the rest). Today that means opening the character sheet
and swapping by hand after every shift. Carl asked for WardrobeForever to do
it: name a set for a form, and shifting puts it on.

## What the player gets

- **Sets come from Blizzard's equipment manager**, the second tab behind the
  arrow on the character sheet (New Set / Equip / Save). WardrobeForever
  does not get a set editor of its own.
- **WardrobeForever's options page gets a Forms section.** One row per form
  or stance this character has, each with a dropdown: "Leave gear alone"
  (the default) or one of the character's sets. Rows hang a 16px gap under
  the description. Choices are saved per character.
- **Shifting into a form puts its set on.** Slots the set ignores are left
  alone.
- **Shifting back out puts back what you had on before** (Carl's pick,
  2026-11-26). Your gear in any form is your normal gear with that form's
  set on top, so going Cat to Travel (no set) also brings your normal gear
  back, and Cat to Bear swaps straight to Bear's set.
- **In combat, it all waits for the fight to end** (as Carl first asked:
  "queue them up"), for whichever form you are in by then. Shift five times
  in a fight and only the last one counts. *Changed 2026-11-26:* the design
  had weapons change at once (`INVSLOTS_EQUIPABLE_IN_COMBAT`), but Forever
  blocks addons from equipping anything in combat ("Interface action failed
  because of an AddOn"); only the player's own click can.
- **Your own changes win.** A slot you change by hand while shifted is not
  put back when you leave the form.
- **It survives /reload and logging out.** The "before" record is saved per
  character, so reloading in Cat Form still brings your normal gear back
  when you leave it.
- The hover pop-out is unchanged.

## How it works (approach A)

WardrobeForever moves items itself, one slot at a time, with Blizzard's
helper (`EquipmentManager_EquipItemByLocation`, which also puts an item in
the bags). The set's items come from `C_EquipmentSet.GetItemLocations`.

On every form change (`UPDATE_SHAPESHIFT_FORM`) and when combat ends
(`PLAYER_REGEN_ENABLED`), it works out the wanted gear: the remembered
normal gear, with the current form's set over it. It then swaps every slot
that differs, skipping non-weapon slots while in combat. The normal gear is
recorded at the moment you leave normal form (exact items, not just ones
with the same name), and forgotten once it has all been put back.

Approaches considered:

- **A. Own slot-by-slot swapping both ways** (picked). One code path for
  going in and coming back, and full control over what happens in combat.
- **B. Blizzard's `UseEquipmentSet` going in, own swapping coming back.**
  Two swap paths to keep in step, and what `UseEquipmentSet` does in combat
  on Forever is unknown; it may refuse the whole set.
- **C. Save the "before" gear as a hidden Blizzard set.** An extra set shows
  in the player's list and is re-saved on every shift, with the same combat
  unknown.

## Check in the game first

Per CLAUDE.md, before building on them:

1. Forever lets you change gear while shapeshifted, out of combat. If it
   does not, this design does not work and comes back for a rethink.
2. Weapons and the idol can be changed while shapeshifted in combat.
3. `C_EquipmentSet.GetItemLocations` returns the set's items for a set
   saved on the Equipment Manager tab.

## Not doing

- Putting gear on before the shift. That needs a secure macro and is a
  different feature.
- A "Wear in Cat Form" entry in each set's cog menu. Possible later.
- Chat messages about queued items. The gear just changes when the fight
  ends.

## Left to the builder

- How a form is keyed. A choice for Bear Form must survive Dire Bear Form
  replacing it at level 40, and forms learned later must not shift
  everyone's choices.
- Retrying a slot that could not move (item locked, bags full): on the next
  form change or combat end is enough.
- Two of the same ring or trinket, and a set that holds an empty slot.
- Version bump (0.2.0), README and options page text, tests against the
  stub.
