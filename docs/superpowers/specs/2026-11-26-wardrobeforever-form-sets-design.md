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

## Addendum: weapons with the shift, from the stance bar (2026-11-26)

**Why.** Carl's real aim was the weapon changing mid-fight when he shifts.
Forever blocks addon code from equipping in combat, but a click on a secure
button may run `/equipslot` (Carl's test: a macro with `/cast Cat Form` and
`/equipslot 16 Defender of Dalaran`, clicked in Bear Form in a fight,
worked). Carl shifts by clicking the stance bar.

**What the player gets.** Once any chosen set holds a weapon (main hand, off
hand, ranged/idol), WardrobeForever lays an invisible button of its own
over each stance bar button. A click shifts, exactly as the stance button
did, and in the same click swaps the weapons: the form's set weapons going
in, the normal weapons going out. Mid-fight included. Everything else is
as before (armour after the fight; all of it out of combat).

**How (Carl approved "build it").**
- `Stance.lua`: a `SecureActionButtonTemplate` button per stance button,
  parented to `StanceBar.actionButtons[i]` and covering it, `type` "macro".
  Its `macrotext`: `/cast <form name>`, then per weapon slot any chosen set
  fills with an item: `/equipslot [form:i] <slot> <normal>` and
  `/equipslot [noform:i] <slot> <this form's set item, or normal>` (one
  unconditional line when the two are the same). Item names, as Carl
  tested.
- The normal weapon is the one Forms remembered, or else the "home"
  weapon: what is worn in 16-18 in normal form once everything is back.
- Text changes only out of combat (secure attributes are locked in a
  fight); it follows sets, choices and the normal weapons.
- Hidden in Edit Mode and Quick Keybind mode, so the bar can still be
  moved and bound. Own hover glow and tooltip (`GameTooltip:SetShapeshift`).
- Forms: a weapon the click already swapped is not taken for normal gear
  (home is used), and the form's own set item is not taken for a change by
  hand.

**After review (2026-11-26).** Druids only (a warrior's stance cannot be
clicked off). A set with an item in either hand brings both hands into the
macros, so leaving a two-handed form puts the normal main and off hand
back; the off hand beside a set's own main hand gets no line going in. A
click tells Forms exactly what it puts on (`Forms.ExpectClick`), so a
refused shift's weapon is neither a change by hand nor a home weapon.
`UPDATE_SHAPESHIFT_FORMS` and `SPELLS_CHANGED` refresh the macros.

**Limits, told to the player.** A key bound to the stance bar
(SHAPESHIFTBUTTONn) presses Blizzard's button, not WardrobeForever's. A
shift the game refuses (no mana, cooldown) still swaps the weapon.
