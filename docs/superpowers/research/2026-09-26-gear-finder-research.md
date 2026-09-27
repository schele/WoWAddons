# Vanilla 1.12 gear data for the addon: stat weights, BiS lists, levelling, enchants, PvP

## 0. Read this before hardcoding anything
- **WoW Forever may not use 1.12 items.** Icy Veins' WoW Forever class guides (updated Sep 2026) say "WoW Forever has completely reworked dungeon loot and item stats, meaning Classic equipment lists can not be used to determine best-in-slot gear" (https://www.icy-veins.com/wow-forever/fury-warrior-melee-dps-pve-guide).
  - Forever also rewrote talents: 392 of 467 are new or changed (https://www.indiekings.com/2026/09/wow-forever-class-changes-new-talents.html).
  - It adds new dungeons and raids, for example Hall of Thanes, Ruins of Lordaeron, Barrow Deeps and Hyjal Summit (https://wowtbc.gg/warcraftforever/news/what-we-know/).
  - Everything below is vanilla 1.12 data, as you asked. Check in-game that the item IDs and stats match 1.12 before relying on the BiS lists.
  - The stat weights (1.12 combat formulas) should carry over better than the item lists, but new talents can shift them.
  - Every BiS row carries its drop source, so the per-instance availability switch can filter it.
- **Item IDs are all checked.** Every ID below was checked against Wowhead's tooltip API (`https://nether.wowhead.com/classic/tooltip/item/<id>`, which returns JSON with the name). There were 0 name mismatches across about 850 checks. I re-checked the 108 main melee picks myself.
- **Nothing was written to the repo.** The subagents' parsed pages and scripts are under the session scratchpad: `...\scratchpad\melee\`, `casters\`, `bis\` (druid), `palsham\` (`picks.tsv` and `phases_v.tsv` hold role/slot/name/ID) and `enchants\`.
- **Access notes:**
  - Wowhead guide bodies are rendered by JavaScript, so WebFetch sees only the page shell and curl gets a CloudFront 403. They were read through Wayback raw copies (`https://web.archive.org/web/2026id_/<url>`) or `r.jina.ai`.
  - Icy Veins returns 403 to WebFetch but works with curl and a browser User-Agent.
  - Fandom wikis return 402, but their MediaWiki API works (`api.php?action=parse&prop=wikitext`).
  - Reddit is blocked.

---

## 1. Stat weights

### 1a. Sources

**[P] Pawn's built-in Classic Era scales**
- They ship inside the Pawn addon: https://github.com/VgerMods/Pawn/blob/main/ClassicHawsJon.lua. They are HawsJon's TBC 2.4.3 scales (derived from Elitist Jerks and MaxDPS; https://tbcwowaddons.weebly.com/pawn.html).
- On Era, Pawn multiplies the rating weights into per-percent weights:
  - melee hit ×9.379, crit ×8.5, spell hit and spell crit ×8
  - dodge and parry ×9.44, block ×6.9, defense ×1.5 per skill point
- Pawn's own comment says they were "originally designed for Burning Crusade". So compared with vanilla they undervalue hit and crit and overvalue Int for healers.
- There are no levelling or PvP scales.
- The per-role numbers in 1d are already converted per 1%.

**[S] WoWSims Season of Discovery default EP weights** (`ui/<spec>/sim.ts` in https://github.com/wowsims/sod)
- These use vanilla formulas, but SoD runes distort them. I used them only as a cross-check.

**[V] Vanilla and Classic numbers that are actually published:**
- **Hunter** (Icy Veins): 1 Agi ≈ 2.5 AP unbuffed and 3 AP buffed; 1% crit ≈ 32 AP; 1% hit ≈ 32 AP. https://www.icy-veins.com/wow-classic/hunter-dps-pve-stat-priority
- **Cat** (Wowhead, NerdEgghead, with Kings and Heart of the Wild), in AP: Str 2.64, Agi 2.76, 1% hit 31.85, 1% crit 30.13, 1% haste 13.6. https://www.wowhead.com/classic/guide/classes/druid/feral/dps-stat-priority-attributes-pve
- **Bear** (Wowhead, Season of Mastery weights), in AP: Str 2.2, Agi 1.57, 1% hit 36.1, 1% crit 25.8, Sta 2.2, gear armor 0.33, bonus armor 0.069, Defense 0.46, Dodge 0, Health 0.167. https://www.wowhead.com/classic/guide/classes/druid/feral/tank-stat-priority-attributes-pve
  - The Warcraft Tavern Season of Mastery version is similar: Agi 1.6, hit 34.8, crit 26.7, armor 0.29, def 0.35. https://www.warcrafttavern.com/wow-classic/guides/feral-tank-stat-priorities-wow-classic-season-of-mastery/
- **Fire mage team sim** (Classic Era rules): 1% crit = 12.8 SP, 1% hit = 15.0 SP. https://github.com/ronkuby-mage/fire-mage-simulation (README image)
  - The Wowhead mage Naxx page implies 1% crit ≈ 12 SP.
- **Warlock** (Wowhead): 1% hit ≈ 10 SP at low gear, up to 15 SP at endgame, and "the same" for crit. https://www.wowhead.com/classic/guide/classes/warlock/dps-stat-priority-attributes-pve
- **Shaman** (Wowhead): Elemental 1% spell hit or crit ≈ "20+" spell damage; Resto 1% crit ≈ 20+ healing; 1 Int beats 1 MP5 on fights under 75 s. https://www.wowhead.com/classic/guide/classes/shaman/elemental/dps-stat-priority-attributes-pve
  - My own calculation for Lightning Bolt with Elemental Fury gives about 8–10 SP per 1% instead.
- **Rogue AEP** (vanilla WoWWiki, Ming/Unsouled): 1 Agi = 1 Sta = 2 Str = 0.1% crit = 0.13% hit = 2 AP = 4 resist = 5 HP5 = 50 armor. This is PvP-flavoured.
  - https://vanilla-wow-archive.fandom.com/wiki/Agility_Equivalence_Points
  - https://forum.nostalrius.org/viewtopic.php?f=37&t=12264
- **Warrior tank** (same wiki page, "Mortem"): 1 Agi = 2 Str = 0.33 Sta = 0.25% crit = 0.07% dodge/parry = 4 AP = 10 armor = 0.25 weapon DPS = 4 block value = 1 weapon skill.
- **Holy priest** (Nostalrius, "res"): Heal 1, Spi 0.71, Int 0.3, MP5 3, 1% crit 10. Int rises a lot on short fights. https://forum.nostalrius.org/viewtopic.php?f=39&t=5806&start=60
- **Shadow priest** (Nostalrius): 1% crit ≈ 2.3 SP; 1% hit ≈ 13–17 SP. https://forum.nostalrius.org/viewtopic.php?f=39&t=38147
- **Elemental** (Nostalrius): 1% crit ≈ 5.2 SP at 0 gear, rising with SP. https://forum.nostalrius.org/viewtopic.php?f=42&t=28640
- **Conversions at level 60** (https://www.wowhead.com/classic/guide/classic-wow-stats-and-attributes-overview):
  - Str: 2 AP for Druid, Paladin, Shaman and Warrior; 1 AP for the others.
  - Agility to crit: 20 Agi per 1% for Druid, Paladin, Shaman and Warrior; 29 for Rogue; 53 for Hunter.
  - Agility to AP: 2 RAP for Hunters; 1 melee AP for Rogues, Hunters and Cat form.
  - Int to spell crit: Mage 59.5, Priest 59.2, Druid 60, Warlock 60.6, Paladin 54 per 1%. Shaman is given as 59.5 on the overview and 59.2 on Wowhead's shaman pages.
  - 14 AP = 1 weapon DPS.
  - Hit caps vs bosses: 9% melee (6% with 305 weapon skill) and 16% spell. Vs level-60 targets: 5% melee and 3% spell.
  - Defense 440 = crit-immune against level 63.

**Priority-only sources** (used to keep the order right):
- Warcraft Tavern Classic: Ret, Holy Paladin, Prot Warrior, Feral DPS and Tank.
- Icy Veins Classic: Priest healer (Healing > MP5 > Spi > Int > Crit), Holy Paladin (Healing > Int > Crit > MP5 > Sta > Spi), Feral tank, Warrior tank.

### 1b. Conventions
- Weights are per 1 stat point.
- HIT, CRIT, SHIT (spell hit), SCRIT (spell crit), DODGE, PARRY and BLOCK are per 1%.
- DEF is per defense skill point. SKILL is per weapon-skill point for your weapon type, up to 305 (the value is small from 305 to 308 and 0 after).
- \*DPS is per 1.0 DPS on the item. ARMOR is per point of base item armor.
- Hit is worth its value only up to the cap. After the cap it is worth about 0, or about 25% of its value for dual-wield white hits.
- **Spell damage has three kinds in 1.12:**
  - SPD = generic "+damage and healing".
  - HEAL = "+healing only".
  - School = "+Fire/Frost/Shadow/Nature/Arcane damage".
  - For healers, SPD counts as HEAL. For DPS casters, HEAL is worth 0 and off-school damage is worth the school weight shown.
- Resists are situational; none of the defaults below include them except RES for tanks.
- Format of each role line: the role, then the recommended values, then **ranges** (low–high across sources) with the sources in brackets.

### 1c. Recommended weights (main stat = 1.0)

**WARRIOR_DPS** (Str = 1)
- Recommended: STR 1, AGI 0.6, STA 0.1, ARMOR 0.005, AP 0.5, HIT 12, CRIT 11, SKILL 15, MHDPS 5, OHDPS 2 (2H DPS 5.3)
- Ranges:
  - AGI 0.55–0.74 [P 0.57 Fury / 0.69 Arms; S 0.74; warriors get no AP from Agi, so Agi = crit/20]
  - AP 0.40–0.54
  - HIT 5.3–14 [P 5.3 Fury / 9.4 Arms; S 11.4]
  - CRIT 6–12.5 [P 5.95–7.2; S 10.0]
  - SKILL 8–23 [S 22.9]
  - MHDPS 4.75–5.3 [P, S]

**WARRIOR_PROT** (Sta = 1)
- Recommended: STA 1, ARMOR 0.03, DEF 1.0 (up to 440, then 0.4), DODGE 5, PARRY 5, BLOCK 3, BV 0.15, AGI 0.5, STR 0.3, AP 0.1, HIT 4, CRIT 1.5, SKILL 0.5, MHDPS 1.5, RES 0.3
- Ranges: ARMOR 0.02–0.074; DEF 0.4–1.4; DODGE 1.1–6.6; PARRY 1.1–5.5; BLOCK 1.3–4.1; BV 0.08–0.59; AGI 0.33–1.19; STR 0.17–0.67; HIT 0.6–6.3; MHDPS 1.3–3.1 [P, Mortem, S]

**PALADIN_HOLY** (Heal = 1)
- Recommended: HEAL 1, SPD 1, INT 0.6, MP5 2.0, SCRIT 10, SPI 0.05, STA 0.1
- Ranges:
  - INT 0.3–1.85 [P 1.85 is TBC-biased]
  - MP5 1.24–2.3
  - SCRIT 6.8–12 (Illumination makes crit a mana stat)
  - SPI 0–0.52 (Icy Veins and Warcraft Tavern: Spirit is useless for Holy Paladins)

**PALADIN_PROT** (Sta = 1; Pawn-based, no vanilla numeric source)
- Recommended: STA 1, ARMOR 0.02, DEF 1.0, DODGE 5, PARRY 4.5, BLOCK 3.5, BV 0.2, AGI 0.5, STR 0.2, INT 0.4, MP5 1.0, SPD 0.45, HOLY 0.45, SHIT 5, SCRIT 3, HIT 2, CRIT 1.3, AP 0.05, MHDPS 1.5, RES 0.5
- Note: holy spell damage is threat (Holy Shield, Consecration, Seal of Righteousness).

**PALADIN_RET** (Str = 1)
- Recommended: STR 1, AGI 0.55, AP 0.45, CRIT 10, HIT 10, 2H DPS 5, SPD 0.3, HOLY 0.3, INT 0.2, MP5 0.8, STA 0.1
- Ranges: AGI 0.45–0.64; AP 0.40–0.5; CRIT 5.6–12; HIT 7.9–12 (Precision gives 3%, so 6% from gear); 2H DPS 2.9–5.4; SPD 0.13–0.33; INT 0.06–0.34

**HUNTER** (Agi = 1)
- Recommended: AGI 1, RAP 0.4, AP 0.4 (generic AP also applies to ranged), HIT 12, CRIT 11, INT 0.35, MP5 1.0, RDPS 5, MHDPS 0.5, STR 0.05, STA 0.1, SPI 0.05
- Ranges:
  - RAP 0.33–0.55 [V, P]
  - CRIT 5.1–12.8 [P 5.1–6.8; V 10.7–12.8]
  - HIT 9.4–12.8
  - INT 0.1–0.9 [P 0.8–0.9]
  - MP5 1–2.4 [P]
  - RDPS 2.4–5.1 [P 2.4–2.6; the 14-RAP-per-DPS rule gives about 5]

**ROGUE** (Agi = 1)
- Recommended: AGI 1, STR 0.5, AP 0.5, HIT 10, CRIT 10, SKILL 10, MHDPS 5, OHDPS 2.5, STA 0.1, ARMOR 0.005, DODGE 0.5
- Ranges: STR and AP 0.45–0.61; CRIT 6.9–11 [P 6.9; V 10]; HIT 7.7–9.4 [V 7.7; P 9.4; S 8.7]; SKILL (S 23.7, no vanilla source); MHDPS 3–7 [P 3; 14 AP/DPS gives about 7]

**PRIEST_HOLY** (Heal = 1)
- Recommended: HEAL 1, SPD 1, MP5 2.5, SPI 0.75, INT 0.5, SCRIT 6, STA 0.1
- Discipline: SPI 0.6, INT 0.6, SCRIT 5
- Ranges: MP5 1.65–3 [P, V]; SPI 0.67–0.9; INT 0.3–1.4 (higher on short fights); SCRIT 2.4–10

**PRIEST_SHADOW** (Shadow = 1)
- Recommended: SPD 1, SHADOW 1, SHIT 12, SCRIT 2.5, INT 0.15, SPI 0.15, MP5 1.0, STA 0.1
- Ranges: SHIT 9–17 [P 9.0; V 13–17]; SCRIT 2.3–6 (SW:P and Mind Flay can't crit in vanilla; P's 6.1 is TBC-biased)
- Cap: 16%; Shadow Focus gives 10%, so 6% from gear.

**SHAMAN_ELE** (Nature = 1)
- Recommended: SPD 1, NATURE 1, FIRE 0.3, FROST 0.1, SHIT 11, SCRIT 10, INT 0.3, MP5 1.2, SPI 0.05, STA 0.1
- Ranges: SHIT 7.2–20+ [P 7.2; my calculation 10; Wowhead "20+"]; SCRIT 5.2–20+ [V 5.2; P 8.4; Wowhead 20+]

**SHAMAN_ENH** (Str = 1)
- Recommended: STR 1, AGI 0.55, AP 0.5, CRIT 10, HIT 9, 2H DPS 6, SPD 0.2, NATURE 0.2, INT 0.2, MP5 0.5, STA 0.1, SKILL 10 (Orc with axes)
- Ranges: AGI 0.55–0.87 [P 0.87; S 0.71]; CRIT 8.3–9.5; HIT 6.3–8.5; 2H DPS 3–7

**SHAMAN_RESTO** (Heal = 1)
- Recommended: HEAL 1, SPD 1, MP5 2.0, INT 0.6, SCRIT 7, SPI 0.2, STA 0.1
- Ranges: MP5 1.48–3; INT 0.3–1.11; SCRIT 4.3–20 [P 4.3; Wowhead 20+]; SPI 0.05–0.68

**MAGE_FIRE** (Fire = 1)
- Recommended: SPD 1, FIRE 1, FROST 0.3, ARCANE 0.15, SHIT 14, SCRIT 11, INT 0.35, MP5 0.9, SPI 0.05, STA 0.1
- Frost variant: FROST 1, FIRE 0.05, ARCANE 0.13, SHIT 13, SCRIT 7, INT 0.35, MP5 0.8
- Ranges: SHIT 7.4–15 [P 7.4 / 9.8; V 12.6–15]; SCRIT 4.6–12.8 [P 4.6–6.2; V 12–12.8]; INT 0.37–0.49
- Cap: Elemental Precision gives 6%, so 10% from gear.

**WARLOCK** (Shadow = 1; SM/Ruin)
- Recommended: SPD 1, SHADOW 1, FIRE 0.2, SHIT 12, SCRIT 10, INT 0.3, SPI 0.1, MP5 0.7, STA 0.15
- Ranges: SHIT 9.6–15 [P 9.6–12.8; WH 10–15]; SCRIT 3.1–15 [P 3.1–7.0; my calculation 9; WH 10–15]
- Cap: 16%, all from gear.

**DRUID_BALANCE** (SPD = 1)
- Recommended: SPD 1, ARCANE 0.65, NATURE 0.35, SHIT 10, SCRIT 7, INT 0.35, SPI 0.2, MP5 0.8, STA 0.1
- Ranges: SHIT 9.7–11.75 [P, S]; SCRIT 5–8.3 [P 5; S 7.5; my calculation 8.3]; INT 0.16–0.38

**DRUID_CAT** (Agi = 1)
- Recommended: AGI 1, STR 1.0, AP 0.38, FAP 0.38, HIT 11.5, CRIT 11, INT 0.05, STA 0.05; weapon DPS 0 (it doesn't matter in form)
- Ranges: STR 0.91–1.48 [WH 0.96; S 0.91; P 1.48]; AP 0.30–0.59; HIT 5.7–11.5; CRIT 5.0–10.9

**DRUID_BEAR** (Sta = 1)
- Recommended: STA 1, ARMOR 0.13 (base item armor; "+X armor" enchants and kits 0.03), AGI 0.75, STR 0.8, AP 0.4, FAP 0.4, DEF 0.25, DODGE 1.0, HIT 10, CRIT 8, RES 0.5, INT 0.05
- Ranges: ARMOR 0.10–0.15; AGI 0.48–0.73; STR 0.2–1.0; DEF 0.16–0.39; DODGE 0–3.6; HIT 1.5–16.4; CRIT 1.3–11.7 [P mitigation-heavy; WH/NerdEgghead threat-balanced]
- Gear armor is ×4.6 in Dire Bear Form.

**DRUID_RESTO** (Heal = 1)
- Recommended: HEAL 1, SPD 1, MP5 2.0, SPI 0.5, INT 0.6, SCRIT 3, STA 0.1
- Ranges: MP5 1.4–3; SPI 0.3–0.72 (Reflection); INT 0.4–0.83; SCRIT 2.3–6 (Nature's Grace builds sit at the high end)

### 1d. Raw Pawn Classic Era values
Main stat = 1 as Pawn defines it. Hit and crit are per 1%. Stamina is 0.1 for non-tanks; Armor is 0.005 unless shown.

**Warrior**
- Arms: Str 1, Agi 0.69, AP 0.45, Hit 9.38, Crit 7.23, MeleeDps 5.31
- Fury: Agi 0.57, AP 0.54, Hit 5.35, Crit 5.95, Dps 5.22
- Prot (Sta = 1): Str 0.33, Agi 0.59, AP 0.06, Armor 0.02, Def 1.215, Dodge 6.61, Parry 5.48, Block 4.07, BV 0.35, Hit 6.28, Crit 2.38, Dps 3.13, AllRes 1

**Paladin**
- Holy (Int = 1): Heal 0.54, Spi 0.28, MP5 1.24, SCrit 3.68
- Prot (Sta = 1): Str 0.2, Agi 0.6, Int 0.5, Armor 0.02, Def 1.05, Dodge 6.61, Parry 5.66, Block 4.14, BV 0.15, SpellDmg and Holy 0.44, SHit 6.24, SCrit 4.8, MP5 1, Dps 1.77
- Ret (Str = 1): Agi 0.64, AP 0.41, Int 0.34, Hit 7.88, Crit 5.61, Dps 5.4, SpellDmg 0.33, MP5 1

**Hunter** (Agi = 1)
- BM: Int 0.8, AP and RAP 0.43, Hit 9.38, Crit 6.8, RangedDps 2.4, MeleeDps 0.75, MP5 2.4
- MM: Int 0.9, AP 0.55, Crit 5.1, RangedDps 2.6
- SV: AP 0.55, Crit 5.53

**Rogue** (all specs, Agi = 1): Str 0.5, AP 0.45, Hit 9.38, Crit 6.89, MainHandDps 3 (off-hand 2)

**Priest** (Int = 1)
- Holy: Heal 0.81, Spi 0.73, MP5 1.35, SCrit 1.92
- Disc: Heal 0.72, Spi 0.48, MP5 1.19, SCrit 2.56
- Shadow (SpellDmg = 1): Int 0.19, Spi 0.21, SHit 8.96, SCrit 6.08, MP5 1

**Shaman**
- Elemental (Nature = 1): Int 0.31, Spi 0.09, MP5 1.14, SHit 7.2, SCrit 8.4
- Enhancement (Str = 1): Agi 0.87, AP 0.5, Int 0.34, Hit 6.28, Crit 8.33, Dps 3, Nature 0.3
- Resto (Int = 1): Heal 0.9, Spi 0.61, MP5 1.33, SCrit 3.84

**Mage** (SpellDmg = 1)
- Fire: Fire 0.94, Frost 0.32, Arcane 0.17, Int 0.44, MP5 0.9, SHit 7.44, SCrit 6.16
- Frost: Frost 0.95, Int 0.37, SHit 9.76, SCrit 4.64
- Arcane: Arcane 0.88, Int 0.46, Spi 0.59, SHit 6.96, SCrit 4.8

**Warlock** (SpellDmg = 1)
- Affliction: Shadow 0.91, Fire 0.35, Int 0.4, SHit 9.6, SCrit 3.12
- Demonology: Shadow and Fire 0.8, Spi 0.5, SCrit 5.28
- Destruction: Shadow 0.95, Fire 0.23, Int 0.34, Spi 0.25, SHit 12.8, SCrit 6.96, MP5 0.65

**Druid**
- Balance (SpellDmg = 1): Arcane 0.64, Nature 0.43, Int 0.38, Spi 0.34, MP5 0.58, SHit 9.68, SCrit 4.96
- Cat (Agi = 1): Str 1.48, AP and FeralAP 0.59, Hit 5.72, Crit 5.02, Armor 0.02
- Bear (Sta = 1): Str 0.2, Agi 0.48, AP 0.34, Armor 0.1, Def 0.39, Dodge 3.59, Hit 1.5, Crit 1.28, AllRes 1
- Resto (Int = 1): Heal 1.21, Spi 0.87, MP5 1.7, SCrit 2.8

### 1e. Levelling (below 60)
No source publishes full levelling weight tables:
- Pawn Classic has none (https://tbcwowaddons.weebly.com/pawn.html).
- WoWSims SoD has EP presets per level bracket (25/40/50/60), but they are rune-specific.

Published guidance you can turn into multipliers:
- **Weapon damage dominates for melee and hunters.**
  - Icy Veins levelling guides: "Your weapon, as a Warrior, is by far the most impactful piece of your gear while leveling." https://www.icy-veins.com/wow-classic/classic-warrior-leveling-guide
  - Icy Veins' Forever Fury levelling order: Weapon Damage > Hit > Crit > Str > Agi > Sta.
  - Suggestion: weapon DPS ×1.5.
- **Stamina counts for more solo:** extra pulls, and Life Tap for warlocks. Warcraft Tavern warlock levelling: Stamina matters (Life Tap); spell power becomes top priority after about level 38. https://www.warcrafttavern.com/wow-classic/guides/warlock-leveling-guide/
  - Suggestion: STA 0.3–0.5 for DPS and healers while levelling.
- **Spirit counts for more for mana classes** because downtime regen is used heavily (Wowhead stats overview: Spirit only regenerates outside the 5-second rule).
  - Suggestion: Priest, Mage, Druid and Shaman SPI about 0.5–1.0 × INT. Warlock Spirit stays low.
- **Hit caps are lower against level-equal mobs:** 5% melee, 3% spell (Wowhead stats overview). Value hit about half after 3–5%.
- **Spell damage is weak at low level.** Spells learned below level 20 lose 3.75% of their coefficient per level under 20 (https://www.warcrafttavern.com/wow-classic/guides/ozgars-downranking-guide-tool/).
- **Agi and Int crit conversions are level-60 values and scale with level.** The vanilla AEP wiki notes 1 Agi ≈ 1.5 AP for a level-19 rogue, against 2 AP at 60.

### 1f. PvP adjustments (item 5b)
No source publishes full PvP weight tables for vanilla. Adjustments supported by sources:
- **Stamina:** raise to 0.5–1.0 × main stat.
  - The vanilla rogue AEP values Sta = Agi.
  - Icy Veins PvP BiS pages list "Stamina, Intellect and Critical Strike" first for Mage and "Stamina, Intellect and Healing Power / Spell Crit" for Priest. https://www.icy-veins.com/wow-classic/mage-pvp-bis-gear-trinkets-and-switch-items and https://www.icy-veins.com/wow-classic/priest-healer-pvp-bis-gear-trinkets-and-switch-items
- **Hit caps:** "You only need 3% Spell Hit to be capped in PvP" (Icy Veins mage PvP). Melee cap is 5% against level-60 players.
- **Crit:** raise for burst specs (mage, priest).
- **Healers:** raise Int. WoWWiki Stat comparison: "For PvP, Int is probably the most important stat" (short fights). https://wowwiki-archive.fandom.com/wiki/Stat_comparison
- **Resists and armor:** the rogue AEP gives 4 resist = 1 Agi (RES ≈ 0.25) and 50 armor = 1 Agi (ARMOR ≈ 0.02).
- **Lower MP5 and Spirit** for DPS casters (short fights).
- **Warrior PvP:** "any high Stamina and Strength / Attack Power / Critical Strike / Armor pieces" (Icy Veins warrior PvP BiS).

---

## 2. Best-in-slot lists (level 60)

**How to read these tables**
- "ID" is the Wowhead Classic item ID. Rings and trinkets have two rows.
- (A)/(H) means an Alliance/Horde pair.
- T0.5 = Tier 0.5 quests and summons (patch 1.10). DM = Dire Maul. Most pre-raid lists rely heavily on DM, T0.5, ZG and PvP reputation.
- **Main sources:**
  - Pre-raid: Wowhead Classic pre-raid pages. Several are titled "Season of Mastery", but every item exists in 1.12.
  - Naxx: Wowhead Naxxramas pages.
  - MC, BWL and AQ: Icy Veins or the Wowhead planners, as noted per role.
  - Where Wowhead embeds a gear-planner set, the "one pick per slot" is the author's own choice, decoded from that set.

**Source errors the agents found (use these IDs):**
- Mark of the Champion: 23206 is the melee version, 23207 the caster version.
- Signet Ring of the Bronze Dragonflight: 21200 tank, 21205 Agi/hit, 21210 spell.
- Level-60 WSG bracers: Dryad's Wrist Bindings 19595 and Forest Stalker's Bracers 19587. Icy Veins links the level-40 versions, 19597 and 19590.
- Royal Seal of Eldre'Thalas has one ID per class: Rogue 18465, Warlock 18467, Mage 18468, Priest 18469, Druid 18470, Shaman 18471, Paladin 18472, Hunter 18473.
- Atiesh has one ID per class: Mage 22589, Warlock 22630, Priest 22631, Druid 22632.
- Icy Veins calls 22403 "Diana's Pearl Necklace". Its real name is Nacreous Shell Necklace.
- Icy Veins lists Force of Will as 18544. The correct ID is 11810.
- Tarnished Elven Ring 18500, Cauterizing Band, Ring of Spell Power and Mindtap Talisman are not Unique, so two can be worn.
- Hand of Justice 11815: Wowhead says it drops from Emperor Thaurissan; older data says General Angerforge. Check your loot table.

### 2.1 Warrior Arms/Fury
Pre-raid (https://www.wowhead.com/classic/guide/fury-warrior-dps-pre-raid-best-in-slot-bis-gear-wow-classic; also https://www.icy-veins.com/wow-classic/warrior-dps-pre-raid-gear):

| Slot | Item | ID | Source | Alt |
|---|---|---|---|---|
| Head | Lionheart Helm | 12640 | Blacksmithing | Mask of the Unforgiven 13404 |
| Neck | Mark of Fordring | 15411 | Quest "In Dreams" | Pendant of Celerity 22340 |
| Shoulder | Truestrike Shoulders | 12927 | UBRS Emberseer | Black Dragonscale Shoulders 15051 |
| Back | Cape of the Black Baron | 13340 | Strat, Rivendare | Blackveil Cape 11626 |
| Chest | Savage Gladiator Chain | 11726 | BRD Gorosh | Cadaverous Armor 14637 |
| Wrist | Battleborn Armbraces | 12936 | UBRS Rend | Vambraces of the Sadist 13400 |
| Hands | Devilsaur Gauntlets | 15063 | Leatherworking | Edgemaster's Handguards 14551 |
| Waist | Brigam Girdle | 13142 | UBRS Drakkisath | Omokk's Girth Restrainer 13959 |
| Legs | Devilsaur Leggings | 15062 | Leatherworking | Black Dragonscale Leggings 15052 |
| Feet | Boots of Heroism | 21995 | T0.5 quest | Bloodmail Boots 14616 |
| Ring | Painweaver Band | 13098 | UBRS | Don Julio's Band 19325 (AV) |
| Ring | Blackstone Ring | 17713 | Maraudon | Tarnished Elven Ring 18500 |
| Trinket | Diamond Flask | 20130 | Warrior quest (Sunken Temple) | Hand of Justice 11815 |
| Trinket | Blackhand's Breadth | 13965 | UBRS quest | Rune of the Guard Captain 19120 (H) |
| MH | Dal'Rend's Sacred Charge | 12940 | UBRS Rend | Ironfoe 11684; Orc: Rivenspike 13286 |
| OH | Dal'Rend's Tribal Guardian | 12939 | UBRS Rend | Mirah's Song 15806; Felstriker 12590 |
| 2H (Arms) | Treant's Bane | 18538 | DM North tribute | Arcanite Reaper 12784 |
| Ranged | Satyr's Bow | 18323 | DM East | Blackcrow 12651 |

Naxx (https://www.wowhead.com/classic/guide/wow-classic-fury-warrior-dps-naxxramas-best-in-slot-gear):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Lionheart Helm | 12640 | Blacksmithing |
| Neck | Stormrage's Talisman of Seething | 23053 | Kel'Thuzad |
| Shoulder | Conqueror's Spaulders | 21330 | AQ40 token |
| Back | Shroud of Dominion | 23045 | Sapphiron |
| Chest | Plated Abomination Ribcage | 23000 | Thaddius |
| Wrist | Wristguards of Vengeance | 22936 | Anub'Rekhan |
| Hands | Gauntlets of Annihilation | 21581 | C'Thun (Edgemaster's 14551 for non-Human/Orc) |
| Waist | Girdle of the Mentor | 23219 | Razuvious |
| Legs | Legplates of Carnage | 23068 | Heigan |
| Feet | Chromatic Boots | 19387 | BWL Chromaggus |
| Ring | Band of Unnatural Forces | 23038 | Loatheb |
| Ring | Quick Strike Ring | 18821 | MC |
| Trinket | Kiss of the Spider | 22954 | Maexxna |
| Trinket | Mark of the Champion | 23206 | Kel'Thuzad quest |
| MH | Gressil, Dawn of Ruin | 23054 | Kel'Thuzad (Orc: Hatchet of Sundered Bone 22816) |
| OH | The Hungering Cold | 23577 | Kel'Thuzad |
| 2H | Might of Menethil | 22798 | Kel'Thuzad |
| Ranged | Nerubian Slavemaker | 22812 | Kel'Thuzad |

Earlier phases (Icy Veins, https://www.icy-veins.com/wow-classic/warrior-dps-pve-gear-best-in-slot):

| Slot | MC/Onyxia | BWL | AQ40 |
|---|---|---|---|
| Head | Lionheart Helm 12640 | same | same |
| Neck | Onyxia Tooth Pendant 18404 | same | Barbed Choker 21664 |
| Shoulder | Truestrike Shoulders 12927 | Drake Talon Pauldrons 19394 | Conqueror's Spaulders 21330 |
| Back | Cape of the Black Baron 13340 | Cloak of Draconic Might 19436 | Cloak of the Fallen God 21710 |
| Chest | Savage Gladiator Chain 11726 | same | Breastplate of Annihilation 21814 |
| Wrist | Wristguards of Stability 19146 | Berserker Bracers 19578 | Qiraji Execution Bracers 21602 |
| Hands | Flameguard Gauntlets 19143 | same | Gauntlets of Annihilation 21581 |
| Waist | Onslaught Girdle 19137 | same | same |
| Legs | Cloudkeeper Legplates 14554 | Legguards of the Fallen Crusader 19402 | Conqueror's Legguards 21332 |
| Feet | Bloodmail Boots 14616 | Chromatic Boots 19387 | same |
| Rings | Quick Strike Ring 18821 + Band of Accuria 17063 | Master Dragonslayer's Ring 19384 + Quick Strike Ring 18821 | Ring of the Qiraji Fury 21677 + Quick Strike Ring 18821 |
| Trinkets | Diamond Flask 20130 + Hand of Justice 11815 | Drake Fang Talisman 19406 + Diamond Flask 20130 | same |
| MH / OH | Deathbringer 17068 / Vis'kag the Bloodletter 17075 | Empyrean Demolisher 17112 or Maladath 19351 / Crul'shorukh 19363 | Blessed Qiraji War Axe 21242 / Crul'shorukh 19363 |
| 2H | Bonereaver's Edge 17076 | same, or Obsidian Edged Blade 18822 | Dark Edge of Insanity 21134 |
| Ranged | Striker's Mark 17069 | same | Larvae of the Great Worm 23557 |

Race decides the weapon: Human swords/maces, Orc axes, everyone else Edgemaster's.

### 2.2 Warrior Protection
Pre-raid ("Best Overall" = balanced; https://www.wowhead.com/classic/guide/warrior-tank-pre-raid-best-in-slot-bis-gear-wow-classic):

| Slot | Item | ID | Source | Alt (without T0.5, or mitigation) |
|---|---|---|---|---|
| Head | Helm of Heroism | 21999 | T0.5 | Lionheart Helm 12640; Gyth's Skull 12952 |
| Neck | Beads of Ogre Might | 22150 | DM quest | Medallion of Grand Marshal Morris 13091 |
| Shoulder | Spaulders of Heroism | 22001 | T0.5 | Stockade Pauldrons 14552 |
| Back | Stoneskin Gargoyle Cape | 13397 | Strat rare | Shifting Cloak 18511 |
| Chest | Breastplate of Heroism | 21997 | T0.5 | Savage Gladiator Chain 11726; Deathbone Chestplate 14624 |
| Wrist | Bracers of Heroism | 21996 | T0.5 | Battleborn Armbraces 12936; Vigorsteel Vambraces 13951 |
| Hands | Gauntlets of Heroism | 21998 | T0.5 | Edgemaster's 14551; Stonegrip Gauntlets 13072 |
| Waist | Brigam Girdle | 13142 | UBRS | Mugger's Belt 18505 |
| Legs | Cloudkeeper Legplates | 14554 | BoE world drop | Legplates of Heroism 22000; Warmaster Legguards 12935 |
| Feet | Boots of Heroism | 21995 | T0.5 | Bloodmail Boots 14616 |
| Ring | Don Julio's Band | 19325 | AV Exalted | Blackstone Ring 17713 |
| Ring | Myrmidon's Signet | 2246 | BoE world drop | Naglering 11669 |
| Trinket | Diamond Flask | 20130 | Warrior quest | Hand of Justice 11815 |
| Trinket | Blackhand's Breadth | 13965 | UBRS quest | Mark of the Chosen 17774; Force of Will 11810 |
| MH | Ironfoe | 11684 | BRD Emperor | Mirah's Song 15806; Orc: Frostbite 19103 |
| Shield | The Immovable Object | 19321 | AV Exalted | Draconian Deflector 12602; Force Reactive Disk 18168 |
| Ranged | Satyr's Bow | 18323 | DM East | Gorewood Bow 16996 |

Naxx (https://www.wowhead.com/classic/guide/wow-classic-warrior-tank-naxxramas-best-in-slot-gear):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Conqueror's Crown | 21329 | AQ40 (mitigation: Dreadnaught Helmet 22418) |
| Neck | Sadist's Collar | 23023 | Gothik |
| Shoulder | Conqueror's Spaulders | 21330 | AQ40 |
| Back | Cloak of the Fallen God | 21710 | C'Thun quest |
| Chest | Conqueror's Breastplate | 21331 | AQ40 |
| Wrist | Dreadnaught Bracers | 22423 | Naxx token |
| Hands | Gauntlets of Annihilation | 21581 | C'Thun |
| Waist | Girdle of the Mentor | 23219 | Razuvious |
| Legs | Conqueror's Legguards | 21332 | AQ40 |
| Feet | Dreadnaught Sabatons | 22420 | Naxx token |
| Ring | Master Dragonslayer's Ring | 19384 | Nefarian quest |
| Ring | Circle of Applied Force | 19432 | Flamegor |
| Trinket | Kiss of the Spider | 22954 | Maexxna |
| Trinket | Mark of the Champion | 23206 | Kel'Thuzad quest (mitigation: Lifegiving Gem 19341) |
| MH | The Hungering Cold | 23577 | Kel'Thuzad (Thunderfury 19019) |
| Shield | The Face of Death | 23043 | Sapphiron |
| Ranged | Crossbow of Imminent Doom | 21459 | AQ20 |

Earlier phases (Icy Veins, https://www.icy-veins.com/wow-classic/warrior-tank-pve-gear-best-in-slot; T = threat, D = defensive):

| Slot | MC/Onyxia | BWL | AQ40 |
|---|---|---|---|
| Head | Lionheart Helm 12640 or Helm of Wrath 16963 | Lionheart Helm 12640 or Helm of Endless Rage 19372 | Conqueror's Crown 21329 |
| Neck | Onyxia Tooth Pendant 18404 or Medallion of Steadfast Might 17065 | Onyxia Tooth Pendant 18404 or Master Dragonslayer's Medallion 19383 | T: Onyxia Tooth Pendant 18404 / D: Mark of C'Thun 22732 |
| Shoulder | Pauldrons of Might 16868 | Drake Talon Pauldrons 19394 | Conqueror's Spaulders 21330 / Pauldrons of the Unrelenting 21639 |
| Back | Cloak of the Shrouded Mists 17102 | Cloak of Draconic Might 19436 | Cloak of the Fallen God 21710 / Cloak of the Golden Hive 21621 |
| Chest | Savage Gladiator Chain 11726 or Breastplate of Might 16865 | Breastplate of Wrath 16966 | Conqueror's Breastplate 21331 |
| Wrist | Wristguards of True Flight 18812 | Bracelets of Wrath 16959 | Hive Defiler Wristguards 21618 / Bracelets of Wrath 16959 |
| Hands | Edgemaster's 14551 or Aged Core Leather Gloves 18823 | same | Gauntlets of Steadfast Determination 21674 |
| Waist | Onslaught Girdle 19137 | same | same, or Royal Qiraji Belt 21598 |
| Legs | Legplates of Wrath 16962 | Legguards of the Fallen Crusader 19402 | Conqueror's Legguards 21332 / Legplates of Wrath 16962 |
| Feet | Sabatons of Might 16862 | Chromatic Boots 19387 | Chromatic Boots 19387 / Conqueror's Greaves 21333 |
| Rings | Band of Accuria 17063 + Quick Strike Ring 18821 | same | Signet Ring of the Bronze Dragonflight 21205 + Band of Accuria 17063 / D: Ring of Emperor Vek'lor 21601 |
| Trinkets | Mark of the Chosen 17774 + Diamond Flask 20130 | Drake Fang Talisman 19406 + Lifegiving Gem 19341 | Earthstrike 21180 + Diamond Flask 20130 / D: Lifegiving Gem 19341 |
| One-hand | Deathbringer 17068 or Vis'kag 17075 | Thunderfury 19019 or Crul'shorukh 19363 | Thunderfury 19019 or Death's Sting 21126 |
| Shield | Malistar's Defender 17106 or Drillborer Disk 17066 | Elementium Reinforced Bulwark 19349 | Blessed Qiraji Bulwark 21269 |
| Ranged | Striker's Mark 17069 | Dragonbreath Hand Cannon 19368 | Crossbow of Imminent Doom 21459 |

### 2.3 Rogue
Pre-raid (https://www.wowhead.com/classic/guide/rogue-dps-pre-raid-best-in-slot-bis-gear-wow-classic; the fallback without T0.5 comes from Icy Veins):

| Slot | Item | ID | Source | Alt (without T0.5) |
|---|---|---|---|---|
| Head | Darkmantle Cap | 22005 | T0.5 | Mask of the Unforgiven 13404 |
| Neck | Mark of Fordring | 15411 | Quest | Pendant of Celerity 22340 |
| Shoulder | Darkmantle Spaulders | 22008 | T0.5 | Truestrike Shoulders 12927 |
| Back | Cape of the Black Baron | 13340 | Strat | Shadow Prowler's Cloak 22269 |
| Chest | Darkmantle Tunic | 22009 | T0.5 | Cadaverous Armor 14637 |
| Wrist | Darkmantle Bracers | 22004 | T0.5 | Bracers of the Eclipse 18375 |
| Hands | Devilsaur Gauntlets | 15063 | Leatherworking | Darkmantle Gloves 22006 |
| Waist | Darkmantle Belt | 22002 | T0.5 | Cloudrunner Girdle 13252; Mugger's Belt 18505 (daggers) |
| Legs | Devilsaur Leggings | 15062 | Leatherworking | Shadowcraft Pants 16709 |
| Feet | Darkmantle Boots | 22003 | T0.5 | Swiftwalker Boots 12553 |
| Ring | Tarnished Elven Ring | 18500 | DM North tribute | Painweaver Band 13098 |
| Ring | Tarnished Elven Ring | 18500 | (a second copy) | Blackstone Ring 17713 |
| Trinket | Hand of Justice | 11815 | BRD | Royal Seal of Eldre'Thalas 18465 |
| Trinket | Blackhand's Breadth | 13965 | UBRS quest | Rune of the Guard Captain 19120 (H) |
| MH swords / daggers | Dal'Rend's Sacred Charge / Felstriker | 12940 / 12590 | UBRS Rend | Sword of Zeal 6622 / Heartseeker 12783 |
| OH swords / daggers | Dal'Rend's Tribal Guardian / Distracting Dagger | 12939 / 18392 | UBRS / DM West | Mirah's Song 15806 / Bonescraper 13368 |
| Ranged | Precisely Calibrated Boomstick | 2100 | BoE world drop | Satyr's Bow 18323 |

Naxx (https://www.wowhead.com/classic/guide/wow-classic-rogue-dps-naxxramas-best-in-slot-gear):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Bonescythe Helmet | 22478 | Naxx token |
| Neck | Prestor's Talisman of Connivery | 19377 | Nefarian |
| Shoulder | Bonescythe Pauldrons | 22479 | Naxx token |
| Back | Cloak of the Fallen God | 21710 | C'Thun quest (daggers: Cloak of Concentrated Hatred 21701) |
| Chest | Deathdealer's Vest | 21364 | AQ40 |
| Wrist | Bonescythe Bracers | 22483 | Naxx token |
| Hands | Bonescythe Gauntlets | 22481 | Naxx token |
| Waist | Bonescythe Waistguard | 22482 | Naxx token |
| Legs | Bonescythe Legplates | 22477 | Naxx token |
| Feet | Bonescythe Sabatons | 22480 | Naxx token |
| Ring | Bonescythe Ring | 23060 | Kel'Thuzad |
| Ring | Band of Unnatural Forces | 23038 | Loatheb |
| Trinket | Kiss of the Spider | 22954 | Maexxna |
| Trinket | Slayer's Crest | 23041 | Sapphiron |
| MH swords / daggers | Gressil 23054 / Kingsfall 22802 | | Kel'Thuzad |
| OH swords / daggers | Iblis 23014 (Human; others The Hungering Cold 23577) / Death's Sting 21126 | | Razuvious / C'Thun |
| Ranged | Nerubian Slavemaker | 22812 | Kel'Thuzad |

Earlier phases (Icy Veins, https://www.icy-veins.com/wow-classic/rogue-dps-pve-gear-best-in-slot):

| Slot | MC/Onyxia | BWL | AQ40 |
|---|---|---|---|
| Head | Bloodfang Hood 16908 | same | Deathdealer's Helm 21360 |
| Neck | Onyxia Tooth Pendant 18404 | Prestor's Talisman 19377 | same |
| Shoulder | Nightslayer Shoulder Pads 16823 | same | Deathdealer's Spaulders 21361 |
| Back | Cape of the Black Baron 13340 | same | Cloak of the Fallen God 21710 |
| Chest | Nightslayer Chestpiece 16820 | Bloodfang Chestpiece 16905 | Deathdealer's Vest 21364 |
| Wrist | Nightslayer Bracelets 16825 | Bloodfang Bracers 16911 | Qiraji Execution Bracers 21602 |
| Hands | Nightslayer Gloves 16826 | same | Gloves of Enforcement 21672 |
| Waist | Nightslayer Belt 16827 | Bloodfang Belt 16910 | Belt of Never-ending Agony 21586 |
| Legs | Bloodfang Pants 16909 | same | Deathdealer's Leggings 21362 |
| Feet | Nightslayer Boots 16824 | Boots of the Shadow Flame 19381 | Deathdealer's Boots 21359 |
| Rings | Band of Accuria 17063 + Quick Strike Ring 18821 | Band of Accuria 17063 + Master Dragonslayer's Ring 19384 | Band of Accuria 17063 + Signet Ring 21205 |
| Trinkets | Hand of Justice 11815 + Blackhand's Breadth 13965 | Hand of Justice 11815 + Drake Fang Talisman 19406 | Jom Gabbar 23570 + Drake Fang Talisman 19406 |
| Swords MH/OH | Vis'kag 17075 / Brutality Blade 18832 | Chromatically Tempered Sword 19352 / Brutality Blade 18832 | GM Longsword 12584 (A) or HW Blade 16345 (H) / Thunderfury 19019 |
| Daggers MH/OH | Perdition's Blade 18816 / Core Hound Tooth 18805 | same | Death's Sting 21126 / Blessed Qiraji Pugio 21244 |
| Ranged | Striker's Mark 17069 | same | Larvae of the Great Worm 23557 |

### 2.4 Hunter
Pre-raid (https://www.wowhead.com/classic/guide/hunter-dps-pre-raid-best-in-slot-bis-gear-wow-classic):

| Slot | Item | ID | Source | Alt |
|---|---|---|---|---|
| Head | Backwood Helm | 18421 | DM quest | Beastmaster's Cap 22013; Mask of the Unforgiven 13404 |
| Neck | Pendant of Celerity | 22340 | UBRS Valthalak (T0.5) | Mark of Fordring 15411 |
| Shoulder | Truestrike Shoulders | 12927 | UBRS | Wyrmhide Spaulders 12082 |
| Back | Cape of the Black Baron | 13340 | Strat | Dark Phantom Cape 13122 |
| Chest | Savage Gladiator Chain | 11726 | BRD | Cadaverous Armor 14637 |
| Wrist | Bracers of the Eclipse | 18375 | DM West | Slashclaw Bracers 13211 |
| Hands | Devilsaur Gauntlets | 15063 | Leatherworking | Trueaim Gauntlets 13255 |
| Waist | Marksman's Girdle | 22232 | LBRS Urok | Warpwood Binding 18393 |
| Legs | Devilsaur Leggings | 15062 | Leatherworking | Blademaster Leggings 12963 |
| Feet | Beastmaster's Boots | 22061 | T0.5 | Windreaver Greaves 13967 |
| Ring | Tarnished Elven Ring | 18500 | DM North | Blackstone Ring 17713 |
| Ring | Tarnished Elven Ring | 18500 | (a second copy) | Painweaver Band 13098 |
| Trinket | Blackhand's Breadth | 13965 | UBRS quest | Devilsaur Eye 19991 |
| Trinket | Royal Seal of Eldre'Thalas | 18473 | DM quest | Hand of Justice 11815 |
| 2H | Huntsman's Harpoon | 22314 | DM Isalien (T0.5) | Barbarous Blade 18520 |
| Ranged | Bloodseeker | 19107 | AV quest | Carapace Spine Crossbow 18738; Blackcrow 12651 |
| Quiver | Ribbly's Quiver | 2662 | BRD | — |

Naxx (https://www.wowhead.com/classic/guide/wow-classic-hunter-dps-naxxramas-best-in-slot-gear):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Cryptstalker Headpiece | 22438 | Naxx token |
| Neck | Prestor's Talisman of Connivery | 19377 | Nefarian |
| Shoulder | Cryptstalker Spaulders | 22439 | Naxx token |
| Back | Cloak of the Fallen God | 21710 | C'Thun quest |
| Chest | Cryptstalker Tunic | 22436 | Naxx token |
| Wrist | Cryptstalker Wristguards | 22443 | Naxx token |
| Hands | General's Chain Gloves (H) / Marshal's Chain Grips (A) | 16571 / 16463 | PvP R12 (non-PvP: Cryptstalker Handguards 22441) |
| Waist | Cryptstalker Girdle | 22442 | Naxx token |
| Legs | Leggings of Apocalypse | 23071 | Four Horsemen |
| Feet | Cryptstalker Boots | 22440 | Naxx token |
| Ring | Band of Unnatural Forces | 23038 | Loatheb |
| Ring | Band of Reanimation | 22961 | Patchwerk |
| Trinket | Mark of the Champion | 23206 | Kel'Thuzad quest |
| Trinket | Drake Fang Talisman | 19406 | BWL |
| 2H | The Eye of Nerub | 23039 | Loatheb |
| Ranged | Nerubian Slavemaker | 22812 | Kel'Thuzad |
| Quiver | Ancient Sinew Wrapped Lamina | 18714 | Rhok'delar quest |

Earlier phases (Icy Veins, https://www.icy-veins.com/wow-classic/hunter-dps-pve-gear-best-in-slot):
- **MC/Onyxia:** Giantstalker set (Helmet 16846, Epaulets 16848, Breastplate 16845, Bracers 16850, Gloves 16852, Belt 16851, Leggings 16847, Boots 16849). Onyxia Tooth Pendant 18404, Cloak of the Shrouded Mists 17102, Band of Accuria 17063 + Quick Strike Ring 18821, Royal Seal 18473 + Blackhand's Breadth 13965, Lok'delar 18715, Rhok'delar 18713.
- **BWL:** Dragonstalker set (Helm 16939, Spaulders 16937, Breastplate 16942, Bracers 16935, Gauntlets 16940, Belt 16936, Legguards 16938, Greaves 16941). Prestor's Talisman 19377, Band of Accuria 17063 + Don Julio's Band 19325, Drake Fang Talisman 19406 + Blackhand's Breadth 13965, Core Hound Tooth 18805 + Brutality Blade 18832, Ashjre'thul 19361.
- **AQ40:** same as BWL, plus Cloak of the Fallen God 21710, Badge of the Swarmguard 21670 + Jom Gabbar 23570, Silithid Claw 21673 + Fang of the Faceless 19859.

### 2.5 Paladin Holy
Pre-raid (https://www.wowhead.com/classic/guide/paladin-healing-pre-raid-best-in-slot-bis-gear-wow-classic):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Insightful Hood | 18490 | DM North |
| Neck | Animated Chain Necklace | 18723 | Strat Undead |
| Shoulder | Royal Cap Spaulders | 14548 | Scholomance |
| Back | Hide of the Wild | 18510 | Leatherworking |
| Chest | Robes of the Exalted | 13346 | Strat, Rivendare |
| Wrist | Gallant's Wristguards | 18459 | DM North |
| Hands | Harmonious Gauntlets | 18527 | DM North, Gordok |
| Waist | Sash of Mercy | 14553 | BoE world drop (Whipvine Cord 18327) |
| Legs | Padre's Trousers | 18386 | DM West |
| Feet | Boots of the Full Moon | 18507 | DM North |
| Ring | Fordring's Seal | 16058 | Quest "In Dreams" |
| Ring | Rosewine Circle | 13178 | LBRS |
| Trinket | Briarwood Reed | 12930 | UBRS |
| Trinket | Second Wind | 11819 | BRD |
| MH | The Hammer of Grace | 11923 | BRD Chest of The Seven |
| OH | Brightly Glowing Stone | 18523 | DM North |
| Libram | Libram of Divinity | 23201 | Scholomance |

Naxx (https://www.wowhead.com/classic/guide/wow-classic-paladin-healing-naxxramas-best-in-slot-gear):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Redemption Headpiece | 22428 | Naxx T3 |
| Neck | Amulet of the Fallen God | 21712 | C'Thun quest |
| Shoulder | Wild Growth Spaulders | 18810 | MC |
| Back | Cloak of Suturing | 22960 | Patchwerk |
| Chest | Redemption Tunic | 22425 | Naxx T3 |
| Wrist | Bracelets of Royal Redemption | 21604 | AQ40 |
| Hands | Peacekeeper Gauntlets | 20264 | ZG Hakkar |
| Waist | Corehound Belt | 19162 | Leatherworking |
| Legs | Empowered Leggings | 19385 | BWL |
| Feet | Boots of Pure Thought | 19437 | BWL trash |
| Ring | Pure Elementium Band | 19382 | Nefarian |
| Ring | Band of Unanswered Prayers | 22939 | Anub'Rekhan |
| Trinket | Eye of the Dead | 23047 | Sapphiron |
| Trinket | Rejuvenating Gem | 19395 | BWL |
| MH | Hammer of the Twisting Nether | 23056 | Kel'Thuzad |
| OH | Shield of Condemnation | 22819 | Kel'Thuzad |
| Libram | Libram of Light | 23006 | Noth |

Earlier phases (Wowhead planners):

| Slot | P1 (MC) | P3 (BWL) | P5 (AQ) |
|---|---|---|---|
| Head | Judgement Crown 16955 | Crystal Adorned Crown 19132 | same |
| Neck | Animated Chain Necklace 18723 | Choker of the Fire Lord 18814 | Amulet of the Fallen God 21712 |
| Shoulder | Wild Growth Spaulders 18810 | same | same |
| Back | Archivist Cape 13386 (random suffix) | Hide of the Wild 18510 | same |
| Chest | Robes of the Exalted 13346 | same | Robes of the Guardian Saint 21663 |
| Wrist | Loomguard Armbraces 13969 | same | Bracelets of Royal Redemption 21604 |
| Hands | Hands of the Exalted Herald 12554 | Harmonious Gauntlets 18527 | Peacekeeper Gauntlets 20264 |
| Waist | Corehound Belt 19162 | same | same |
| Legs | Salamander Scale Pants 18875 | Empowered Leggings 19385 | same |
| Feet | Verdant Footpads 13954 | Boots of Pure Thought 19437 | same |
| Rings | Cauterizing Band 19140 ×2 | Pure Elementium Band 19382 / Cauterizing Band 19140 | Pure Elementium Band 19382 / Ring of the Martyr 21620 |
| Trinkets | Shard of the Scale 17064 / Briarwood Reed 12930 | Rejuvenating Gem 19395 / Major Recombobulator 18637 | Scarab Brooch 21625 / Rejuvenating Gem 19395 |
| MH | Azuresong Mageblade 17103 | Grand Marshal's Warhammer 23454 | Scepter of the False Prophet 21839 |
| OH | Malistar's Defender 17106 | Lei of the Lifegiver 19312 | same |

### 2.6 Paladin Protection
Wowhead calls Paladin tanking niche. Its pre-raid page is thin, so this list also draws on Icy Veins and Wowhead's "Light's Bulwark" guide.
- https://www.wowhead.com/classic/guide/wow-classic-paladin-tank-pre-raid-best-in-slot-gear
- https://www.icy-veins.com/wow-classic/protection-paladin-tank-pre-raid-gear
- https://www.wowhead.com/classic/guide/lights-bulwark-protection-paladin-tanking

Pre-raid:

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Enchanted Thorium Helm | 12620 | Blacksmithing (alt Gyth's Skull 12952) |
| Neck | Medallion of Grand Marshal Morris | 13091 | BoE world drop |
| Shoulder | Stockade Pauldrons | 14552 | BoE world drop |
| Back | The Emperor's New Cape | 11930 | BRD |
| Chest | Deathbone Chestplate | 14624 | Scholomance |
| Wrist | Vigorsteel Vambraces | 13951 | Scholomance |
| Hands | Deathbone Gauntlets | 14622 | Scholomance |
| Waist | Deathbone Girdle | 14620 | Scholomance |
| Legs | Deathbone Legguards | 14623 | Scholomance |
| Feet | Deathbone Sabatons | 14621 | Scholomance |
| Ring | Naglering | 11669 | BRD |
| Ring | Ring of Protection | 15855 | Quest |
| Trinket | Force of Will | 11810 | BRD |
| Trinket | Smotts' Compass | 4130 | Quest (STV) |
| MH | Flurry Axe | 871 | BoE world drop (alt Mastersmith's Hammer 18048) |
| Shield | Draconian Deflector | 12602 | UBRS |
| Libram | Libram of Hope | 22401 | DM East |

Naxx (https://www.wowhead.com/classic/guide/wow-classic-paladin-tank-naxxramas-best-in-slot-gear):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Avenger's Crown | 21387 | AQ40 T2.5 |
| Neck | Gluth's Missing Collar | 22981 | Gluth |
| Shoulder | Avenger's Pauldrons | 21391 | AQ40 |
| Back | Cryptfiend Silk Cloak | 22938 | Anub'Rekhan |
| Chest | Avenger's Breastplate | 21389 | AQ40 |
| Wrist | Wristguards of True Flight | 18812 | MC |
| Hands | Gauntlets of Steadfast Determination | 21674 | AQ40 |
| Waist | Royal Qiraji Belt | 21598 | AQ40 |
| Legs | Avenger's Legguards | 21390 | AQ40 |
| Feet | Avenger's Greaves | 21388 | AQ40 |
| Ring | Angelista's Touch | 21695 | AQ40 |
| Ring | Signet Ring of the Bronze Dragonflight | 21205 | AQ rep (tank version 21200) |
| Trinket | Hand of Justice | 11815 | BRD |
| Trinket | Styleen's Impeding Scarab | 19431 | BWL |
| MH | Thunderfury | 19019 | MC quest |
| Shield | The Face of Death | 23043 | Sapphiron |
| Libram | Libram of Fervor | 23203 | BoE world drop |

Earlier phases (Wowhead planners):
- **P1:** Judgement Crown 16955, Medallion of Steadfast Might 17065, Stockade Pauldrons 14552, The Emperor's New Cape 11930, Deathbone Chestplate 14624, Lawbringer Bracers 16857, Deathbone Gauntlets 14622 and Girdle 14620, Judgement Legplates 16954, Core Forged Greaves 18806, Naglering 11669 / Ring of Protection 15855, Onyxia Blood Talisman 18406 / Force of Will 11810, Quel'Serrar 18348, Drillborer Disk 17066.
- **P3/4:** Judgement Spaulders 16953, Overlord's Embrace 19888, Field Marshal's Lamellar Chestplate 16473, Judgement Bindings 16951, Marshal's Lamellar Gloves 16471, Judgement Belt 16952, Bloodsoaked Legplates 19855, Heavy Dark Iron Ring 18879 / Overlord's Crimson Band 19873, Styleen's Impeding Scarab 19431, Elementium Reinforced Bulwark 19349, Libram of Fervor 23203.
- **P5:** Avenger set (see Naxx), Mark of C'Thun 22732, Cloak of the Golden Hive 21621, Earthstrike 21180 / Hand of Justice 11815, Blessed Qiraji Bulwark 21269.

### 2.7 Paladin Retribution
Pre-raid (https://www.wowhead.com/classic/guide/paladin-dps-pre-raid-best-in-slot-bis-gear-wow-classic). Paladins are Alliance-only, so the Alliance PvP reputation items apply:

| Slot | Item | ID | Source | Alt |
|---|---|---|---|---|
| Head | Lionheart Helm | 12640 | Blacksmithing | — |
| Neck | Beads of Ogre Might | 22150 | DM quest | — |
| Shoulder | Highlander's Plate Spaulders | 20057 | Arathi Basin Exalted | Truestrike Shoulders 12927 |
| Back | Cloak of the Honor Guard | 20073 | Arathi Basin Exalted | — |
| Chest | Savage Gladiator Chain | 11726 | BRD | — |
| Wrist | Berserker Bracers | 19578 | Warsong Gulch Exalted | — |
| Hands | Chromatic Gauntlets | 19157 | Leatherworking | — |
| Waist | Highlander's Plate Girdle | 20041 | Arathi Basin Honored | Brigam Girdle 13142 |
| Legs | Sentinel's Plate Legguards | 22672 | Warsong Gulch Exalted | — |
| Feet | Highlander's Plate Greaves | 20048 | Arathi Basin Revered | Bloodmail Boots 14616 |
| Ring | Blackstone Ring | 17713 | Maraudon | — |
| Ring | Don Julio's Band | 19325 | AV Exalted | — |
| Trinket | Blackhand's Breadth | 13965 | UBRS quest | — |
| Trinket | Hand of Justice | 11815 | BRD | — |
| 2H | The Unstoppable Force | 19323 | AV Exalted | Arcanite Reaper 12784; Nightfall 19169 |
| Libram | Libram of Hope | 22401 | DM East | — |

Naxx (https://www.wowhead.com/classic/guide/wow-classic-paladin-dps-naxxramas-best-in-slot-gear):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Avenger's Crown | 21387 | AQ40 T2.5 |
| Neck | Stormrage's Talisman of Seething | 23053 | Kel'Thuzad |
| Shoulder | Avenger's Pauldrons | 21391 | AQ40 |
| Back | Shroud of Dominion | 23045 | Sapphiron |
| Chest | Avenger's Breastplate | 21389 | AQ40 |
| Wrist | Wristguards of Vengeance | 22936 | Anub'Rekhan |
| Hands | Gauntlets of Annihilation | 21581 | C'Thun |
| Waist | Girdle of the Mentor | 23219 | Razuvious |
| Legs | Avenger's Legguards | 21390 | AQ40 |
| Feet | Avenger's Greaves | 21388 | AQ40 |
| Ring | Band of Unnatural Forces | 23038 | Loatheb |
| Ring | Quick Strike Ring | 18821 | MC |
| Trinket | Scrolls of Blinding Light | 19343 | BWL |
| Trinket | Kiss of the Spider | 22954 | Maexxna |
| 2H | Might of Menethil | 22798 | Kel'Thuzad (Corrupted Ashbringer 22691) |
| Libram | Libram of Fervor | 23203 | BoE world drop |

Earlier phases (Wowhead planners):

| Slot | P1 | P3/4 | P5 |
|---|---|---|---|
| Head | Lionheart Helm 12640 | Helm of Endless Rage 19372 | Avenger's Crown 21387 |
| Neck | Onyxia Tooth Pendant 18404 | Prestor's Talisman 19377 | Onyxia Tooth Pendant 18404 |
| Shoulder | Truestrike Shoulders 12927 | Drake Talon Pauldrons 19394 | Avenger's Pauldrons 21391 |
| Back | Stoneskin Gargoyle Cape 13397 | Cloak of Draconic Might 19436 | same |
| Chest | Savage Gladiator Chain 11726 | same | Avenger's Breastplate 21389 |
| Wrist | Wristguards of Stability 19146 | Forest Stalker's Bracers 19587 | Hive Defiler Wristguards 21618 |
| Hands | Flameguard Gauntlets 19143 | Marshal's Lamellar Gloves 16471 | Gauntlets of Annihilation 21581 |
| Waist | Onslaught Girdle 19137 | same | same |
| Legs | Cloudkeeper Legplates 14554 | Legguards of the Fallen Crusader 19402 | Avenger's Legguards 21390 |
| Feet | Bloodmail Boots 14616 | Chromatic Boots 19387 | Avenger's Greaves 21388 |
| Rings | Quick Strike Ring 18821 / Blackstone Ring 17713 | Quick Strike Ring 18821 / Circle of Applied Force 19432 | Ring of the Qiraji Fury 21677 / Signet 21205 |
| Trinkets | Hand of Justice 11815 / Blackhand's Breadth 13965 | Scrolls of Blinding Light 19343 / Hand of Justice 11815 | same |
| 2H | Sulfuras, Hand of Ragnaros 17182 | same | same |

### 2.8 Priest Holy/Discipline
Pre-raid (https://www.wowhead.com/classic/guide/priest-healing-pre-raid-best-in-slot-bis-gear-wow-classic):

| Slot | Item | ID | Source | Alt |
|---|---|---|---|---|
| Head | Cassandra's Grace | 13102 | BoE world drop | Crimson Felt Hat 18727 |
| Neck | Animated Chain Necklace | 18723 | Strat Undead | Amulet of the Redeemed 22327 |
| Shoulder | Mantle of Lost Hope | 22234 | BRD | Burial Shawl 18681 |
| Back | Hide of the Wild | 18510 | Leatherworking | Cloak of the Cosmos 18389 |
| Chest | Truefaith Vestments (Priest only) | 14154 | Tailoring | Robes of the Exalted 13346 |
| Wrist | Sublime Wristguards | 18497 | DM North | Virtuous Bracers 22079 |
| Hands | Hands of the Exalted Herald | 12554 | BRD | Desert Bloom Gloves 20717 |
| Waist | Whipvine Cord | 18327 | DM East | Virtuous Belt 22078 |
| Legs | Padre's Trousers | 18386 | DM West | Senior Designer's Pantaloons 11841 |
| Feet | Faith Healer's Boots | 22247 | UBRS | Boots of the Full Moon 18507 |
| Ring | Rosewine Circle | 13178 | LBRS | Band of Mending 22334 |
| Ring | Fordring's Seal | 16058 | Quest | Band of Rumination 18103 |
| Trinket | Royal Seal of Eldre'Thalas (Priest) | 18469 | DM quest | Draconic Infused Emblem 22268 |
| Trinket | Blessed Prayer Beads | 19990 | Quest | Briarwood Reed 12930 |
| MH | The Hammer of Grace | 11923 | BRD | Hammer of Revitalization 22315 |
| OH | Tome of Divine Right | 22319 | UBRS Mor Grayhoof (T0.5) | Lei of the Lifegiver 19312 |
| Staff (option) | Redemption | 22406 | Strat Live | — |
| Wand | Wand of Eternal Light | 22254 | BRD | Stormrager 16997 |

Naxx (https://www.wowhead.com/classic/guide/priest-healing-naxxramas-best-in-slot-bis-gear-classic-era):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Circlet of Faith | 22514 | Naxx T3 |
| Neck | Amulet of the Fallen God | 21712 | C'Thun quest |
| Shoulder | Shoulderpads of Faith | 22515 | Naxx T3 |
| Back | Cloak of Suturing | 22960 | Patchwerk |
| Chest | Robe of Faith | 22512 | Naxx T3 |
| Wrist | Bracelets of Royal Redemption | 21604 | AQ40 |
| Hands | Gloves of Faith | 22517 | Naxx T3 |
| Waist | Grasp of the Old God | 21582 | C'Thun |
| Legs | Leggings of Faith | 22513 | Naxx T3 |
| Feet | Sandals of Faith | 22516 | Naxx T3 |
| Ring | Ring of Faith | 23061 | Kel'Thuzad |
| Ring | Band of Unanswered Prayers | 22939 | Anub'Rekhan |
| Trinket | Warmth of Forgiveness | 23027 | Four Horsemen |
| Trinket | Eye of the Dead | 23047 | Sapphiron |
| MH | Hammer of the Twisting Nether | 23056 | Kel'Thuzad |
| OH | Sapphiron's Right Eye | 23048 | Sapphiron |
| Staff | Atiesh (Priest) | 22631 | Legendary (Benediction 18608) |
| Wand | Wand of the Whispering Dead | 23009 | Razuvious |

Earlier phases (Icy Veins, https://www.icy-veins.com/wow-classic/priest-healer-pve-gear-best-in-slot):
- **P1:** Prophecy set (Gloves 16812, Boots 16811, Mantle 16816, Girdle 16817, Vambraces 16819). Halo of Transcendence 16921, Leggings of Transcendence 16922, Truefaith Vestments 14154, Raincaster Drape 12110. Fordring's Seal 16058 + Cauterizing Band 19140, Blessed Prayer Beads 19990 + Burst of Knowledge 11832, Benediction 18608.
- **P3:** Transcendence set (Pauldrons 16924, Robes 16923, Bindings 16926, Handguards 16920, Belt 16925). Crystal Adorned Crown 19132, Shroud of Pure Thought 19430, Empowered Leggings 19385, Boots of Pure Thought 19437, Pure Elementium Band 19382, Rejuvenating Gem 19395.
- **P5:** Don Rigoberto's Lost Hat 21615, The All-Seeing Eye of Zuldazar 19594, Ternary Mantle 21694, Cloak of Clarity 21583, Grasp of the Old God 21582, Hibernation Crystal 20636, Scepter of the False Prophet 21839 + Sartura's Might 21666, Antenna of Invigoration 21801.

### 2.9 Priest Shadow
Pre-raid (https://www.wowhead.com/classic/guide/shadow-priest-dps-pre-raid-best-in-slot-bis-gear-wow-classic). The top picks for several slots are random-suffix "of Shadow Wrath" greens (Archivist Cape 13386, Flameweave Cuffs 11766, Drakestone 10796). They share one ID across all suffixes, so fixed-stat items are listed instead:

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Spellweaver's Turban | 22267 | UBRS |
| Neck | Dark Advisor's Pendant | 18691 | Scholomance (alt Nacreous Shell Necklace 22403) |
| Shoulder | Felcloth Shoulders | 14112 | Tailoring |
| Back | Amplifying Cloak | 18350 | DM West |
| Chest | Robe of Winter Night | 14136 | Tailoring |
| Wrist | Sublime Wristguards | 18497 | DM North |
| Hands | Felcloth Gloves | 18407 | Tailoring |
| Waist | Ban'thok Sash | 11662 | BRD |
| Legs | Leggings of Torment | 22342 | UBRS Valthalak (alt Skyshroud Leggings 13170) |
| Feet | Maleki's Footwraps | 18735 | Strat |
| Ring | Rune Band of Wizardry | 22339 | UBRS Valthalak |
| Ring | Eye of Orgrimmar (H) / Songstone of Ironforge (A) | 12545 / 12543 | BRD quest |
| Trinket | Briarwood Reed | 12930 | UBRS |
| Trinket | Draconic Infused Emblem | 22268 | UBRS |
| MH | Scepter of the Unholy | 13349 | Strat |
| OH | Scepter of Interminable Focus | 22329 | Strat Live |
| Staff | Lord Valthalak's Staff of Command | 22335 | UBRS (T0.5) |
| Wand | Skul's Ghastly Touch | 13396 | Strat |

Naxx (https://www.wowhead.com/classic/guide/shadow-priest-dps-naxxramas-best-in-slot-bis-gear-classic-era):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Preceptor's Hat | 23035 | Heigan |
| Neck | Choker of the Fire Lord | 18814 | Ragnaros |
| Shoulder | Rime Covered Mantle | 22983 | Gluth |
| Back | Cloak of the Devoured | 22731 | C'Thun |
| Chest | Crystal Webbed Robe | 23220 | Maexxna |
| Wrist | Burrower Bracers | 21611 | Ouro |
| Hands | Dark Storm Gauntlets | 21585 | C'Thun |
| Waist | Eyestalk Waist Cord | 22730 | C'Thun |
| Legs | Fel Infused Leggings | 19133 | Kazzak |
| Feet | Snowblind Shoes | 19131 | Azuregos |
| Ring | Ring of the Fallen God | 21709 | C'Thun quest |
| Ring | Band of the Inevitable | 23031 | Noth |
| Trinket | Neltharion's Tear | 19379 | Nefarian |
| Trinket | The Restrained Essence of Sapphiron | 23046 | Sapphiron |
| MH | The End of Dreams | 22988 | Grobbulus |
| OH | Tome of Shadow Force | 19309 | AV Exalted |
| Staff | Soulseeker | 22799 | Kel'Thuzad |
| Wand | Wand of Qiraji Nobility | 21603 | AQ40 |

Earlier phases (Icy Veins, https://www.icy-veins.com/wow-classic/shadow-priest-dps-pve-gear-best-in-slot):
- **P1:** Choker of the Fire Lord 18814, Felcloth Shoulders 14112, Robe of Winter Night 14136, Felcloth Gloves 18407, Sash of Whispered Secrets 18809, Skyshroud Leggings 13170, Maleki's Footwraps 18735, Ring of Spell Power 19147 ×2, Briarwood Reed 12930 + Talisman of Ephemeral Power 18820, Anathema 18609, Skul's Ghastly Touch 13396.
- **P3:** Mish'undare 19375, Mantle of the Blackwing Cabal 19370, Cloak of the Brood Lord 19378, Bracers of Arcane Accuracy 19374, Ebony Flame Gloves 19407, Firemaw's Clutch 19400, Fel Infused Leggings 19133, Snowblind Shoes 19131, Band of Forced Concentration 19403 + Band of Dark Dominion 19434, Neltharion's Tear 19379 + Talisman of Ephemeral Power 18820, Lok'amir il Romathis 19360 + Master Dragonslayer's Orb 19366.
- **P5:** Tiara of the Oracle 21348, Cloak of the Devoured 22731, Vestments of the Oracle 21351, Burrower Bracers 21611, Dark Storm Gauntlets 21585, Ring of the Fallen God 21709 + Signet 21210, Wand of Qiraji Nobility 21603.

### 2.10 Shaman Elemental
Pre-raid (https://www.wowhead.com/classic/guide/elemental-shaman-dps-pre-raid-best-in-slot-bis-gear-wow-classic):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Spellweaver's Turban | 22267 | UBRS |
| Neck | Barbed Thorn Necklace | 18289 | DM East |
| Shoulder | Burial Shawl | 18681 | Scholomance |
| Back | Crystalline Threaded Cape | 20697 | Silithus quest (AQ patch) |
| Chest | Wildthorn Mail | 12624 | Blacksmithing (alt Robe of Everlasting Night 18385) |
| Wrist | Sublime Wristguards | 18497 | DM North |
| Hands | Hands of Power | 13253 | LBRS |
| Waist | Sash of the Windreaver | 18676 | Silithus |
| Legs | Skyshroud Leggings | 13170 | LBRS |
| Feet | Omnicast Boots | 11822 | BRD |
| Ring | Maiden's Circle | 13001 | BoE world drop |
| Ring | Rune Band of Wizardry | 22339 | UBRS Valthalak |
| Trinket | Royal Seal of Eldre'Thalas (Shaman) | 18471 | DM quest |
| Trinket | Briarwood Reed | 12930 | UBRS |
| MH | Witchblade | 13964 | Scholomance |
| OH | Scepter of Interminable Focus | 22329 | Strat Live |
| Totem | Totem of the Storm | 23199 | BoE world drop |

Naxx (https://www.wowhead.com/classic/guide/wow-classic-elemental-shaman-dps-naxxramas-best-in-slot-gear):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Mish'undare, Circlet of the Mind Flayer | 19375 | Nefarian |
| Neck | Amulet of Vek'nilash | 21608 | AQ40 |
| Shoulder | Pauldrons of Elemental Fury | 23664 | Naxx trash |
| Back | Cloak of the Necropolis | 23050 | Sapphiron |
| Chest | Garb of Royal Ascension | 21838 | AQ40 trash |
| Wrist | Rockfury Bracers | 21186 | Silithus quest |
| Hands | Dark Storm Gauntlets | 21585 | C'Thun |
| Waist | Eyestalk Waist Cord | 22730 | C'Thun |
| Legs | Leggings of Polarity | 23070 | Thaddius |
| Feet | Boots of Epiphany | 21600 | AQ40 |
| Ring | Ring of the Fallen God | 21709 | C'Thun quest |
| Ring | Band of the Inevitable | 23031 | Noth |
| Trinket | Natural Alignment Crystal | 19344 | BWL |
| Trinket | Mark of the Champion (caster) | 23207 | Kel'Thuzad quest |
| 2H | Brimstone Staff | 22800 | Loatheb (or The End of Dreams 22988 + Sapphiron's Left Eye 23049) |
| Totem | Totem of the Storm | 23199 | BoE world drop |

Earlier phases (Wowhead planners):
- **P1:** Helmet of Ten Storms 16947, Choker of the Fire Lord 18814, Deep Earth Spaulders 18829, Sapphiron Drape 17078, Robe of Volatile Power 19145, Pyremail Wristguards 11765, Hands of Power 13253, Mana Igniting Cord 19136, Skyshroud Leggings 13170, Omnicast Boots 11822, Ring of Spell Power 19147 ×2, Talisman of Ephemeral Power 18820 / Briarwood Reed 12930, Aurastone Hammer 17105 + Spirit of Aquementas 11904.
- **P3:** Mish'undare 19375, Cloak of the Brood Lord 19378, Bracers of Arcane Accuracy 19374, Gauntlets of Ten Storms 16948, Firemaw's Clutch 19400, Flarecore Leggings 19165, Snowblind Shoes 19131, Band of Forced Concentration 19403, Neltharion's Tear 19379, Lok'amir il Romathis 19360 + Therazane's Touch 19315, Totem of the Storm 23199.
- **P5:** Cloak of the Devoured 22731, Rockfury Bracers 21186, Dark Storm Gauntlets 21585, Eyestalk Waist Cord 22730, Stormcaller's Footguards 21373, Ring of the Fallen God 21709.

### 2.11 Shaman Enhancement
Pre-raid (https://www.wowhead.com/classic/guide/enhancement-shaman-dps-pre-raid-best-in-slot-bis-gear-wow-classic):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Crown of Tyranny | 13359 | Strat |
| Neck | Mark of Fordring | 15411 | Quest |
| Shoulder | Black Dragonscale Shoulders | 15051 | Leatherworking |
| Back | Cape of the Black Baron | 13340 | Strat |
| Chest | Savage Gladiator Chain | 11726 | BRD |
| Wrist | Bracers of the Eclipse | 18375 | DM West |
| Hands | Chromatic Gauntlets | 19157 | Leatherworking |
| Waist | Cloudrunner Girdle | 13252 | LBRS |
| Legs | Black Dragonscale Leggings | 15052 | Leatherworking |
| Feet | Black Dragonscale Boots | 16984 | Leatherworking |
| Ring | Tarnished Elven Ring | 18500 | DM North |
| Ring | Blackstone Ring | 17713 | Maraudon |
| Trinket | Blackhand's Breadth | 13965 | UBRS quest |
| Trinket | Hand of Justice | 11815 | BRD |
| 2H | Nightfall | 19169 | Blacksmithing (alt The Unstoppable Force 19323, Arcanite Reaper 12784) |
| Totem | Totem of Rage | 22395 | BRD |

Naxx (https://www.wowhead.com/classic/guide/wow-classic-enhancement-shaman-dps-naxxramas-best-in-slot-gear):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Crown of Destruction | 18817 | Ragnaros |
| Neck | Stormrage's Talisman of Seething | 23053 | Kel'Thuzad |
| Shoulder | Mantle of Wicked Revenge | 21665 | AQ40 |
| Back | Shroud of Dominion | 23045 | Sapphiron |
| Chest | Ghoul Skin Tunic | 23226 | Naxx trash |
| Wrist | Qiraji Execution Bracers | 21602 | AQ40 |
| Hands | Gloves of Enforcement | 21672 | AQ40 |
| Waist | Belt of Never-ending Agony | 21586 | C'Thun |
| Legs | Leggings of Apocalypse | 23071 | Four Horsemen |
| Feet | Boots of the Vanguard | 21493 | AQ20 |
| Ring | Band of Unnatural Forces | 23038 | Loatheb |
| Ring | Ring of the Qiraji Fury | 21677 | AQ40 |
| Trinket | Slayer's Crest | 23041 | Sapphiron |
| Trinket | Kiss of the Spider | 22954 | Maexxna |
| 2H | Dark Edge of Insanity (Orc) / Might of Menethil (others) | 21134 / 22798 | C'Thun / Kel'Thuzad |
| Totem | Totem of Rage | 22395 | BRD |

Earlier phases (Wowhead planners):
- **P1:** Crown of Destruction 18817, Onyxia Tooth Pendant 18404, Truestrike Shoulders 12927, Cape of the Black Baron 13340, Savage Gladiator Chain 11726, Wristguards of True Flight 18812, Chromatic Gauntlets 19157, Cloudrunner Girdle 13252, Devilsaur Leggings 15062, Sabatons of the Flamewalker 19144, Band of Accuria 17063 / Quick Strike Ring 18821, Hand of Justice 11815 / Blackhand's Breadth 13965, Sulfuras 17182.
- **P3:** Cloak of Draconic Might 19436, Therazane's Link 19380, Boots of the Shadow Flame 19381, Don Julio's Band 19325 / Master Dragonslayer's Ring 19384, Drake Fang Talisman 19406, Totem of Rage 22395.
- **P5:** The Eye of Hakkar 19856, Mantle of Wicked Revenge 21665, Cloak of the Fallen God 21710, Obsidian Mail Tunic 22191, Qiraji Execution Bracers 21602, Gloves of Enforcement 21672, Scaled Sand Reaver Leggings 21651, Boots of the Vanguard 21493, Earthstrike 21180, Dark Edge of Insanity 21134.

### 2.12 Shaman Restoration
Pre-raid (https://www.wowhead.com/classic/guide/shaman-healing-pre-raid-best-in-slot-bis-gear-wow-classic):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Insightful Hood | 18490 | DM North |
| Neck | Animated Chain Necklace | 18723 | Strat Undead |
| Shoulder | Mantle of Lost Hope | 22234 | BRD |
| Back | Hide of the Wild | 18510 | Leatherworking |
| Chest | Robes of the Exalted | 13346 | Strat |
| Wrist | Loomguard Armbraces | 13969 | Scholomance |
| Hands | Harmonious Gauntlets | 18527 | DM North |
| Waist | Corehound Belt | 19162 | Leatherworking |
| Legs | Padre's Trousers | 18386 | DM West |
| Feet | Faith Healer's Boots | 22247 | UBRS |
| Ring | Rosewine Circle | 13178 | LBRS |
| Ring | Fordring's Seal | 16058 | Quest |
| Trinket | Royal Seal of Eldre'Thalas (Shaman) | 18471 | DM quest |
| Trinket | Briarwood Reed | 12930 | UBRS |
| MH | The Hammer of Grace | 11923 | BRD |
| OH | Brightly Glowing Stone | 18523 | DM North |
| Totem | Totem of Sustaining | 23200 | Scholomance |

Naxx (https://www.wowhead.com/classic/guide/wow-classic-shaman-healing-naxxramas-best-in-slot-gear):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Earthshatter Headpiece | 22466 | Naxx T3 |
| Neck | Amulet of the Fallen God | 21712 | C'Thun quest |
| Shoulder | Wild Growth Spaulders | 18810 | MC |
| Back | Cloak of Clarity | 21583 | C'Thun |
| Chest | Earthshatter Tunic | 22464 | Naxx T3 |
| Wrist | Bracers of Ten Storms | 16943 | BWL |
| Hands | Gauntlets of Ten Storms | 16948 | BWL |
| Waist | Grasp of the Old God | 21582 | C'Thun |
| Legs | Earthshatter Legguards | 22465 | Naxx T3 |
| Feet | Greaves of Ten Storms | 16949 | BWL |
| Ring | Ring of the Martyr | 21620 | AQ40 |
| Ring | Ring of the Earthshatterer | 23065 | Kel'Thuzad |
| Trinket | Eye of the Dead | 23047 | Sapphiron |
| Trinket | Rejuvenating Gem | 19395 | BWL |
| MH | Hammer of the Twisting Nether | 23056 | Kel'Thuzad |
| OH | Shield of Condemnation | 22819 | Kel'Thuzad |
| Totem | Totem of Life | 22396 | AQ40 |

Earlier phases (Wowhead planners):
- **P1:** Earthfury set (Vestments 16841, Bracers 16840, Gauntlets 16839, Legguards 16843, Boots 16837). Helmet of Ten Storms 16947, Animated Chain Necklace 18723, Wild Growth Spaulders 18810, Archivist Cape 13386, Corehound Belt 19162, Cauterizing Band 19140 / Rosewine Circle 13178, Shard of the Scale 17064 / Briarwood Reed 12930, Aurastone Hammer 17105 + Malistar's Defender 17106.
- **P3:** Choker of the Fire Lord 18814, Shroud of Pure Thought 19430, Robes of the Exalted 13346, Bracers of Ten Storms 16943, Gauntlets of Ten Storms 16948, Empowered Leggings 19385, Boots of Pure Thought 19437, Pure Elementium Band 19382, Rejuvenating Gem 19395, Lok'amir il Romathis 19360 + Lei of the Lifegiver 19312.
- **P5:** Stormcaller's set (Diadem 21372, Pauldrons 21376, Hauberk 21374, Leggings 21375, Footguards 21373). Amulet of the Fallen God 21712, Cloak of Clarity 21583, Belt of Ten Storms 16944, Ring of the Martyr 21620, Natural Alignment Crystal 19344, Scepter of the False Prophet 21839 + Sartura's Might 21666, Totem of Life 22396.

### 2.13 Mage (Frost pre-raid through BWL; Fire for AQ and Naxx)
Pre-raid (https://www.wowhead.com/classic/guide/mage-dps-pre-raid-best-in-slot-bis-gear-wow-classic):

| Slot | Item | ID | Source | Alt |
|---|---|---|---|---|
| Head | Spellweaver's Turban | 22267 | UBRS | Crimson Felt Hat 18727 |
| Neck | Nacreous Shell Necklace | 22403 | Strat Live | Star of Mystaria 12103 |
| Shoulder | Boreal Mantle (Frost) | 11782 | BRD | Burial Shawl 18681 (Fire) |
| Back | Amplifying Cloak | 18350 | DM West | Crystalline Threaded Cape 20697 |
| Chest | Robe of the Archmage (Mage only) | 14152 | Tailoring | Freezing Lich Robes 14340 |
| Wrist | Dryad's Wrist Bindings | 19595 | WSG Exalted | Sublime Wristguards 18497 |
| Hands | Sorcerer's Gloves | 22066 | T0.5 | Hands of Power 13253 |
| Waist | Ban'thok Sash | 11662 | BRD | Defiler's 20163 (H) / Highlander's 20047 (A) Cloth Girdle |
| Legs | Skyshroud Leggings | 13170 | LBRS | PvP R8: Legionnaire's 22883 (H) / Knight-Captain's 23304 (A) |
| Feet | Omnicast Boots | 11822 | BRD | PvP R7: Blood Guard's 22860 (H) / Knight-Lieutenant's 23291 (A) |
| Ring | Rune Band of Wizardry | 22339 | UBRS Valthalak | Maiden's Circle 13001 |
| Ring | Freezing Band (Frost) | 942 | BoE world drop | Eye of Orgrimmar 12545 / Songstone of Ironforge 12543 |
| Trinket | Briarwood Reed | 12930 | UBRS | — |
| Trinket | Eye of the Beast | 13968 | UBRS quest | Draconic Infused Emblem 22268 |
| MH | Mindfang (H) / Sageclaw (A) | 20214 / 20070 | Arathi Basin Exalted | Witchblade 13964 |
| OH | Tome of the Ice Lord (Frost) | 19310 | AV Exalted | Tome of Fiery Arcana 19311 (Fire) |
| Staff (option) | Ironbark Staff | 20220 (H) / 20069 (A) | Arathi Basin Exalted | Lord Valthalak's Staff 22335 |
| Wand | Wand of Biting Cold | 19108 | AV quest | Bonecreeper Stylus 13938 |

Naxx, Fire (https://www.wowhead.com/classic/guide/mage-dps-naxxramas-best-in-slot-bis-gear-classic-era):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Frostfire Circlet | 22498 | Naxx T3 |
| Neck | Gem of Trapped Innocents | 23057 | Kel'Thuzad |
| Shoulder | Rime Covered Mantle | 22983 | Gluth |
| Back | Cloak of the Necropolis | 23050 | Sapphiron |
| Chest | Frostfire Robe | 22496 | Naxx T3 |
| Wrist | The Soul Harvester's Bindings | 23021 | Gothik |
| Hands | Dark Storm Gauntlets | 21585 | C'Thun |
| Waist | Eyestalk Waist Cord | 22730 | C'Thun |
| Legs | Leggings of Polarity | 23070 | Thaddius |
| Feet | Frostfire Sandals | 22500 | Naxx T3 |
| Ring | Frostfire Ring | 23062 | Kel'Thuzad |
| Ring | Ring of the Eternal Flame | 23237 | Naxx trash |
| Trinket | Neltharion's Tear | 19379 | Nefarian |
| Trinket | The Restrained Essence of Sapphiron | 23046 | Sapphiron (Mind Quickening Gem 19339) |
| MH | Wraith Blade | 22807 | Maexxna |
| OH | Sapphiron's Left Eye | 23049 | Sapphiron |
| Staff | Atiesh (Mage) | 22589 | Legendary |
| Wand | Doomfinger | 22821 | Kel'Thuzad |

Earlier phases (Icy Veins, https://www.icy-veins.com/wow-classic/mage-dps-pve-gear-best-in-slot):
- **P1 Frost:** Arcanist Crown 16795, Arcanist Bindings 16799, Arcanist Boots 16800, Choker of the Fire Lord 18814, Boreal Mantle 11782, Sapphiron Drape 17078, Robe of the Archmage 14152, Hands of Power 13253, Mana Igniting Cord 19136, Netherwind Pants 16915, Ring of Spell Power 19147 ×2, Talisman of Ephemeral Power 18820 + Briarwood Reed 12930, Azuresong Mageblade 17103 + Spirit of Aquementas 11904.
- **P3 Frost:** Mish'undare 19375, Mantle of the Blackwing Cabal 19370, Cloak of the Brood Lord 19378, Bracers of Arcane Accuracy 19374, Netherwind Gloves 16913, Ringo's Blizzard Boots 19438, Band of Forced Concentration 19403, Mind Quickening Gem 19339 + Neltharion's Tear 19379, Claw of Chromaggus 19347 + Tome of the Ice Lord 19310, Cold Snap 19130.
- **P5:** Enigma set (Circlet 21347, Robes 21343, Boots 21344), Amulet of Vek'nilash 21608, Cloak of the Devoured 22731, Rockfury Bracers 21186, Dark Storm Gauntlets 21585, Eyestalk Waist Cord 22730, Leggings of the Black Blizzard 21461, Ring of the Fallen God 21709 + Ritssyn's Ring of Chaos 21836, Sharpened Silithid Femur 21622 + Royal Scepter of Vek'lor 21597, Wand of Qiraji Nobility 21603.

### 2.14 Warlock
Pre-raid (https://www.wowhead.com/classic/guide/warlock-dps-pre-raid-best-in-slot-bis-gear-wow-classic, by Zephan of the Warlock Discord):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Spellweaver's Turban | 22267 | UBRS (Deathmist Mask 22074, T0.5) |
| Neck | Nacreous Shell Necklace | 22403 | Strat Live |
| Shoulder | Felcloth Shoulders | 14112 | Tailoring |
| Back | Shroud of Arcane Mastery | 22330 | BRD arena summon (Amplifying Cloak 18350) |
| Chest | Robe of the Void (Warlock only) | 14153 | Tailoring |
| Wrist | Sublime Wristguards | 18497 | DM North |
| Hands | Felcloth Gloves | 18407 | Tailoring |
| Waist | Ban'thok Sash | 11662 | BRD |
| Legs | Flarecore Leggings | 19165 | Tailoring (MC mats; alt Skyshroud Leggings 13170) |
| Feet | Maleki's Footwraps | 18735 | Strat |
| Ring | Rune Band of Wizardry | 22339 | UBRS |
| Ring | Don Mauricio's Band of Domination | 22433 | Scholomance |
| Trinket | Briarwood Reed | 12930 | UBRS |
| Trinket | Eye of the Beast | 13968 | UBRS quest |
| MH | Blade of the New Moon | 18372 | DM West |
| OH | Scepter of Interminable Focus | 22329 | Strat Live (Tome of Shadow Force 19309, AV) |
| Wand | Skul's Ghastly Touch | 13396 | Strat |

Naxx (https://www.wowhead.com/classic/guide/warlock-dps-naxxramas-best-in-slot-bis-gear-classic-era):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Plagueheart Circlet | 22506 | Naxx T3 |
| Neck | Gem of Trapped Innocents | 23057 | Kel'Thuzad |
| Shoulder | Plagueheart Shoulderpads | 22507 | Naxx T3 |
| Back | Cloak of the Necropolis | 23050 | Sapphiron |
| Chest | Plagueheart Robe | 22504 | Naxx T3 |
| Wrist | Rockfury Bracers | 21186 | Silithus quest |
| Hands | Dark Storm Gauntlets | 21585 | C'Thun |
| Waist | Eyestalk Waist Cord | 22730 | C'Thun |
| Legs | Leggings of Polarity | 23070 | Thaddius |
| Feet | Plagueheart Sandals | 22508 | Naxx T3 |
| Ring | Ring of the Fallen God | 21709 | C'Thun quest |
| Ring | Seal of the Damned | 23025 | Four Horsemen |
| Trinket | Neltharion's Tear | 19379 | Nefarian |
| Trinket | The Restrained Essence of Sapphiron | 23046 | Sapphiron |
| MH | Wraith Blade | 22807 | Maexxna |
| OH | Sapphiron's Left Eye | 23049 | Sapphiron |
| Staff | Atiesh (Warlock) | 22630 | Legendary |
| Wand | Doomfinger | 22821 | Kel'Thuzad |

Earlier phases (Icy Veins, https://www.icy-veins.com/wow-classic/warlock-dps-pve-gear-best-in-slot):
- **P1:** random "of Shadow Wrath" pieces, Choker of the Fire Lord 18814, Robe of Volatile Power 19145, Hands of Power 13253, Mana Igniting Cord 19136, Nemesis Leggings 16930, Maleki's Footwraps 18735, Ring of Spell Power 19147 ×2, Briarwood Reed 12930 + Talisman of Ephemeral Power 18820, Azuresong Mageblade 17103.
- **P3:** Mish'undare 19375, Mantle of the Blackwing Cabal 19370, Cloak of the Brood Lord 19378, Nemesis Robes 16931, Bracers of Arcane Accuracy 19374, Ebony Flame Gloves 19407, Nemesis Belt 16933, Fel Infused Leggings 19133, Nemesis Boots 16927, Band of Forced Concentration 19403 + Band of Dark Dominion 19434, Neltharion's Tear 19379.
- **P5:** Doomcaller's Circlet 21337 and Mantle 21335, Amulet of Vek'nilash 21608, Cloak of the Devoured 22731, Bloodvine Vest 19682, Leggings 19683 and Boots 19684 (Tailor-only for the set bonus), Rockfury Bracers 21186, Dark Storm Gauntlets 21585, Eyestalk Waist Cord 22730, Ring of Unspoken Names 21417, Sharpened Silithid Femur 21622 + Royal Scepter of Vek'lor 21597.

### 2.15 Druid Balance
Pre-raid (https://www.wowhead.com/classic/guide/balance-druid-dps-pre-raid-best-in-slot-bis-gear-wow-classic, planner):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Spellweaver's Turban | 22267 | UBRS |
| Neck | Nacreous Shell Necklace | 22403 | Strat Live |
| Shoulder | Burial Shawl | 18681 | Scholomance |
| Back | Spritecaster Cape | 11623 | BRD |
| Chest | Robe of Everlasting Night | 18385 | DM West |
| Wrist | Sublime Wristguards | 18497 | DM North |
| Hands | Hands of Power | 13253 | LBRS |
| Waist | Ban'thok Sash | 11662 | BRD |
| Legs | Skyshroud Leggings | 13170 | LBRS |
| Feet | Waterspout Boots | 18322 | DM East |
| Ring | Rune Band of Wizardry | 22339 | UBRS (T0.5) |
| Ring | Songstone of Ironforge (A) / Eye of Orgrimmar (H) | 12543 / 12545 | BRD quest |
| Trinket | Eye of the Beast | 13968 | UBRS quest |
| Trinket | Briarwood Reed | 12930 | UBRS |
| 2H | Lord Valthalak's Staff of Command | 22335 | UBRS (T0.5; alt Rod of the Ogre Magi 18534) |
| Idol | Idol of the Moon | 23197 | BoE world drop |

Naxx (https://www.wowhead.com/classic/guide/wow-classic-balance-druid-dps-naxxramas-best-in-slot-gear):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Mish'undare | 19375 | Nefarian |
| Neck | Gem of Trapped Innocents | 23057 | Kel'Thuzad |
| Shoulder | Rime Covered Mantle | 22983 | Gluth |
| Back | Cloak of the Necropolis | 23050 | Sapphiron |
| Chest | Bloodvine Vest | 19682 | Tailoring |
| Wrist | Rockfury Bracers | 21186 | AQ quest |
| Hands | Dark Storm Gauntlets | 21585 | C'Thun |
| Waist | Eyestalk Waist Cord | 22730 | C'Thun |
| Legs | Bloodvine Leggings | 19683 | Tailoring |
| Feet | Bloodvine Boots | 19684 | Tailoring |
| Ring | Ring of the Fallen God | 21709 | C'Thun quest |
| Ring | Band of the Inevitable | 23031 | Noth |
| Trinket | Neltharion's Tear | 19379 | Nefarian |
| Trinket | The Restrained Essence of Sapphiron | 23046 | Sapphiron |
| 2H | Brimstone Staff | 22800 | Loatheb (Atiesh 22632) |
| Idol | Idol of the Moon | 23197 | BoE world drop |

Earlier phases (Wowhead planners):
- **P2:** Crimson Felt Hat 18727, Choker of the Fire Lord 18814, Burial Shawl 18681, Sapphiron Drape 17078, Robe of Volatile Power 19145, Flarecore Wraps 18263, Hands of Power 13253, Mana Igniting Cord 19136, Flarecore Leggings 19165, Omnicast Boots 11822, Ring of Spell Power 19147 ×2, Talisman of Ephemeral Power 18820 + Briarwood Reed 12930, Staff of Dominance 18842.
- **P4:** Mish'undare 19375, Mantle of the Blackwing Cabal 19370, Cloak of Consumption 19857, Bloodvine set, Bracers of Arcane Accuracy 19374, Bloodtinged Gloves 19929, Firemaw's Clutch 19400, Band of Forced Concentration 19403, Neltharion's Tear 19379 + Zandalarian Hero Charm 19950, Lok'amir il Romathis 19360 + Tome of Arcane Domination 19308.
- **P5:** Amulet of Vek'nilash 21608, Cloak of the Devoured 22731, Rockfury Bracers 21186, Dark Storm Gauntlets 21585, Eyestalk Waist Cord 22730, Ring of the Fallen God 21709, Royal Scepter of Vek'lor 21597.

### 2.16 Druid Feral Cat
Pre-raid (https://www.wowhead.com/classic/guide/feral-druid-dps-pre-raid-best-in-slot-bis-gear-wow-classic, planner):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Wolfshead Helm | 8345 | Leatherworking (needed for powershifting) |
| Neck | Pendant of Celerity | 22340 | UBRS (T0.5; alt Mark of Fordring 15411) |
| Shoulder | Truestrike Shoulders | 12927 | UBRS |
| Back | Cape of the Black Baron | 13340 | Strat |
| Chest | Cadaverous Armor | 14637 | Scholomance |
| Wrist | Bracers of the Eclipse | 18375 | DM West |
| Hands | Devilsaur Gauntlets | 15063 | Leatherworking |
| Waist | Cloudrunner Girdle | 13252 | LBRS |
| Legs | Devilsaur Leggings | 15062 | Leatherworking |
| Feet | Boots of Ferocity | 22472 | DM Isalien (T0.5; alt Swiftwalker Boots 12553) |
| Ring | Tarnished Elven Ring | 18500 | DM North |
| Ring | Tarnished Elven Ring | 18500 | (a second copy) |
| Trinket | Blackhand's Breadth | 13965 | UBRS quest |
| Trinket | Hand of Justice | 11815 | BRD |
| 2H | Manual Crowd Pummeler | 9449 | Gnomeregan (used through Naxx) |
| Idol | Idol of Ferocity | 22397 | BRD |

Naxx (https://www.wowhead.com/classic/guide/wow-classic-feral-druid-dps-naxxramas-best-in-slot-gear):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Wolfshead Helm | 8345 | Leatherworking |
| Neck | Stormrage's Talisman of Seething | 23053 | Kel'Thuzad |
| Shoulder | Mantle of Wicked Revenge | 21665 | AQ40 |
| Back | Cloak of the Fallen God | 21710 | C'Thun quest |
| Chest | Ghoul Skin Tunic | 23226 | Naxx trash |
| Wrist | Qiraji Execution Bracers | 21602 | AQ40 |
| Hands | Gloves of Enforcement | 21672 | AQ40 |
| Waist | Belt of Never-ending Agony | 21586 | C'Thun |
| Legs | Leggings of Apocalypse | 23071 | Four Horsemen |
| Feet | Boots of the Vanguard | 21493 | AQ20 |
| Ring | Band of Unnatural Forces | 23038 | Loatheb |
| Ring | Signet Ring of the Bronze Dragonflight | 21205 | AQ rep |
| Trinket | Drake Fang Talisman | 19406 | BWL |
| Trinket | Kiss of the Spider | 22954 | Maexxna |
| 2H | Manual Crowd Pummeler | 9449 | Gnomeregan |
| Idol | Idol of Ferocity | 22397 | BRD |

Earlier phases:
- **P1:** Onyxia Tooth Pendant 18404, Cloak of the Shrouded Mists 17102, Wristguards of Stability 19146, Swiftwalker Boots 12553, Band of Accuria 17063 + Quick Strike Ring 18821.
- **P4:** Prestor's Talisman 19377, Cloak of Draconic Might 19436, Field Marshal's 16452 (A) / Warlord's 16549 (H) Dragonhide chest, Forest Stalker's Bracers 19587, Marshal's 16448 / General's 16555 gloves, Molten Belt 19163, Marshal's 16450 / General's 16552 legs, Boots of the Shadow Flame 19381, Circle of Applied Force 19432.
- **P5:** Vest of Swift Execution 21680, Jom Gabbar 23570.

### 2.17 Druid Feral Bear
Pre-raid (https://www.wowhead.com/classic/guide/feral-druid-tank-pre-raid-best-in-slot-bis-gear-wow-classic; balanced set):

| Slot | Item | ID | Source | Mitigation alt |
|---|---|---|---|---|
| Head | Mask of the Unforgiven | 13404 | Strat Live | — |
| Neck | Beads of Ogre Might | 22150 | DM quest | — |
| Shoulder | Truestrike Shoulders | 12927 | UBRS | Atal'ai Spaulders 10783 (random suffix) |
| Back | Phantasmal Cloak | 18689 | Scholomance | — |
| Chest | Breastplate of Bloodthirst | 12757 | Winterspring quest | Warbear Harness 15064 |
| Wrist | Blackmist Armguards | 12966 | UBRS | — |
| Hands | Devilsaur Gauntlets | 15063 | Leatherworking | Slaghide Gauntlets 13258 |
| Waist | Cloudrunner Girdle | 13252 | LBRS | — |
| Legs | Devilsaur Leggings | 15062 | Leatherworking | Warstrife Leggings 11821 |
| Feet | Boots of Ferocity | 22472 | DM (T0.5) | Ash Covered Boots 18716 |
| Ring | Myrmidon's Signet | 2246 | BoE world drop | — |
| Ring | Blackstone Ring | 17713 | Maraudon | Ring of Protection 15855 |
| Trinket | Blackhand's Breadth | 13965 | UBRS quest | Mark of Tyranny 13966 |
| Trinket | Smoking Heart of the Mountain | 11811 | Enchanting | — |
| 2H | Manual Crowd Pummeler | 9449 | Gnomeregan | Warden Staff 943 |
| Idol | Idol of Brutality | 23198 | Strat | — |

Naxx (mitigation from Icy Veins, https://www.icy-veins.com/wow-classic/feral-druid-tank-pve-gear-best-in-slot; threat from Wowhead, https://www.wowhead.com/classic/guide/wow-classic-feral-druid-tank-naxxramas-best-in-slot-gear):

| Slot | Mitigation | Threat |
|---|---|---|
| Head | Guise of the Devourer 21693 | Field Marshal's 16451 (A) / Warlord's 16550 (H) Dragonhide Helmet |
| Neck | Sadist's Collar 23023 | Stormrage's Talisman 23053 |
| Shoulder | Highlander's 20059 (A) / Defiler's 20194 (H) Leather Shoulders | Mantle of Wicked Revenge 21665 |
| Back | Cryptfiend Silk Cloak 22938 | Cloak of the Fallen God 21710 |
| Chest | Ghoul Skin Tunic 23226 | same |
| Wrist | Qiraji Execution Bracers 21602 | same |
| Hands | Gloves of the Hidden Temple 21605 | Marshal's 16448 / General's 16555 |
| Waist | Belt of Never-ending Agony 21586 | same |
| Legs | Leggings of Apocalypse 23071 | same |
| Feet | Boots of the Shadow Flame 19381 | same |
| Rings | Ring of Emperor Vek'lor 21601 + Signet of the Fallen Defender 23018 | Band of Unnatural Forces 23038 + Signet 21205 |
| Trinkets | Drake Fang Talisman 19406 + Kiss of the Spider 22954 | Kiss of the Spider 22954 + Slayer's Crest 23041 |
| Weapon | Blessed Qiraji War Hammer 21268 + Tome of Knowledge 13385 | Manual Crowd Pummeler 9449 |
| Idol | Idol of Brutality 23198 | same |

Earlier phases (Wowhead planners):
- **P2:** Lieutenant Commander's Dragonhide Headguard 23308 and Shoulders 23309, Knight-Captain's chest 23294 and legs 23295, Knight-Lieutenant's grips 23280 and treads 23281, Dragon's Blood Cape 17107, Blackmist Armguards 12966, Frostbite Girdle 14502, Band of Accuria 17063 + Heavy Dark Iron Ring 18879, Mark of Tyranny 13966 + Smoking Heart 11811, Unyielding Maul 18531.
- **P4:** Field Marshal's Dragonhide Helmet 16451, Puissant Cape 18541, Malfurion's Blessed Bulwark 19405, Forest Stalker's Bracers 19587, Taut Dragonhide Belt 19396, Master Dragonslayer's Ring 19384.
- **P5:** Vest of Swift Execution 21680, Gloves of the Hidden Temple 21605, Boots of the Vanguard 21493, Earthstrike 21180.

### 2.18 Druid Restoration
Pre-raid (https://www.wowhead.com/classic/guide/druid-healing-pre-raid-best-in-slot-bis-gear-wow-classic):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Insightful Hood | 18490 | DM North |
| Neck | Animated Chain Necklace | 18723 | Strat Undead |
| Shoulder | Living Shoulders | 15061 | Leatherworking |
| Back | Hide of the Wild | 18510 | Leatherworking |
| Chest | Robes of the Exalted | 13346 | Strat |
| Wrist | Bracers of Prosperity | 18525 | DM North |
| Hands | Hands of the Exalted Herald | 12554 | BRD |
| Waist | Whipvine Cord | 18327 | DM East (alt Sash of Mercy 14553) |
| Legs | Padre's Trousers | 18386 | DM West |
| Feet | Faith Healer's Boots | 22247 | UBRS |
| Ring | Rosewine Circle | 13178 | LBRS |
| Ring | Fordring's Seal | 16058 | Quest |
| Trinket | Royal Seal of Eldre'Thalas (Druid) | 18470 | DM quest |
| Trinket | Mindtap Talisman | 18371 | DM West |
| MH | The Hammer of Grace | 11923 | BRD |
| OH | Brightly Glowing Stone | 18523 | DM North |
| Idol | Idol of Rejuvenation | 22398 | UBRS Mor Grayhoof (T0.5) |

Naxx (https://www.wowhead.com/classic/guide/wow-classic-druid-healing-naxxramas-best-in-slot-gear; 4/8 T3 set):

| Slot | Item | ID | Source |
|---|---|---|---|
| Head | Crystal Adorned Crown | 19132 | Azuregos |
| Neck | Necklace of Necropsy | 23036 | Heigan |
| Shoulder | Dreamwalker Spaulders | 22491 | Naxx T3 |
| Back | Cloak of Suturing | 22960 | Patchwerk |
| Chest | Dreamwalker Tunic | 22488 | Naxx T3 |
| Wrist | Stormrage Bracers | 16904 | BWL |
| Hands | Stormrage Handguards | 16899 | BWL |
| Waist | Dreamwalker Girdle | 22494 | Naxx T3 |
| Legs | Stormrage Legguards | 16901 | MC |
| Feet | Boots of Pure Thought | 19437 | BWL |
| Ring | Pure Elementium Band | 19382 | Nefarian |
| Ring | Ring of the Dreamwalker | 23064 | Kel'Thuzad |
| Trinket | Wushoolay's Charm of Nature | 19955 | ZG |
| Trinket | Eye of the Dead | 23047 | Sapphiron |
| MH | Hammer of the Twisting Nether | 23056 | Kel'Thuzad |
| OH | Sapphiron's Right Eye | 23048 | Sapphiron |
| Idol | Idol of Health | 22399 | AQ40 |

Earlier phases (Wowhead planners):
- **P2:** Wild Growth Spaulders 18810, Gloves of Restoration 18309, Sash of Mercy 14553, Salamander Scale Pants 18875, Verdant Footpads 13954, Cauterizing Band 19140 ×2, Aurastone Hammer 17105 + Lei of the Lifegiver 19312.
- **P4:** Jin'do's Evil Eye 19885, Shroud of Pure Thought 19430, Stormrage Chestguard 16897, Corehound Belt 19162, Empowered Leggings 19385, Wushoolay's Charm 19955 + Rejuvenating Gem 19395, Grand Marshal's Warhammer 23454 / High Warlord's Battle Mace 23464.
- **P5:** Amulet of the Fallen God 21712, Cloak of Clarity 21583, Grasp of the Old God 21582, Ring of the Martyr 21620, Scepter of the False Prophet 21839 + Sartura's Might 21666, Idol of Health 22399.

---

## 3. Levelling gear lists
**No comprehensive per-level-bracket list exists for any class.** The closest partial sources:
- **Wowhead "Notable Classic WoW content" articles**, per level range, with key quest and dungeon items:
  - 20–30: https://classic.wowhead.com/news=294833
  - 30–39: https://www.wowhead.com/classic/news/notable-classic-wow-quests-and-items-from-level-30-39-295053
- **Wowhead "Best <Class> Weapons"** (levelling weapons by level):
  - https://www.wowhead.com/classic/guide/wow-classic-best-warrior-weapons
  - https://www.wowhead.com/classic/guide/wow-classic-best-rogue-weapons
  - https://classic.wowhead.com/guides/wow-classic-best-hunter-weapons
- **Wowhead "Unique and Irreplaceable Quest Rewards":** https://www.wowhead.com/classic/guide/unique-quest-rewards-classic-wow
- **Class levelling guides with gear notes:**
  - Wowhead (e.g. https://www.wowhead.com/classic/guide/classes/warrior/leveling-tips)
  - Icy Veins (e.g. https://www.icy-veins.com/wow-classic/classic-warrior-leveling-guide)
- **Warcraft Tavern Dungeon Levelling Guide** (dungeons by level): https://www.warcrafttavern.com/wow-classic/guides/dungeon-leveling-guide-wow-classic/
- **Twink lists** (useful as "best at level X" for bracket caps):
  - Warcraft Tavern Twink BiS tool (19/29/39): https://www.warcrafttavern.com/wow-classic/tools/bis-twink/
  - Wowhead level-19 guides (https://www.wowhead.com/classic/news/wow-classic-level-19-twink-class-guides-and-bis-gear-291929) and level-39 guides (https://www.wowhead.com/classic/guide/classic-level-39-twink-overview-9789)
- **WoW Forever:** Icy Veins Forever class guides have level-20 gear tables (beta cap) on reworked Forever items. https://www.icy-veins.com/wow-forever/
- **Avoid woweternity.com's "WoW: Forever" BiS pages.** Its feral-druid page lists plate and mail items and a Nefarian neck as "pre-raid", so it is unreliable.
- **Practical route:** score items from your 1.12 database with the weights above plus the 1e levelling multipliers, filtered by required level.

---

## 4. Recommended enchants
**Sources:**
- Icy Veins Classic `…/wow-classic/<slug>-pve-enchants-consumables`
- Wowhead Classic `…/guide/classes/<class>/<spec>/…-enchants-gems-pve`
- Names and IDs checked with Wowhead's tooltip API. "(verify)" means the recipe source is unconfirmed.

**Availability by phase:**

| Phase | Patch | What arrives |
|---|---|---|
| P1 | launch | Most Enchanting recipes; Crusader, Spell Power and Healing Power weapon enchants (formulas drop in MC); Lesser Arcanums; Mantles of the Dawn; scopes (Biznicks schematic from MC) |
| P2 | Dire Maul, 1.3 | Arcanum of Rapidity / Focus / Protection |
| P3 | BWL, 1.6 | Weapon Agility / Strength / Mighty Intellect / Mighty Spirit; Bracer Healing Power and Mana Regeneration |
| P4 | ZG, 1.7 | Class head/leg enchants and Zandalar Signets |
| P5 | AQ, 1.9 | New glove and cloak enchants; 2H Agility |
| P6 | Naxx, 1.11 | "…of the Scourge" shoulder enchants |

Vanilla has no ring enchants and no gems or sockets.

**Head and legs** (the same item works on either slot)

| Enchant | Effect | Source | ID |
|---|---|---|---|
| Lesser Arcanum of Voracity | +8 Str / Sta / Agi / Int / Spi | Burning Steppes libram quest (q4484) | item 11645 / 11646 / 11647 / 11648 / 11649 |
| Lesser Arcanum of Constitution | +100 HP | Burning Steppes | 11642 |
| Lesser Arcanum of Tenacity | +125 armor | Burning Steppes | 11643 |
| Lesser Arcanum of Resilience | +20 Fire resistance | Burning Steppes | 11644 |
| Lesser Arcanum of Rumination | +150 mana | Burning Steppes | 11622 |
| Arcanum of Rapidity | +1% haste | Dire Maul (Lorekeeper Lydros) | 18329 |
| Arcanum of Focus | +8 spell damage and healing | Dire Maul | 18330 |
| Arcanum of Protection | +1% dodge | Dire Maul | 18331 |

ZG class enchants: Zandalar Friendly, then a quest from Zanza turning in a Primal Hakkari Idol 22637 plus the class's Punctured Voodoo Doll. They are class-locked and need level 60.

| Class | Enchant | Effect | ID |
|---|---|---|---|
| Warrior | Presence of Might | +10 Sta, +7 Def, +15 block value | 19782 |
| Paladin | Syncretist's Sigil | +10 Sta, +7 Def, +24 healing | 19783 |
| Rogue | Death's Embrace | +28 AP, +1% dodge | 19784 |
| Hunter | Falcon's Call | +24 RAP, +10 Sta, +1% hit | 19785 |
| Shaman | Vodouisant's Vigilant Embrace | +15 Int, +13 spell damage/healing | 19786 |
| Mage | Presence of Sight | +18 spell damage/healing, +1% spell hit | 19787 |
| Warlock | Hoodoo Hex | +10 Sta, +18 spell damage/healing | 19788 |
| Priest | Prophetic Aura | +10 Sta, +4 MP5, +24 healing | 19789 |
| Druid | Animist's Caress | +10 Sta, +10 Int, +24 healing | 19790 |

**Shoulders**

| Enchant | Effect | Source | ID |
|---|---|---|---|
| Flame / Frost / Arcane / Nature / Shadow Mantle of the Dawn | +5 of one resistance | Argent Dawn (Revered, verify) | 18169 / 18170 / 18171 / 18172 / 18173 |
| Chromatic Mantle of the Dawn | +5 all resistances | Argent Dawn Exalted | 18182 |
| Zandalar Signet of Might | +30 AP | Zandalar Exalted + 15 Honor Tokens | 20077 |
| Zandalar Signet of Mojo | +18 spell damage/healing | Zandalar Exalted | 20076 |
| Zandalar Signet of Serenity | +33 healing | Zandalar Exalted | 20078 |
| Might of the Scourge | +26 AP, +1% crit | Naxx, Sapphiron (Argent Dawn requirement: verify) | 23548 |
| Power of the Scourge | +15 spell damage/healing, +1% spell crit | Naxx, Sapphiron | 23545 |
| Resilience of the Scourge | +31 healing, +5 MP5 | Naxx, Sapphiron | 23547 |
| Fortitude of the Scourge | +16 Sta, +100 armor | Naxx, Sapphiron | 23549 |

**Enchanting recipes by slot** (spell IDs; P1 unless noted)

| Slot | Recipes |
|---|---|
| Cloak | Lesser Agility (+3 Agi) 13882; Superior Defense (+70 armor) 20015; Greater Resistance (+5 all res) 20014. P5: Subtlety (−2% threat) 25084, Dodge (+1%) 25086, Greater Fire Res 25081, Greater Nature Res 25082 |
| Chest | Greater Stats (+4 all) 20025; Stats 13941; Major Health (+100) 20026; Major Mana (+100) 20028 |
| Bracer | Superior Strength (+9) 20010; Superior Stamina (+9) 20011; Greater Intellect (+7) 20008; Superior Spirit (+9) 20009; Deflection (+3 Def) 13931; Minor Agility 7779. P3: Healing Power (+24) 23802 (Argent Dawn Revered); Mana Regeneration (+4 MP5) 23801 |
| Gloves | Greater Agility (+7) 20012; Greater Strength (+7) 20013; Minor Haste (+1%) 13948. P5: Superior Agility (+15) 25080, Threat (+2%) 25072, Healing Power (+30) 25079, Fire Power (+20) 25078, Frost Power 25074, Shadow Power 25073 |
| Boots | Minor Speed 13890; Greater Agility (+7) 20023; Greater Stamina (+7) 20020; Spirit (+5) 20024 |
| Weapon | Crusader 20034 (formula from Scarlet mobs in EPL, verify); Spell Power (+30) 22749; Healing Power (+55) 22750 (both formulas drop in MC); Superior Striking (+5) 20031; Fiery Weapon 13898. P3: Agility (+15) 23800, Strength (+15) 23799, Mighty Intellect (+22) 23804, Mighty Spirit (+20) 23803 |
| 2H only | Superior Impact (+9) 20030; Major Intellect (+9) 20036; Major Spirit (+9) 20035. P5: Agility (+25) 27837 |
| Shield | Greater Stamina (+7) 20017; Superior Spirit (+9) 20016; Lesser Block (+2%) 13689 |

**Other professions**
- **Engineering scopes:** Biznicks 247x128 Accurascope (+3% ranged hit) 18283; Sniper Scope (+7, level 40) 10548; Deadly Scope (+5, level 30) 10546.
- **Leatherworking kits:** Core Armor Kit (+3 Def) 18251; Rugged Armor Kit (+40 armor) 15564.
- **Blacksmithing:** Thorium Shield Spike 12645, Iron Counterweight 6043 (+3% speed on 2H weapons), Mithril Spurs 7969. The tooltip shows a Blacksmithing requirement for these.

**Role × slot**
Each cell is the Naxx-era BiS, then " / " and a cheaper or earlier option. H/L = head and legs.

| Role | H/L | Shoulder | Back | Chest | Wrist | Hands | Feet | Weapon | OH / Shield / Ranged |
|---|---|---|---|---|---|---|---|---|---|
| Warrior DPS | LA Voracity (Str) / Rapidity | Might of the Scourge / Signet of Might | Lesser Agility (Icy Veins: Subtlety) | Greater Stats | Superior Strength | Superior Agility / Greater Strength | Minor Speed / Greater Agility | Crusader on both / Superior Striking; 2H Superior Impact | — |
| Warrior Prot | Presence of Might / LA Constitution | Fortitude (or Might) of the Scourge / Signet of Might | Dodge / Superior Defense | Greater Stats / Major Health | Superior Stamina / Superior Strength | Threat or Superior Agility | Minor Speed | Crusader | Shield: Greater Stamina / Thorium Spike |
| Paladin Holy | Syncretist's Sigil / Arcanum of Focus | Resilience of the Scourge / Signet of Serenity | Greater Resistance | Greater Stats / Major Mana | Healing Power / Greater Intellect | Healing Power | Minor Speed | Healing Power / Mighty Intellect | Shield: Greater Stamina |
| Paladin Prot | Syncretist's Sigil / LA Constitution | Fortitude of the Scourge | Superior Defense / Dodge | Greater Stats or Core Armor Kit | Deflection / Superior Stamina | Threat / Core Armor Kit | Minor Speed | Spell Power / Crusader | Shield: Greater Stamina |
| Paladin Ret | LA Voracity (Str) | Might of the Scourge / Signet of Might | Lesser Agility | Greater Stats | Superior Strength | Superior Agility / Greater Strength | Greater Agility | Crusader / Superior Impact | — |
| Hunter | Falcon's Call / LA Voracity (Agi) | Might of the Scourge / Signet of Might | Lesser Agility | Greater Stats | Minor Agility / Superior Stamina | Superior Agility / Greater Agility | Minor Speed / Greater Agility | 2H Agility / 1H Agility | Ranged: Biznicks / Sniper Scope → Deadly Scope |
| Rogue | Death's Embrace / LA Voracity (Agi) | Might of the Scourge / Signet of Might | Lesser Agility | Greater Stats | Superior Strength | Superior Agility / Greater Agility | Minor Speed / Greater Agility | MH Crusader | OH Crusader or Agility |
| Priest Holy/Disc | Prophetic Aura / Arcanum of Focus | Resilience of the Scourge / Signet of Serenity | Greater Resistance | Greater Stats / Major Mana | Healing Power / Superior Spirit | Healing Power | Minor Speed / Spirit | Healing Power / Mighty Intellect | — |
| Priest Shadow | Arcanum of Focus / LA Voracity (Int) | Power of the Scourge / Signet of Mojo | Greater Resistance / Subtlety | Greater Stats | Mana Regeneration or Greater Intellect | Shadow Power | Minor Speed | Spell Power | — |
| Shaman Elemental | Vodouisant's / Arcanum of Focus | Power of the Scourge / Signet of Mojo | Greater Resistance | Greater Stats | Greater Intellect / Mana Regeneration | Fire or Frost Power | Minor Speed | Spell Power | Shield: Greater Stamina |
| Shaman Enhancement | Rapidity / LA Voracity (Str) | Might of the Scourge / Signet of Might | Lesser Agility | Greater Stats | Superior Strength | Superior Agility / Greater Agility | Minor Speed | Crusader / Superior Impact | — |
| Shaman Resto | Vodouisant's / Arcanum of Focus | Resilience of the Scourge / Signet of Serenity | Greater Resistance | Greater Stats / Major Mana | Healing Power / Mana Regeneration | Healing Power | Minor Speed | Healing Power | Shield: Greater Stamina |
| Mage | Presence of Sight / Arcanum of Focus | Power of the Scourge / Signet of Mojo | Greater Resistance / Subtlety | Greater Stats | Greater Intellect | Fire or Frost Power | Minor Speed | Spell Power | — |
| Warlock | Hoodoo Hex / Arcanum of Focus | Power of the Scourge / Signet of Mojo | Greater Resistance / Subtlety | Greater Stats | Greater Intellect | Shadow (or Fire) Power | Minor Speed | Spell Power | — |
| Druid Balance | Arcanum of Focus / LA Voracity (Int) | Power of the Scourge / Signet of Mojo | Greater Resistance | Greater Stats | Greater Intellect | none exists | Minor Speed | Spell Power or 2H Major Intellect | — |
| Druid Cat | LA Voracity (Agi) | Might of the Scourge / Signet of Might | Lesser Agility | Greater Stats | Superior Strength | Superior Agility / Greater Agility | Minor Speed | 2H Agility / Iron Counterweight | — |
| Druid Bear | Rapidity (Wowhead) or Protection (Icy Veins) / Animist's Caress | Fortitude or Might of the Scourge | Superior Defense or Lesser Agility | Greater Stats or Major Health | Superior Stamina or Superior Strength | Threat or Superior Agility | Minor Speed / Greater Stamina | Iron Counterweight | — |
| Druid Resto | Animist's Caress / Arcanum of Focus | Resilience of the Scourge / Signet of Serenity | Greater Resistance | Greater Stats / Major Mana | Healing Power / Greater Spirit | Healing Power | Minor Speed | Healing Power / Mighty Intellect | — |

**Levelling enchants** (all P1):
- 2H: Lesser Impact → Impact → Greater Impact → Superior Impact.
- 1H: Striking → Greater Striking → Superior Striking. Fiery Weapon is a cheap proc. Move to Crusader at about 55–60.
- Chest: Stats (+3), moving to Greater Stats.
- Boots: Minor Speed is worth it at any level.
- Bracer and gloves: +5 Str or Agi, then +7.
- Hunter scopes: Deadly Scope at 30 → Sniper Scope at 40 → Biznicks.
- Head/legs: before 60, only the Lesser Arcanums.

---

## 5. PvP

### 5a. PvP reward gear in vanilla 1.12
Honor ranks, Classic Era layout (https://www.icy-veins.com/wow-classic/honor-system-overview):

| Rank | Reward |
|---|---|
| R1 | Tabard |
| R2 | Insignia trinket |
| R3 | Rare cloak, plus 10% vendor discount |
| R4 | Rare necklace |
| R5 | Rare bracers |
| R6 | Officer's tabard, potions, barracks access |
| R7 | Rare boots and gloves |
| R8 | Rare chest and legs |
| R9 | Battle standard |
| R10 | Rare helm and shoulders |
| R11 | Epic mount |
| R12 | Epic gloves, legs and boots |
| R13 | Epic helm, chest and shoulders |
| R14 | Epic weapons |

- Rank point thresholds: R2 2000, then +5000 per rank up to R14 at 60000. Classic Era has no rank decay.
- The pre-1.12 layout had R12 = chest/legs/boots and R13 = helm/shoulders/gloves (https://vanilla-wow-archive.fandom.com/wiki/PvP_rewards). The 1.12 rare set revamp uses IDs in the 22xxx–23xxx range, for example Knight-Lieutenant's Silk Walkers 23291.

**Battleground reputation rewards:**
- **Alterac Valley** (Stormpike Guard / Frostwolf Clan; https://www.wowhead.com/classic/guide/alterac-valley-rewards-pvp-classic-wow):
  - Honored: pendants and cloaks (AP and caster versions), and a belt for each armor type (19083–19098).
  - Revered: battle standard, Electrified Dagger / Glacial Blade, Crackling / Whiteout Staff, Stormstrike Hammer / Frostbite, quivers.
  - Exalted:
    - Rings: Don Julio's Band 19325, Don Rodrigo's Band 21563
    - Weapons: The Lobotomizer 19324, The Unstoppable Force 19323
    - Shield: The Immovable Object 19321
    - Tomes: Tome of Fiery Arcana 19311, Tome of the Ice Lord 19310, Tome of Shadow Force 19309
    - Off-hands: Therazane's Touch 19315, Lei of the Lifegiver 19312
    - Epic mount
  - The insignia trinket upgrades at each rep level: Stormpike 17900–17904 / Frostwolf 17905–17909.
- **Warsong Gulch** (Silverwing Sentinels / Warsong Outriders): consumables and trinkets at Friendly; level-bracketed weapons at Revered; level-60 bracers (e.g. Dryad's Wrist Bindings 19595, Forest Stalker's Bracers 19587, Berserker Bracers 19578); epic leggings and bracers per armor type plus the tabard at Exalted (e.g. Sentinel's Plate Legguards 22672, Outrider's Leather Pants 22740 / Sentinel's 22749).
  - Sources: https://www.wowhead.com/classic/guide/silverwing-sentinels-warsong-gulch-reputation-wow-classic and https://www.wowisclassic.com/en/guide/warsong-gulch/
- **Arathi Basin** (League of Arathor / The Defilers): Highlander's / Defiler's armor sets per armor type from Friendly to Exalted (e.g. Highlander's Plate Girdle 20041 Honored, Plate Greaves 20048 Revered, Plate Spaulders 20057 Exalted), plus Exalted weapons and cloaks (Ironbark Staff 20069 / 20220, Sageclaw 20070 / Mindfang 20214, Cloak of the Honor Guard 20073).
  - Source: https://www.wowhead.com/classic/guide/battlegrounds-pvp-wow-classic
  - Exact rep levels per item are in your database; I didn't verify them individually.

### 5b. PvP weights
See 1f. No source publishes full per-class PvP weight tables for vanilla, and Pawn has none.
