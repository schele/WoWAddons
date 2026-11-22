# Pester 3 tests for WagoChangelog.ps1. Run from the repo root:
#   powershell -NoProfile -Command "Invoke-Pester -Script tools/WagoChangelog.Tests.ps1 -EnableExit"

. (Join-Path $PSScriptRoot "WagoChangelog.ps1")

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

Describe "Invoke-ChangelogGit" {
    It "stops on a git error instead of returning nothing" {
        { Invoke-ChangelogGit @("log", "--format=%s", "0123456789abcdef0123456789abcdef01234567") } | Should Throw "git log"
    }
    It "reads git's text as UTF-8" {
        $text = "Caf$([char]0xE9) $([char]0x2013) ok"
        Invoke-ChangelogGit @("show", "-s", "--format=tformat:$text", "HEAD") | Should BeExactly $text
    }
}

# Against the repo's history up to $until, which later commits and uploads
# leave alone.
$until = "41355fe"

Describe "Get-WagoReleases" {
    It "finds each upload of an addon, in order" {
        $releases = Get-WagoReleases "BankBags" -Until $until
        ($releases | ForEach-Object Version) -join "," | Should Be "0.1.0,0.2.0,0.3.0,0.3.1"
        $releases[3].Commit | Should Be "2500d7ad615ac151a36c92827bd692ab4b135a4b"
        $releases[0].Date | Should Be ([datetime]"2026-11-06")
    }
    It "stops at -Until" {
        (Get-WagoReleases "BankBags" -Until "9e3b380" | ForEach-Object Version) -join "," | Should Be "0.1.0,0.2.0,0.3.0"
    }
    It "splits addons uploaded together at the same commit" {
        (Get-WagoReleases "AutoVendor" -Until $until | ForEach-Object Version) -join "," | Should Be "0.2.0,0.3.0,0.4.0"
    }
    It "adds an upload the record holds but git does not yet" {
        $releases = Get-WagoReleases "RankUp" @{ version = "0.2.0"; commit = "41355fe" } -Until $until
        ($releases | ForEach-Object Version) -join "," | Should Be "0.1.0,0.2.0"
        $releases[1].Date | Should Be (Get-Date).Date
    }
}

Describe "Get-WagoChangelog, failing" {
    It "stops when a recorded commit is gone, rather than send its versions empty" {
        $gone = @{ version = "0.2.0"; commit = "0123456789abcdef0123456789abcdef01234567" }
        { Get-WagoChangelog "RankUp" "RankUp" "0.3.0" $gone -Until $until } | Should Throw "git log"
    }
}

Describe "Get-WagoChangelog, merges" {
    It "leaves out merge commits" {
        Get-WagoChangelog "ClickHeal" "ClickHeal" "9.9.9" -Until $until | Should Not Match "Merge branch"
    }
}

Describe "Get-WagoChangelog" {
    $text = Get-WagoChangelog "RankUp" "RankUp" "0.2.0" -Date ([datetime]"2026-11-22") -Until $until
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
