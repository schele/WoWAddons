# Wago Changelog History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Wago upload sends the addon's whole history, newest version first, one heading per version, built from git.

**Architecture:** A new `tools/WagoChangelog.ps1` holds the changelog functions; `package.ps1` dot-sources it and `Publish-Wago` calls `Get-WagoChangelog` in place of its one-range `git log`. Version boundaries come from the git history of `wago-uploads.json`; each version's lines are the commit subjects touching the addon's folder in its range, cleaned up.

**Tech Stack:** Windows PowerShell 5.1, git, Pester 3.4.0 (ships with Windows; `Describe`/`It`/`Should` syntax; `Be` and `Match` ignore case, so case checks use `BeExactly` and `MatchExactly`).

**Spec:** [docs/superpowers/specs/2026-11-22-wago-changelog-history-design.md](../specs/2026-11-22-wago-changelog-history-design.md)

## Global Constraints

- Newest version first; heading `## <version> (<d MMM yyyy>)`, e.g. `## 0.1.0 (6 Nov 2026)`, month names in English whatever the PC's culture (`[cultureinfo]::InvariantCulture`).
- The oldest version's heading ends `, first release on Wago`.
- A version left with no lines says `- Version <version>`.
- A version's date is the date of the commit that changed its entry in `wago-uploads.json`; the version being uploaded is dated today.
- Lines: leading `Name: ` or `A, B and C: ` removed, first letter capitalised, `- ` in front.
- Left out: every subject that mentions Wago (`\bWago\b`, any case). This covers "on Wago as", "its Wago project ID", "for its Wago page", and the publishing-tool commits; no player-facing subject in the history mentions Wago (checked 2026-11-22).
- Sections separated by one blank line; lines joined with `` `n ``.

## Review Focus

1. **Upload not yet committed:** the working-tree `wago-uploads.json` holds an upload whose record commit is not in git yet. That version must still appear (dated today) and the new one count from its commit. Test in Task 2 (`-Current` appended).
2. **Same record commit for two addons in one upload** (`680d67b` uploaded three addons at `5bdfb0f`): each addon's history must still split at its own entries. Test in Task 2 (AutoVendor's versions).
3. **A record commit that touches the addon nothing** (RankUp 0.1.0 was recorded at `91906d9`, not a RankUp commit): ranges are `git log A..B -- Folder`, which works with any commit. Test in Task 2 (RankUp's first release lists its 11 commits).
4. **A version with only Wago commits in it:** shows `- Version x.y.z`, never an empty heading. Test in Task 1.
5. **A subject with a second colon** (`AutoVendor: pick items: from bags`): only the leading name prefix comes off. Test in Task 1.

Known and accepted: an addon whose folder was renamed (ThreatMeter → ThreatForever) lists only the commits since the rename, since a folder pathspec does not follow renames.

---

### Task 1: Clean lines and format the changelog

**Files:**
- Create: `tools/WagoChangelog.ps1`
- Test: `tools/WagoChangelog.Tests.ps1`

**Interfaces:**
- Produces:
  - `ConvertTo-ChangelogLine([string]$Subject) -> [string] or $null`: `"- <cleaned>"`, or `$null` for a subject that mentions Wago.
  - `Format-WagoChangelog([object[]]$Releases) -> [string]`: `$Releases` oldest first, each `[pscustomobject]@{ Version = [string]; Date = [datetime]; Lines = [string[]] }` (Lines already cleaned, newest first, may be empty). Returns the Markdown, newest version first.

- [ ] **Step 1: Write the failing tests**

`tools/WagoChangelog.Tests.ps1` starts with `. (Join-Path $PSScriptRoot "WagoChangelog.ps1")`.

```powershell
Describe "ConvertTo-ChangelogLine" {
    It "drops the addon prefix and capitalises" {
        ConvertTo-ChangelogLine "RankUp: never put a lower rank over a higher one" |
            Should BeExactly "- Never put a lower rank over a higher one"
    }
    It "drops a prefix naming several addons" {
        ConvertTo-ChangelogLine "ForeverPanel, AutoVendor and MailHandler: honor on the bar" |
            Should BeExactly "- Honor on the bar"
    }
    It "keeps a later colon" {
        ConvertTo-ChangelogLine "AutoVendor: pick items: from bags" | Should BeExactly "- Pick items: from bags"
    }
    It "keeps a subject with no prefix" {
        ConvertTo-ChangelogLine "fix the popup" | Should BeExactly "- Fix the popup"
    }
    It "leaves out publishing commits" {
        ConvertTo-ChangelogLine "ForeverPanel: on Wago as 0.6.0" | Should BeNullOrEmpty
        ConvertTo-ChangelogLine "LFGBoard: its Wago project ID" | Should BeNullOrEmpty
        ConvertTo-ChangelogLine "RankUp: a screenshot of the upgrade popup, for its Wago page" | Should BeNullOrEmpty
    }
}

