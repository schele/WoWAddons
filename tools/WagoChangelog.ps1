# The changelog sent with each Wago upload: the addon's whole history, newest
# version first, one heading per version, from the commits that touched it.
# package.ps1 dot-sources this; tools/WagoChangelog.Tests.ps1 tests it.

# A leading "RankUp: " or "ForeverPanel, AutoVendor and MailHandler: ".
$script:changelogPrefix = '^[A-Z]\w*(?:(?:, | and )[A-Z]\w*)*:\s+'
# git runs here, wherever the caller stands.
$script:changelogRepo = Split-Path $PSScriptRoot -Parent

<#
    One commit subject as a changelog line, "- <subject>", without the addon
    names in front and with a capital first letter. $null for a commit about
    publishing: every subject that mentions Wago ("on Wago as", its project
    ID, screenshots for its Wago page) is one.
#>
function ConvertTo-ChangelogLine([string]$Subject) {
    if ($Subject -match '\bWago\b') {
        return $null
    }
    $text = ($Subject -replace $script:changelogPrefix, '').Trim()
    if (-not $text) {
        return $null
    }
    return "- " + $text.Substring(0, 1).ToUpperInvariant() + $text.Substring(1)
}

<#
    The changelog's Markdown from the releases, oldest first, each
    @{ Version; Date; Lines }: newest first, the oldest marked as the first
    release on Wago, and a version with no lines left says its number.
#>
function Format-WagoChangelog([object[]]$Releases) {
    $sections = @()
    for ($i = $Releases.Count - 1; $i -ge 0; $i--) {
        $release = $Releases[$i]
        $heading = "## $($release.Version) ($($release.Date.ToString('d MMM yyyy', [cultureinfo]::InvariantCulture)))"
        if ($i -eq 0) {
            $heading += ", first release on Wago"
        }
        $lines = @($release.Lines | Where-Object { $_ })
        if (-not $lines) {
            $lines = @("- Version $($release.Version)")
        }
        $sections += (@($heading) + $lines) -join "`n"
    }
    return $sections -join "`n`n"
}

<#
    Whether $Commit is $Of itself or one of its ancestors. Throws when git
    cannot tell, as for a commit that is gone: an answer guessed there would
    send a changelog that looks whole and is not.
#>
function Test-ChangelogAncestor([string]$Commit, [string]$Of) {
    & git -C $script:changelogRepo merge-base --is-ancestor $Commit $Of
    switch ($LASTEXITCODE) {
        0 { return $true }
        1 { return $false }
        default { throw "git merge-base --is-ancestor $Commit $Of failed (exit $LASTEXITCODE)." }
    }
}

<#
    Every upload of an addon so far, oldest first, each @{ Version; Commit;
    Date }, read from the git history of wago-uploads.json: each commit that
    changed the addon's recorded commit is an upload, dated by that commit,
    unless the record only went back to a commit the last upload already
    holds. That is a copy of the file made on a branch that had not seen the
    upload yet, and the merge after it puts the upload back: neither is one.
    $Current is the record on disk, @{ version; commit }: an upload not
    committed yet, added dated today when git does not have it. $Until is
    the commit the history ends at (the tests pin it).
#>
function Get-WagoReleases([string]$Name, [hashtable]$Current = $null, [string]$Until = "HEAD") {
    $releases = @()
    $last = $null
    $history = Invoke-ChangelogGit @("log", "--reverse", "--format=%H %cd", "--date=short", $Until, "--", "wago-uploads.json")
    foreach ($line in $history) {
        $sha, $day = $line -split ' ', 2
        $record = (Invoke-ChangelogGit @("show", "${sha}:wago-uploads.json")) -join "`n" | ConvertFrom-Json
        $entry = $record.$Name
        if ($entry -and $entry.commit -ne $last) {
            if ($last -and (Test-ChangelogAncestor $entry.commit $last)) {
                continue
            }
            $releases += [pscustomobject]@{
                Version = $entry.version
                Commit  = $entry.commit
                Date    = [datetime]::ParseExact($day, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
            }
            $last = $entry.commit
        }
    }
    if ($Current -and $Current.commit -and $Current.commit -ne $last) {
        $releases += [pscustomobject]@{ Version = $Current.version; Commit = $Current.commit; Date = (Get-Date).Date }
    }
    return $releases
}

# The changelog lines of the commits in $Range that touched $Folder, newest
# first. Merges are left out: their subjects say nothing about the addon.
function Get-ChangelogLines([string]$Range, [string]$Folder) {
    $subjects = Invoke-ChangelogGit @("log", "--no-merges", "--format=%s", $Range, "--", $Folder)
    $subjects | ForEach-Object { ConvertTo-ChangelogLine $_ } | Where-Object { $_ }
}

<#
    git's output in the repo, read as UTF-8 (Windows PowerShell reads a
    program's output in the console's code page, which garbles an "é" or a
    dash). Throws when git fails: a changelog with a release's commits
    missing must not go up as if it were whole.
#>
function Invoke-ChangelogGit([string[]]$Arguments) {
    $encoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
    try {
        $output = & git -C $script:changelogRepo @Arguments
        $code = $LASTEXITCODE
    }
    finally {
        [Console]::OutputEncoding = $encoding
    }
    if ($code -ne 0) {
        throw "git $($Arguments -join ' ') failed (exit $code)."
    }
    return $output
}

<#
    The changelog for uploading $Version of addon $Name (folder $Folder):
    every earlier upload with the commits in it, and $Version, dated $Date,
    with the commits since the last upload. $Current and $Until are as for
    Get-WagoReleases.
#>
function Get-WagoChangelog([string]$Name, [string]$Folder, [string]$Version,
    [hashtable]$Current = $null, [datetime]$Date = (Get-Date), [string]$Until = "HEAD") {
    $sections = @()
    $previous = $null
    foreach ($release in @(Get-WagoReleases $Name $Current $Until)) {
        $range = if ($previous) { "$previous..$($release.Commit)" } else { $release.Commit }
        $sections += [pscustomobject]@{
            Version = $release.Version; Date = $release.Date; Lines = @(Get-ChangelogLines $range $Folder)
        }
        $previous = $release.Commit
    }
    $range = if ($previous) { "$previous..$Until" } else { $Until }
    $sections += [pscustomobject]@{ Version = $Version; Date = $Date.Date; Lines = @(Get-ChangelogLines $range $Folder) }
    return Format-WagoChangelog $sections
}
