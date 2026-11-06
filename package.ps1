#requires -Version 5.1
<#
    Packages each addon in this repo into dist/<name>-<version>.zip.

        .\package.ps1                          every addon
        .\package.ps1 ForeverPanel             just that one
        .\package.ps1 ForeverPanel -Install    and copy it into the client

    An addon is any top-level folder holding a .toc. The zip contains a single
    top-level folder named after the addon, so it extracts straight into
    Interface/AddOns.

    -Install copies into a WoW client; -WowPath picks which one.

    -Install also publishes to Wago Addons, once per version: when the .toc's
    '## Version:' has not been uploaded yet, the zip goes up as a new version.
    Reinstalling the same version only installs. Needs:

        ## X-Wago-ID: <project id>      in the addon's .toc
        WAGO_API_TOKEN                   environment variable, from
                                         addons.wago.io/account/apikeys

    What went up is recorded in wago-uploads.json. -NoWago skips publishing,
    -Stability beta|alpha marks the upload as a pre-release, and -WagoDryRun
    prints what would be sent instead of sending it.
#>
[CmdletBinding()]
param(
    [string[]]$Addon,
    [switch]$Install,
    [string]$WowPath = "C:\Program Files (x86)\World of Warcraft\_forever_",
    [switch]$NoWago,
    [ValidateSet("stable", "beta", "alpha")]
    [string]$Stability = "stable",
    [switch]$WagoDryRun
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

Set-Location $PSScriptRoot

$wagoRecordPath = Join-Path $PSScriptRoot "wago-uploads.json"
$script:wagoPatches = $null

function Get-TocField([string[]]$tocLines, [string]$field) {
    $tocLines | Where-Object { $_ -match "^##\s*$([regex]::Escape($field)):\s*(.+)$" } |
        ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1
}

function Get-WagoRecord {
    $record = @{}
    if (Test-Path $wagoRecordPath) {
        $json = Get-Content $wagoRecordPath -Raw | ConvertFrom-Json
        foreach ($property in $json.PSObject.Properties) {
            $record[$property.Name] = @{ version = $property.Value.version; commit = $property.Value.commit }
        }
    }
    return $record
}

function Save-WagoRecord([hashtable]$record) {
    $ordered = [ordered]@{}
    foreach ($key in ($record.Keys | Sort-Object)) {
        $ordered[$key] = [ordered]@{ version = $record[$key].version; commit = $record[$key].commit }
    }
    $json = $ordered | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($wagoRecordPath, "$json`n", (New-Object System.Text.UTF8Encoding $false))
}

# "11509, 16001" -> supported_classic_patches 1.15.9, supported_forever_patches
# 1.60.1. Wago names the flavour, so the flavour is whichever of its lists
# holds the patch, and an interface it does not know stops the upload.
function Get-WagoSupport([string]$interfaceLine) {
    if (-not $script:wagoPatches) {
        $script:wagoPatches = (Invoke-RestMethod "https://addons.wago.io/api/data/game").patches
    }

    $support = [ordered]@{}
    foreach ($interface in ($interfaceLine -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $n = [int]$interface
        $patch = "{0}.{1}.{2}" -f [int][math]::Floor($n / 10000), ([int][math]::Floor($n / 100) % 100), ($n % 100)
        $flavours = @($script:wagoPatches.PSObject.Properties |
            Where-Object { @($_.Value) -contains $patch } | ForEach-Object { $_.Name })
        if (-not $flavours) {
            throw "Wago has no game version $patch (from '## Interface: $interface')."
        }
        foreach ($flavour in $flavours) {
            $key = "supported_${flavour}_patches"
            if (-not $support.Contains($key)) {
                $support[$key] = @()
            }
            $support[$key] += $patch
        }
    }
    return $support
}

function Publish-Wago($name, $version, $zip, [string[]]$tocLines, $folder) {
    $wagoId = Get-TocField $tocLines "X-Wago-ID"
    if (-not $wagoId) {
        Write-Host "Wago: skipped, $name.toc has no '## X-Wago-ID:' line."
        return
    }

    $record = Get-WagoRecord
    $last = $record[$name]
    if ($last -and $last.version -eq $version) {
        Write-Host "Wago: already has $name $version. Raise '## Version:' to publish a new one."
        return
    }

    # The commits that touched this addon since the last upload, newest first.
    $changelog = $null
    if ($last -and $last.commit) {
        $changelog = (git log --format="- %s" "$($last.commit)..HEAD" -- $folder.Name 2>$null) -join "`n"
    }
    if (-not $changelog) {
        $changelog = if ($last) { "- Version $version" } else { "- First release on Wago." }
    }

    $metadata = [ordered]@{ label = $version; stability = $Stability; changelog = $changelog }
    $support = Get-WagoSupport (Get-TocField $tocLines "Interface")
    foreach ($key in $support.Keys) {
        $metadata[$key] = @($support[$key])
    }
    $json = $metadata | ConvertTo-Json -Depth 3

    if ($WagoDryRun) {
        Write-Host "Wago (dry run): would POST $zip to project $wagoId with:"
        Write-Host $json
        return
    }

    # The user-level variable too, so a terminal opened before it was set
    # still finds it.
    $token = $env:WAGO_API_TOKEN
    if (-not $token) {
        $token = [Environment]::GetEnvironmentVariable("WAGO_API_TOKEN", "User")
    }
    if (-not $token) {
        Write-Warning "Wago: skipped, WAGO_API_TOKEN is not set. Make a key at addons.wago.io/account/apikeys."
        return
    }

    $metaFile = [System.IO.Path]::GetTempFileName()
    $responseFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($metaFile, $json, (New-Object System.Text.UTF8Encoding $false))
        $code = & curl.exe -sS -o $responseFile -w "%{http_code}" `
            -H "authorization: Bearer $token" -H "accept: application/json" `
            -F "metadata=<$metaFile" -F "file=@$zip" `
            "https://addons.wago.io/api/projects/$wagoId/version"

        if ($code -eq "200" -or $code -eq "201") {
            $record[$name] = @{ version = $version; commit = (git rev-parse HEAD).Trim() }
            Save-WagoRecord $record
            Write-Host "Wago: published $name $version ($Stability)."
        }
        elseif ($code -eq "404") {
            Write-Warning "Wago: no project with id '$wagoId' (from $name.toc)."
        }
        else {
            $body = Get-Content $responseFile -Raw -ErrorAction SilentlyContinue
            Write-Warning "Wago: upload of $name $version failed (HTTP $code). $body"
        }
    }
    finally {
        Remove-Item $metaFile, $responseFile -Force -ErrorAction SilentlyContinue
    }
}

$folders = Get-ChildItem -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName "$($_.Name).toc")
}

if ($Addon) {
    $folders = $folders | Where-Object { $Addon -contains $_.Name }
    $missing = $Addon | Where-Object { $folders.Name -notcontains $_ }
    if ($missing) {
        Write-Error "No such addon: $($missing -join ', ')"
    }
}

if (-not $folders) {
    Write-Error "No addons found. An addon is a folder containing <name>.toc."
}

foreach ($folder in $folders) {
    $name = $folder.Name
    $toc = Join-Path $folder.FullName "$name.toc"
    $tocLines = Get-Content $toc

    $version = ($tocLines | Where-Object { $_ -match "^##\s*Version:\s*(.+)$" } |
        ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)
    if (-not $version) {
        Write-Error "No '## Version:' line in $toc."
    }

    # Everything the TOC loads, plus the TOC itself. Read from the .toc rather
    # than globbed, so anything added there ships and anything missing fails
    # the build instead of shipping broken.
    $required = @("$name.toc")
    foreach ($line in $tocLines) {
        $trimmed = $line.Trim()
        if ($trimmed -and -not $trimmed.StartsWith("#")) {
            $required += ($trimmed -replace "\\", "/")
        }
    }

    $missingFiles = $required | Where-Object { -not (Test-Path (Join-Path $folder.FullName $_)) }
    if ($missingFiles) {
        Write-Error "Listed in $name.toc but missing on disk: $($missingFiles -join ', ')"
    }

    # The readme rides along when there is one, but is not required.
    $files = $required
    if (Test-Path (Join-Path $folder.FullName "README.md")) {
        $files += "README.md"
    }

    # Art rides along too, and cannot come from the .toc: a .toc lists code for
    # the client to load, while a texture is only ever referenced by path. So
    # these are found by looking rather than by being declared, which is the
    # one thing this script otherwise refuses to do.
    Get-ChildItem -Path $folder.FullName -File -Include *.tga, *.blp -Recurse |
        ForEach-Object {
            $files += $_.FullName.Substring($folder.FullName.Length + 1) -replace "\\", "/"
        }

    $staging = Join-Path ([System.IO.Path]::GetTempPath()) ("$name-pkg-" + [guid]::NewGuid().ToString("N"))
    $addonRoot = Join-Path $staging $name

    try {
        foreach ($file in $files) {
            $target = Join-Path $addonRoot $file
            $targetDir = Split-Path $target -Parent
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            Copy-Item (Join-Path $folder.FullName $file) $target
        }

        $dist = Join-Path $PSScriptRoot "dist"
        if (-not (Test-Path $dist)) {
            New-Item -ItemType Directory -Path $dist | Out-Null
        }

        $zip = Join-Path $dist "$name-$version.zip"
        if (Test-Path $zip) {
            Remove-Item $zip -Force
        }

        # The repo's licence travels with every copy, as the MIT terms ask.
        $license = Join-Path $PSScriptRoot "LICENSE"
        if (Test-Path $license) {
            Copy-Item $license (Join-Path $addonRoot "LICENSE")
        }

        # Not Compress-Archive: on Windows PowerShell 5.1 it writes entry names
        # with backslashes, which addon sites and non-Windows unzippers read as
        # one flat file named "Addon\file.lua". Zip entries must use "/".
        $archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            Get-ChildItem -Path $addonRoot -File -Recurse | ForEach-Object {
                $entry = "$name/" + ($_.FullName.Substring($addonRoot.Length + 1) -replace "\\", "/")
                [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    $archive, $_.FullName, $entry, [System.IO.Compression.CompressionLevel]::Optimal)
            }
        }
        finally {
            $archive.Dispose()
        }
        Write-Host "Packaged $($files.Count) files -> $zip"

        if ($Install) {
            $addons = Join-Path $WowPath "Interface\AddOns"
            if (-not (Test-Path $addons)) {
                New-Item -ItemType Directory -Path $addons -Force | Out-Null
            }

            $installed = Join-Path $addons $name
            if (Test-Path $installed) {
                Remove-Item $installed -Recurse -Force
            }

            Copy-Item $addonRoot $addons -Recurse
            Write-Host "Installed -> $installed"

            # A failed upload is reported but leaves the install, and the
            # other addons in this run, alone.
            if (-not $NoWago) {
                try {
                    Publish-Wago $name $version $zip $tocLines $folder
                }
                catch {
                    Write-Warning "Wago: $name not published. $_"
                }
            }
        }
    }
    finally {
        if (Test-Path $staging) {
            Remove-Item $staging -Recurse -Force
        }
    }
}