Describe "Format-WagoChangelog" {
    It "puts the newest version first, the oldest marked as the first release" {
        $text = Format-WagoChangelog @(
            [pscustomobject]@{ Version = "0.1.0"; Date = [datetime]"2026-11-06"; Lines = @("- Find the buttons") },
            [pscustomobject]@{ Version = "0.2.0"; Date = [datetime]"2026-11-22"; Lines = @("- Bars 2-8 too", "- A wider popup") }
        )
        $text | Should BeExactly "## 0.2.0 (22 Nov 2026)`n- Bars 2-8 too`n- A wider popup`n`n## 0.1.0 (6 Nov 2026), first release on Wago`n- Find the buttons"
    }
    It "says the version when nothing is left to list" {
        $text = Format-WagoChangelog @(
            [pscustomobject]@{ Version = "0.1.0"; Date = [datetime]"2026-11-06"; Lines = @("- Find the buttons") },
            [pscustomobject]@{ Version = "0.1.1"; Date = [datetime]"2026-11-07"; Lines = @() }
        )
        $text | Should MatchExactly "^## 0\.1\.1 \(7 Nov 2026\)`n- Version 0\.1\.1`n`n"
    }
}
```

- [ ] **Step 2: Run them and see them fail**

Run: `powershell -NoProfile -Command "Invoke-Pester -Script tools/WagoChangelog.Tests.ps1 -EnableExit"`
Expected: FAIL, `WagoChangelog.ps1` not found.

- [ ] **Step 3: Implement both functions in `tools/WagoChangelog.ps1`**

Prefix pattern: `^[A-Z]\w*(?:(?:, | and )[A-Z]\w*)*:\s+`. Date: `$date.ToString("d MMM yyyy", [cultureinfo]::InvariantCulture)`. A header comment says what the file is for and that `package.ps1` dot-sources it.

- [ ] **Step 4: Run them and see them pass**

Run: `powershell -NoProfile -Command "Invoke-Pester -Script tools/WagoChangelog.Tests.ps1 -EnableExit"`
Expected: all pass, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add tools/WagoChangelog.ps1 tools/WagoChangelog.Tests.ps1
git commit -m "Publishing: changelog lines without the addon name or Wago commits, newest version first"
```

### Task 2: Read the versions from git and send the whole history

