#requires -Version 5.1
<#
.SYNOPSIS
  Run fetch-dungeon-quotes.ps1 against every dungeon in data/dungeons.json.
  Writes data/voicelines-<slug>.json per dungeon. Skips Halls of Atonement
  (already has Tier-2 data).

.PARAMETER Skip
  Slugs to skip (in addition to the always-skipped HoA).

.PARAMETER Only
  Slugs to run (others ignored). Empty = run all.
#>
param(
    [string[]] $Skip = @(),
    [string[]] $Only = @(),
    [int]      $InterDungeonDelaySec = 30,
    [switch]   $RedoCompleted
)

$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$catalog   = Get-Content (Join-Path $RepoRoot 'data/dungeons.json') -Raw -Encoding UTF8 | ConvertFrom-Json

$alwaysSkip = @('halls-of-atonement')  # has Tier-2 data we want to preserve
$dungeons = $catalog.dungeons | Where-Object { $_.slug -notin $alwaysSkip -and $_.slug -notin $Skip }
if ($Only.Count -gt 0) { $dungeons = $dungeons | Where-Object { $_.slug -in $Only } }

$total = @($dungeons).Count
$results = [System.Collections.ArrayList]::new()
$start = Get-Date
$idx = 0

foreach ($d in $dungeons) {
    $idx++
    $outFile = "data/voicelines-$($d.slug).json"
    $outPath = Join-Path $RepoRoot $outFile

    # Skip dungeons that already have output (unless -RedoCompleted)
    if ((Test-Path $outPath) -and -not $RedoCompleted) {
        try {
            $data = Get-Content $outPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $existingQuotes = ($data.npcs | ForEach-Object { $_.quotes.Count } | Measure-Object -Sum).Sum
            if (-not $existingQuotes) { $existingQuotes = 0 }
            Write-Host ("[{0}/{1}] SKIP {2} (already done: {3} quotes)" -f $idx, $total, $d.name, $existingQuotes)
            [void]$results.Add([PSCustomObject]@{
                Name = $d.name; Expansion = $d.expansion; Slug = $d.slug
                NPCs = @($data.npcs).Count; Quotes = $existingQuotes
                Seconds = 0; Status = 'SKIP (existed)'
            })
            continue
        } catch { Write-Warning "  Existing file unreadable, will re-run: $($_.Exception.Message)" }
    }

    # Inter-dungeon pause to let the WAF rate window decay
    if ($idx -gt 1 -and $InterDungeonDelaySec -gt 0) {
        Write-Host ("    (pausing {0}s before next dungeon)" -f $InterDungeonDelaySec)
        Start-Sleep -Seconds $InterDungeonDelaySec
    }

    Write-Host ''
    Write-Host ('=' * 60)
    Write-Host ("[{0}/{1}] {2} ({3})  zone={4}  -> {5}" -f $idx, $total, $d.name, $d.expansion, $d.zoneId, $outFile)
    Write-Host ('=' * 60)

    $tStart = Get-Date
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'fetch-dungeon-quotes.ps1') `
            -ZoneId $d.zoneId -Dungeon $d.name -Expansion $d.expansion -DataFile $outFile 2>&1 |
            ForEach-Object { Write-Host "  $_" }
        $elapsed = ((Get-Date) - $tStart).TotalSeconds

        # Read result to count quotes
        $fp = Join-Path $RepoRoot $outFile
        $quotes = 0; $npcs = 0
        if (Test-Path $fp) {
            try {
                $data = Get-Content $fp -Raw -Encoding UTF8 | ConvertFrom-Json
                $npcs = @($data.npcs).Count
                $quotes = ($data.npcs | ForEach-Object { $_.quotes.Count } | Measure-Object -Sum).Sum
                if (-not $quotes) { $quotes = 0 }
            } catch { }
        }
        [void]$results.Add([PSCustomObject]@{
            Name      = $d.name
            Expansion = $d.expansion
            Slug      = $d.slug
            NPCs      = $npcs
            Quotes    = $quotes
            Seconds   = [math]::Round($elapsed, 1)
            Status    = 'OK'
        })
    } catch {
        Write-Warning "  ERROR: $($_.Exception.Message)"
        [void]$results.Add([PSCustomObject]@{
            Name      = $d.name
            Expansion = $d.expansion
            Slug      = $d.slug
            NPCs      = 0
            Quotes    = 0
            Seconds   = [math]::Round(((Get-Date) - $tStart).TotalSeconds, 1)
            Status    = 'ERROR'
        })
    }
}

$totalElapsed = ((Get-Date) - $start).TotalSeconds
Write-Host ''
Write-Host ('=' * 60)
Write-Host ("ALL DONE in {0:N0}s ({1:N1} min)" -f $totalElapsed, ($totalElapsed/60))
Write-Host ('=' * 60)
$results | Format-Table -AutoSize

# Summary stats
$totalQuotes = ($results | Measure-Object Quotes -Sum).Sum
$totalNpcs   = ($results | Measure-Object NPCs -Sum).Sum
$thinDungeons = @($results | Where-Object { $_.Quotes -lt 5 })
Write-Host ("Total: {0} dungeons, {1} NPCs, {2} quotes" -f $total, $totalNpcs, $totalQuotes)
Write-Host ("Sparse (<5 quotes): {0} dungeons" -f $thinDungeons.Count)
if ($thinDungeons.Count -gt 0) {
    Write-Host "Candidates for Tier-2 backfill:"
    $thinDungeons | ForEach-Object { Write-Host "  - $($_.Name) ($($_.Quotes) quotes)" }
}
