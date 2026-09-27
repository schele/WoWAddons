# ClickHeal: buff timers that keep counting in combat

Date: 2026-09-27. Status: design approved in chat; this write-up awaits review.

## The problem

Under each spell icon ClickHeal shows how long that buff has left on the
row's person. On WoW Forever (client `_classic_beta_` 1.60.1, build 70009)
every number disappears as soon as the player is in combat, and comes back
when the fight ends.

What the client said, from `/ch auras` in combat:

```
HELPFUL #1: the client raised on the read: GetAuraDataByIndex(): Auras
  cannot be accessed when secret while tainted by 'ClickHeal'
instance IDs: raised: GetUnitAuraInstanceIDs(): Auras cannot be accessed
  when secret while tainted by 'ClickHeal'
```

In combat, auras are secret ("SecretWhenUnitAuraRestricted": combat,
encounter, challenge mode or PvP match restrictions), and addon code may not
read them by any call: not by index, not by instance ID. ClickHeal's reads
are already guarded, so the refusal leaves the labels blank rather than
raising. No change to how ClickHeal reads auras can fix this.

## What works: Blizzard's aura container

The client ships `Blizzard_AuraContainer`. Its templates can be created by
addon code; its logic runs in the game's protected environment, which may
read secret auras. A throwaway `/ch probe` (2026-09-27) showed it working:

- `CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")`,
  `container:SetUnit("player")` and
  `container:AddAuraSlot(key, "HELPFUL", { candidateFilters = { includeSpellIDs = { [782] = true } } })`
  all succeed from ClickHeal.
- The slot's frame takes a label through `slot:SetDurationText(fontString)`,
  and the game writes the countdown into it. "Probe, Thorns: 8 m" kept
  counting in a fight while ClickHeal's own row went blank.
