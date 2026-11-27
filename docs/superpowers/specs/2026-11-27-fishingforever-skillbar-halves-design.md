# FishingForever: the skill bar in two halves

## Intent

The skill bar's words and its fill disagree. The label says `Fishing 27/175`,
the skill and its cap, but the fill under it is the catches since the last
skill point against how many a point usually takes
([SkillBar.lua](../../../FishingForever/SkillBar.lua), `draw`). A player reads
27/175 and expects a bar 15% full; they get something else, and no bar for the
skill itself.

## What was decided

One bar, the same frame and size, with two fills side by side in it. Each half
is only shown while it has something to say.

```
┌────────────────────────┬────────────────────────┐
│▓▓▓▓▓▓ Next point ░░░░░░│▓▓ Fishing 27/175 ░░░░░░│
└────────────────────────┴────────────────────────┘
   left, blue: catches        right, green: skill
   toward the next point      against its cap
```

| State | What the bar shows |
|---|---|
| A point takes more than one catch | Both halves |
| Every catch raises the skill (a point takes one catch, below 75 on the old rule) | The skill half alone, at full width: the next-point half would only flip on every cast |
| The game refused a cast here, or every fish got away ("too low here") | The left half comes back whatever the skill, the highest rank included, reading "too low here" in red: the warning is worth saying wherever a player stands, and matters most at low skill. At 300 both halves are grey, as at any cap |
| At a trainer's cap below 300 | Left half grey and reading "capped", skill half full and grey. Still a reason to go and train |
| At 300, the highest rank, with no warning | Neither fill: a slim strip with only `Fishing 300/300`. Clicking it opens the stats, as the bar does everywhere |

Colours: next point is FishingForever's blue (as today), skill is green, the
capped state grey. A thin dark line divides the halves when both show. The
tooltip says what each showing half is.

## Goals

- The number and the fill beside it always agree.
- The bar stays one frame of the size it is, so the stats window, which hard-codes
  the bar's height and takes the bar inside itself, does not change.
- The stats stay one click away at 300: the stats window only opens while the
  bar shows ([StatsPanel.lua](../../../FishingForever/StatsPanel.lua), `Sync`).

## Non-goals

- No new settings. It is the same bar, so showing, hiding and locking it are
  the options that already exist.
- No change to how catches or the expected catches per point are worked out
  (Skill.lua), or to the stats window's contents.

## Anti-goals

- The stats window's layout moving, or the stats becoming unreachable at 300.
- Two halves that can be mistaken for one progress: the labels and the colours
  carry that, so neither may be dropped while both halves show.

## Approaches considered

| Approach | Verdict |
|---|---|
| Two stacked bars, skill on top | Rejected: a bar's height more on screen and in the stats window, and the stats window's layout and its tests would change |
| A skill bar with a thin unlabelled strip for the next point | Rejected: the strip is easy to miss, and "too low here" and "capped" would have no room |
| Relabel only, no skill bar | Rejected: it was asked for a bar for the skill |
| **Two fills side by side in the one bar** | **Chosen**, by the user (their idea), over stacking |

At 300 the user chose the slim strip with the label over hiding the bar
entirely (stats then reachable only by `/ff stats`).

## Calls made without being asked

- "Every catch raises the skill" is `Skill.Expected(rank) <= 1`, so it follows
  the measured catches per point where there are enough, as the fill does.
- "300" is the skill's cap being 300 and reached. A cap below 300 is a trainer's.
- The strip at 300 keeps the bar's size rather than getting slimmer, so the
  stats window's layout does not move. It can be thinned later.
- The halves follow the bar's width: the stats window widens the bar to its
  own inside, and each half is half of whatever the bar is.
- The README's skill bar section is rewritten for it. No version bump: that
  belongs to a release.

## Left to the builder

How the two fills are built inside the frame (`SkillBar.Frame()` stays the one
frame the stats window, settings page and tests find the bar by), the exact
green, the divider's width, and where each label sits inside its half.
