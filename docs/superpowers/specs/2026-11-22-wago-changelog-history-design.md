# Wago changelog with every version's history

## Why

An addon's Changelog tab on Wago shows the text sent with its latest upload.
`package.ps1` sends only the commits since the previous upload, and a first
release sends "First release on Wago.", so a page never shows what came in
each version, and RankUp's says nothing at all. Carl wants the history
around each version update visible there.

## Goals

- Every upload's changelog holds the addon's whole history, newest version
  first, one heading per version with its date.
- Each version lists the commits that touched the addon in it, cleaned up
  for players.

## Non-goals

- Hand-written notes or a CHANGELOG.md to keep up: a cleaned-up commit list
  is enough (Carl, 2026-11-22).
- Rewriting the text of releases already on Wago. Each page shows the full
  history from that addon's next upload.

## Approaches

| Approach | Trade-off |
|---|---|
| A `CHANGELOG.md` per addon, drafted from commits and edited, sent whole | Reads best, but work at every release |
| **Generated from git at upload time** (picked) | Nothing to keep up, reads like a commit log |

Carl picked the generated list.

## Design

- **Version boundaries** come from the git history of `wago-uploads.json`:
  each commit that changed an addon's entry recorded its version and the
  commit uploaded. Versions are told apart by that recorded commit, in
  order. The date shown is the date of the commit that changed the record.
- **A version's lines** are the commits touching the addon's folder after
  the previous version's recorded commit, up to its own. The first version
  holds everything up to its recorded commit. The version being uploaded
  holds the commits since the last recorded one, up to HEAD, dated today.
- **Cleaning:** drop the leading `Name: ` (also `A, B and C: `), capitalise
  the first letter, and leave out publishing commits: "on Wago as", the Wago
  project ID, and screenshots for the Wago page.
- **Shape:**

  ```
  ## 0.2.0 (22 Nov 2026)
  - Upgrades a rank on bars 2-8 too

  ## 0.1.0 (6 Nov 2026), first release on Wago
  - Find the buttons holding an older rank
  - ...
  ```

  A version left with no lines after cleaning says "- Version x.y.z".
- `-WagoDryRun` prints the whole text, as now.

## Left to the builder

- Exactly how the publishing-commit filter is matched, as long as the three
  kinds above are dropped and player-facing commits are not.
- Where the code lives (in `package.ps1`, or a helper it calls) and how it
  is tested.