- The label must be the slot frame or a descendant of it ("must be the owner
  or a direct or indirect descendant of owner"). The probe made it on the
  slot frame inside `options.initializeFrame`, the callback the game runs on
  the frame before applying its access restrictions.
- Matching by spell ID is permitted "for helpful buffs on assistable units",
  which is every unit ClickHeal draws a row for.

## The design

### Where it lives

A new file, `AuraSlots.lua`, loaded after `Spells.lua` and before `Row.lua`.
It owns one container per row, parented to the row and pointed at the row's
unit, so it shows, hides and fades with the row. `Row.lua` calls it:

- `AuraSlots.Attach(row)` from `Row.Create`: makes the container and the
  slots for every button. Returns false on a client without the container,
  and the row keeps today's timers.
- `AuraSlots.SetSpell(row, index, spell)` from `Row.ApplySpells`, wherever a
  button's `spell` attribute is set or cleared: points that button's slots at
  the spell's IDs, or at none.

`Row.RefreshAuras` does nothing for a row whose timers the container draws.
Its current path (`Spells.HelpfulAuras`, `Row.FormatDuration`, `SetText`)
stays for clients without the container, such as Classic Era 1.15.

A new file changes `ClickHeal.toc`, so installing this needs a game restart
once, not a `/reload`.

### Two slots per button

Each button gets two slots on its row's container, both with filter
`"HELPFUL"` and `includeSpellIDs` for the button's spell:

| Slot | Extra filter | Number | Drawn |
|---|---|---|---|
| `own<index>` | `isFromPlayerOrPlayerPet = true` | white, on a dark plate | on top |
| `other<index>` | `isFromPlayerOrPlayerPet = false` | grey (`OTHERS_DIM`, as today) | under |

The game shows and hides each slot's frame as a matching buff comes and
goes. When both are on the target, as with two druids' Rejuvenations, the
own slot's plate covers the grey number, so only yours shows. The plate is a
dark texture on the own slot's frame, behind its number: about 26 by 13
pixels, black at about 85% opacity, to be tuned in game. It also makes the
white number easier to read over bright ground.

A button with no spell has both slots disabled (`SetAuraSlotEnabled`).

### Placement

Each slot's frame is 40 by 14 pixels (the timer box from the 1 by 1 fix),
anchored where the timer label is today: its top 3 pixels below the button's
bottom, centred. The own slot's frame is given a higher frame level than the
other's. The label is made on the slot frame in `initializeFrame`: 40 by 14,
centred, `GameFontHighlightSmall`, its colour set there. The anchors are set
once, out of combat, when the row is built; they follow the button through
icon-size changes.

### The number's style

A formatter ClickHeal configures and passes as `textFormatter` to
`SetDurationText`, to match today's `Row.FormatDuration`: "7s", "8m", "2h".

```lua
local formatter = C_StringUtil.CreateSecondsFormatter()
formatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
formatter:SetStripIntervalWhitespace(Enum.SecondsFormatterIntervalWhitespace.StripIgnoreLocale)
formatter:SetDesiredUnitCount(1)
formatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
formatter:SetRounding(Enum.SecondsFormatterRounding.RoundUp)
formatter:SetCanRoundUpLastUnit(true)
```

If the client lacks any of these setters, the game's default formatter is
used ("8 m"), rather than no number.

### Spell IDs

A slot matches spell IDs, not names, and ranks have different IDs.

- **From the spellbook:** `C_Spell.GetSpellInfo(spell).spellID`. The buttons
  cast by name, which casts the highest rank known, so this covers the
  player's own casts.
- **Learned:** out of combat, `Spells.HelpfulAuras` can still read each
  aura's `spellId`. It records every ID it sees under the aura's name. When a
  name a button holds gains an ID, that button's two slots get
  `SetAuraSlotCandidateFilters` with the wider set. This covers other
  people's ranks, and the player's own lower ranks. Learned IDs last the
  session; they are not saved.

Filters change only out of combat. A spell assigned in combat already waits
for combat to end (`Row.ApplySpells` is held back), and a learned ID found
in combat waits too.

### What goes, what stays

- `/ch probe` is removed.
- `/ch auras` stays, and prints one line per unit saying whether its timers
  are drawn by the container or by ClickHeal.

## Risks to check in game first

1. **Your own row turning grey.** The client has not credited buffs on the
   player's own unit to the player when addons ask (`sourceUnit` is nil
   there). If the protected side's `isFromPlayerOrPlayerPet` is also false
   on "player", every number on your own row lands in the grey slot. If so,
   the own row uses one slot, any caster, white.
2. **Colour.** `SetDurationText` gives the label secret aspects (text, alpha,
   vertex colour). If the game resets the colour, the grey needs
   `options.textColor` with a flat colour curve instead.
3. **Frame level.** If the game resets the slot frames' levels, the plate may
   fall under the grey number.
4. **Changing filters.** If `SetAuraSlotCandidateFilters` is refused, learned
   IDs mean rebuilding the button's slots instead.

## Testing

The test stub gains the container, modelled on what the probe found:
`CreateFrame("AuraContainer", ...)` with `SetUnit`, `AddAuraSlot` (calling
`initializeFrame` on the new slot frame, recording filter and candidate
filters), `SetAuraSlotCandidateFilters`, `SetAuraSlotEnabled`, and a slot
frame whose `SetDurationText` raises, as the client does, for a label that
is not the frame or its descendant. Tests, written first:

- A row builds one container on its unit, and two slots per button with the
  right filters.
- Each label is on its slot's frame, 40 by 14, under the button; own is
  white on a plate and drawn above; other is grey.
- `SetSpell` points both slots at the spell's IDs; no spell disables them.
- A learned ID widens the filters out of combat, and waits in combat.
- Without the container, the row keeps today's timers, unchanged.
- The formatter is configured as above, and a missing setter leaves the
  default.
- `/ch auras` says which way each unit's timers are drawn.

Then in game, in and out of combat: your own buff on yourself and on a party
member; another player's buff, if one is to hand; a spell changed on a slot;
the icon size changed.