**Files:**
- Modify: `tools/WagoChangelog.ps1`
- Modify: `package.ps1` (dot-source the tool after `$wagoRecordPath`; `Publish-Wago`'s changelog block, lines 114-121; help text at the top)
- Modify: `docs/publishing.md` ("Every release": what the changelog holds, and how to run the tests)
- Test: `tools/WagoChangelog.Tests.ps1`

**Interfaces:**
- Consumes: `ConvertTo-ChangelogLine`, `Format-WagoChangelog` (Task 1).
- Produces:
  - `Get-WagoReleases([string]$Name, [hashtable]$Current = $null) -> [object[]]`: oldest first, each `[pscustomobject]@{ Version; Commit; Date }`. Walks `git log --reverse --format="%H %cd" --date=short -- wago-uploads.json`; at each commit reads `git show <sha>:wago-uploads.json` and adds a release when `$Name`'s entry has a commit different from the last release's. `$Current` (`@{ version; commit }`, the working-tree record) is appended, dated today, when its commit is not the last release's.
  - `Get-WagoChangelog([string]$Name, [string]$Folder, [string]$Version, [hashtable]$Current = $null, [datetime]$Date = (Get-Date)) -> [string]`: the releases, plus `$Version` dated `$Date` covering `<last commit>..HEAD`; each release's lines from `git log --format=%s <previous commit>..<its commit> -- $Folder` (the first: `git log --format=%s <its commit> -- $Folder`) through `ConvertTo-ChangelogLine`, nulls dropped; then `Format-WagoChangelog`.
  - Both run git in the repo root (the tool's parent folder), whatever the caller's working directory.

- [ ] **Step 1: Write the failing tests** (against the repo's real history, which does not change)

```powershell
Describe "Get-WagoReleases" {
    It "finds each upload of an addon, in order" {
        $releases = Get-WagoReleases "BankBags"
        ($releases | ForEach-Object Version) -join "," | Should Be "0.1.0,0.2.0,0.3.0,0.3.1"
        $releases[3].Commit | Should Be "2500d7ad615ac151a36c92827bd692ab4b135a4b"
        $releases[0].Date | Should Be ([datetime]"2026-11-06")
    }
    It "splits addons uploaded together at the same commit" {
        (Get-WagoReleases "AutoVendor" | ForEach-Object Version) -join "," | Should Be "0.2.0,0.3.0,0.4.0"
    }
    It "adds an upload the record holds but git does not yet" {
        $releases = Get-WagoReleases "RankUp" @{ version = "0.2.0"; commit = "41355fe" }
        ($releases | ForEach-Object Version) -join "," | Should Be "0.1.0,0.2.0"
        $releases[1].Date | Should Be (Get-Date).Date
    }
}

Describe "Get-WagoChangelog" {
    $text = Get-WagoChangelog "RankUp" "RankUp" "0.2.0" -Date ([datetime]"2026-11-22")
    It "puts the new version on top" {
        $text | Should MatchExactly "^## 0\.2\.0 \(22 Nov 2026\)`n- A sharper icon, drawn at full size instead of scaled up`n"
    }
    It "lists the first release's commits under its heading" {
        $text | Should MatchExactly "## 0\.1\.0 \(6 Nov 2026\), first release on Wago`n- A settings page with Check my bars now`n"
        $text | Should MatchExactly "`n- Find the buttons holding an older rank$"
    }
    It "leaves out the Wago commits" {
        $text | Should Not Match "Wago page|Publishing|-Install"
    }
}
```

The `0.2.0` section holds the RankUp commits after `91906d9` that do not mention Wago: only `12b9387` (the sharper icon). `d36ccda` ("Publishing: ... Wago Addons") and `0cb2f93` ("Icons: ... with Wago thumbnails") are left out.

- [ ] **Step 2: Run them and see them fail**

Run: `powershell -NoProfile -Command "Invoke-Pester -Script tools/WagoChangelog.Tests.ps1 -EnableExit"`
Expected: the Task 1 tests pass; the new ones FAIL, `Get-WagoReleases` not recognised.

- [ ] **Step 3: Implement `Get-WagoReleases` and `Get-WagoChangelog` in `tools/WagoChangelog.ps1`**

Use `git -C <repo root>` for every call. Compare record commits by full hash.

- [ ] **Step 4: Run the tests and see them pass**

Run: `powershell -NoProfile -Command "Invoke-Pester -Script tools/WagoChangelog.Tests.ps1 -EnableExit"`
Expected: all pass, exit code 0.

- [ ] **Step 5: Use it in `package.ps1`**

Dot-source `tools/WagoChangelog.ps1` near the top. In `Publish-Wago`, replace the changelog block with `$changelog = Get-WagoChangelog $name $folder.Name $version $last`. The help text says the changelog holds every version's history. `docs/publishing.md` "Every release": replace "builds the changelog from the commits that touched the addon since its last upload" with the whole-history behaviour and the left-out Wago commits, and give the test command; "Once per addon" step 4 no longer needs the "First release on Wago." sentence.

- [ ] **Step 6: Dry-run it**

Run: `.\package.ps1 RankUp -WagoDryRun -Install -WowPath "$env:TEMP\wago-dry"`, after temporarily raising `## Version:` in `RankUp/RankUp.toc` to `0.2.0` (undo afterwards: `git checkout RankUp/RankUp.toc`).
Expected: the printed metadata's `changelog` starts `## 0.2.0 (<today>)` and holds `## 0.1.0 (6 Nov 2026), first release on Wago` with RankUp's eleven early commits. Nothing is uploaded. Also run `.\package.ps1 ForeverPanel -WagoDryRun -Install -WowPath "$env:TEMP\wago-dry"` with its version raised the same way: five older versions (0.5.0, 0.5.1, 0.5.2, 0.6.0, 0.7.0) under the new one. Then `Remove-Item -Recurse "$env:TEMP\wago-dry"`.

- [ ] **Step 7: Commit**

```bash
git add tools/WagoChangelog.ps1 tools/WagoChangelog.Tests.ps1 package.ps1 docs/publishing.md docs/superpowers/specs/2026-11-22-wago-changelog-history-design.md docs/superpowers/plans/2026-11-22-wago-changelog-history.md
git commit -m "Publishing: Wago's changelog holds every version's history, newest first"
```
