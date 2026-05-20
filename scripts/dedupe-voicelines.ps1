#requires -Version 5.1
<#
.SYNOPSIS
  Dedupe data/voicelines-*.json files by soundId. The same character can
  appear under multiple Wowhead NPC IDs (e.g., Alleria Windrunner has id
  123743 and id 125836 in Seat of the Triumvirate), and both NPC entries
  reference the same sound files. Keep the first occurrence; drop later
  ones. Drop any NPC entry that ends up with 0 quotes.

.PARAMETER File
  Specific file to process. If omitted, processes all data/voicelines-*.json.
#>
param(
    [string] $File
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

$files = if ($File) {
    @(Join-Path $RepoRoot $File)
} else {
    Get-ChildItem (Join-Path $RepoRoot 'data') -Filter 'voicelines-*.json' | ForEach-Object { $_.FullName }
}

$totalChanged = 0; $totalDupes = 0

foreach ($f in $files) {
    if (-not (Test-Path $f)) { Write-Warning "Not found: $f"; continue }
    try {
        $data = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warning ("Could not parse {0}: {1}" -f (Split-Path -Leaf $f), $_.Exception.Message)
        continue
    }
    if (-not $data.npcs) { continue }

    $seen = @{}
    $fileDupes = 0
    $newNpcs = [System.Collections.ArrayList]::new()

    foreach ($npc in $data.npcs) {
        $keptQuotes = [System.Collections.ArrayList]::new()
        foreach ($q in $npc.quotes) {
            $sid = [int]$q.soundId
            if ($seen.ContainsKey($sid)) {
                $fileDupes++
            } else {
                $seen[$sid] = $true
                [void]$keptQuotes.Add($q)
            }
        }
        if ($keptQuotes.Count -gt 0) {
            # Replace the quotes array in-place
            $npc.quotes = @($keptQuotes)
            [void]$newNpcs.Add($npc)
        }
    }

    $droppedNpcs = @($data.npcs).Count - $newNpcs.Count
    if ($fileDupes -gt 0 -or $droppedNpcs -gt 0) {
        $data.npcs = @($newNpcs)
        $json = $data | ConvertTo-Json -Depth 20
        $json = [regex]::Replace($json, '\\u(?<n>[0-9a-fA-F]{4})', {
            param($mm) [char]::ConvertFromUtf32([Convert]::ToInt32($mm.Groups['n'].Value, 16))
        })
        $json = $json -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText($f, $json + "`n", [System.Text.UTF8Encoding]::new($false))
        Write-Host ("  {0,-45}  dropped {1} duplicate(s), {2} empty NPC(s)" -f (Split-Path -Leaf $f), $fileDupes, $droppedNpcs)
        $totalChanged++
        $totalDupes += $fileDupes
    } else {
        Write-Host ("  {0,-45}  clean" -f (Split-Path -Leaf $f))
    }
}

Write-Host ''
Write-Host ("Done. {0} file(s) changed, {1} duplicate quote(s) removed total." -f $totalChanged, $totalDupes)
