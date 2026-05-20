#requires -Version 5.1
<#
.SYNOPSIS
  Generic Tier-2 builder. Given a config JSON listing a dungeon's bosses + their
  wiki-extracted quote lists, this script:
    1. For each boss: searches Wowhead globally for matching sound files
    2. Downloads .ogg files to audio/cache/
    3. Invokes transcribe.py to Whisper-transcribe them
    4. Levenshtein-matches wiki quote text against transcripts
    5. Merges resulting NPC entries into data/voicelines-<slug>.json
       (preserving any Tier-1 NPC entries already present)

.PARAMETER ConfigFile
  Path to JSON config. Schema:
  {
    "dungeon": "Theater of Pain",
    "slug": "theater-of-pain",
    "wowheadZoneId": 12841,
    "expansion": "Shadowlands",
    "bosses": [
      {
        "id": 162317,
        "name": "Mordretha",
        "filterName": "mordretha",                   // optional, defaults to lowercased name
        "namePattern": "^VO_90.*Mordretha",          // optional, regex
        "quotes": [ { "context": "Intro", "text": "..." } ]
      }
    ]
  }
#>
param(
    [Parameter(Mandatory = $true)] [string] $ConfigFile,
    [string] $DataFile,                              # default: data/voicelines-<slug>.json
    [double] $MatchThreshold = 0.55,
    [int]    $MinBonusChars  = 10,                   # min transcript chars for bonus entry
    [switch] $NoBonus                                # skip bonus transcripts entirely (wiki-matched only)
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

$cfgPath = Join-Path $RepoRoot $ConfigFile
if (-not (Test-Path $cfgPath)) { throw "Config not found: $cfgPath" }
$cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $DataFile) {
    $DataFile = "data/voicelines-$($cfg.slug).json"
}

# --- Fuzzy match helpers ---
function Get-Levenshtein {
    param([string]$a, [string]$b)
    $m = $a.Length; $n = $b.Length
    if ($m -eq 0) { return $n }; if ($n -eq 0) { return $m }
    $prev = New-Object 'int[]' ($n + 1)
    $curr = New-Object 'int[]' ($n + 1)
    for ($j = 0; $j -le $n; $j++) { $prev[$j] = $j }
    for ($i = 1; $i -le $m; $i++) {
        $curr[0] = $i
        for ($j = 1; $j -le $n; $j++) {
            $cost = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
            $a1 = $curr[$j - 1] + 1; $a2 = $prev[$j] + 1; $a3 = $prev[$j - 1] + $cost
            $curr[$j] = [Math]::Min([Math]::Min($a1, $a2), $a3)
        }
        $tmp = $prev; $prev = $curr; $curr = $tmp
    }
    return $prev[$n]
}

function Get-Similarity {
    param([string]$a, [string]$b)
    $na = (($a.ToLower() -replace '[^a-z0-9\s]', ' ' -replace '\s+', ' ').Trim())
    $nb = (($b.ToLower() -replace '[^a-z0-9\s]', ' ' -replace '\s+', ' ').Trim())
    $maxLen = [Math]::Max($na.Length, $nb.Length)
    if ($maxLen -eq 0) { return 0 }
    $dist = Get-Levenshtein $na $nb
    return [math]::Round(1 - ($dist / $maxLen), 3)
}

# --- Per-boss pipeline ---
$resultNpcs  = [System.Collections.ArrayList]::new()
$totalWiki   = 0
$totalBonus  = 0

foreach ($boss in $cfg.bosses) {
    Write-Host ''
    Write-Host ('=' * 60)
    Write-Host "Boss: $($boss.name)  (id=$($boss.id))"
    Write-Host ('=' * 60)

    $filter = if ($boss.filterName) { $boss.filterName } else { $boss.name.ToLower() -replace '[^a-z0-9]+', '_' }
    $pattern = $boss.namePattern
    $manifestFile = "data/sounds-$($cfg.slug)-$($boss.name.ToLower() -replace '[^a-z0-9]+', '-').json"

    # 1. Fetch + download (idempotent thanks to cache).
    # Wrapped in try/catch with EAP='Continue' so a single boss's failure doesn't
    # tank the whole dungeon (e.g., when the Wowhead name-filter returns 0).
    $fetchArgs = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $ScriptDir 'fetch-by-name.ps1'),
        '-FilterName', $filter,
        '-Npc', $boss.name,
        '-Dungeon', $cfg.dungeon,
        '-OutputFile', $manifestFile
    )
    if ($pattern) { $fetchArgs += @('-NamePattern', $pattern) }
    Write-Host "Step 1/3: fetch + download via fetch-by-name.ps1 ..."
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & powershell.exe @fetchArgs 2>&1 | ForEach-Object { Write-Host "  $_" }
    } catch {
        Write-Warning "  Boss skipped (fetch failed): $($_.Exception.Message)"
        $ErrorActionPreference = $prev
        continue
    }
    $ErrorActionPreference = $prev

    $manifestPath = Join-Path $RepoRoot $manifestFile
    if (-not (Test-Path $manifestPath)) {
        Write-Warning "  Manifest not written. Skipping boss."
        continue
    }
    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $manifest.sounds -or $manifest.sounds.Count -eq 0) {
        Write-Host "  No sounds matched filter. Skipping boss."
        continue
    }

    # 2. Transcribe (idempotent: skips entries with non-null transcript).
    # Python (tqdm) writes progress to stderr which trips $ErrorActionPreference='Stop';
    # relax it for this call only.
    Write-Host "Step 2/3: transcribe via transcribe.py ..."
    $env:PATH = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $audioCacheAbs = Join-Path $RepoRoot 'audio/cache'
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & python (Join-Path $ScriptDir 'transcribe.py') (Join-Path $RepoRoot $manifestFile) --model small --cache $audioCacheAbs 2>&1 | Out-Null
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    # Reload manifest after transcribe
    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

    # 3. Match wiki quotes to transcripts
    Write-Host "Step 3/3: match wiki quotes to transcripts ..."
    $quotes  = [System.Collections.ArrayList]::new()
    $usedIds = @{}

    foreach ($wq in $boss.quotes) {
        $best = $null; $bestSim = 0
        foreach ($s in $manifest.sounds) {
            if ($usedIds.ContainsKey($s.soundId)) { continue }
            if (-not $s.transcript) { continue }
            $sim = Get-Similarity $wq.text $s.transcript
            if ($sim -gt $bestSim) { $bestSim = $sim; $best = $s }
        }
        if ($best -and $bestSim -ge $MatchThreshold) {
            $usedIds[$best.soundId] = $true
            [void]$quotes.Add([PSCustomObject]([ordered]@{
                soundId     = $best.soundId
                filename    = $best.filename
                audioUrl    = $best.audioUrl
                text        = $wq.text
                source      = 'wiki'
                wikiContext = $wq.context
                transcript  = $best.transcript
                matchScore  = $bestSim
                status      = 'pending'
                selected    = $false
                notes       = ''
            }))
            $totalWiki++
            Write-Host ("    [wiki {0:F2}]  '{1}'  -> id={2}" -f $bestSim, $wq.text, $best.soundId)
        } else {
            Write-Host ("    [skip]       '{0}'  (best sim {1:F2}, threshold {2:F2})" -f $wq.text, $bestSim, $MatchThreshold)
        }
    }

    # Bonus transcripts (not matched to any wiki quote, long enough to be meaningful)
    if (-not $NoBonus) {
        foreach ($s in $manifest.sounds) {
            if ($usedIds.ContainsKey($s.soundId)) { continue }
            if (-not $s.transcript) { continue }
            $clean = ($s.transcript -replace '[^a-zA-Z]', '')
            if ($clean.Length -lt $MinBonusChars) { continue }
            [void]$quotes.Add([PSCustomObject]([ordered]@{
                soundId     = $s.soundId
                filename    = $s.filename
                audioUrl    = $s.audioUrl
                text        = $s.transcript
                source      = 'transcript'
                wikiContext = $null
                transcript  = $s.transcript
                matchScore  = $null
                status      = 'pending'
                selected    = $false
                notes       = ''
            }))
            $totalBonus++
        }
    }

    if ($quotes.Count -gt 0) {
        [void]$resultNpcs.Add([PSCustomObject]([ordered]@{
            id     = [int]$boss.id
            name   = $boss.name
            elite  = $true
            quotes = @($quotes)
        }))
    }
}

# --- Merge with existing voicelines-<slug>.json ---
$dataPath = Join-Path $RepoRoot $DataFile
$existing = $null
if (Test-Path $dataPath) {
    try { $existing = Get-Content $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
}

$mergedNpcs = [System.Collections.ArrayList]::new()
$tier1Ids   = @{}
if ($existing -and $existing.npcs) {
    foreach ($n in $existing.npcs) {
        # If a Tier-1 entry exists for an NPC we also processed Tier-2 for, keep the Tier-1 quotes
        # and add the Tier-2 quotes alongside (deduped at sound-id level later).
        [void]$mergedNpcs.Add($n)
        $tier1Ids[[int]$n.id] = $true
    }
}
foreach ($nn in $resultNpcs) {
    if ($tier1Ids.ContainsKey([int]$nn.id)) {
        # Tier-2 quotes for an NPC already in Tier-1 — append to that NPC's quotes
        $existingNpc = $mergedNpcs | Where-Object { [int]$_.id -eq [int]$nn.id } | Select-Object -First 1
        $existingNpc.quotes = @($existingNpc.quotes) + @($nn.quotes)
    } else {
        [void]$mergedNpcs.Add($nn)
    }
}

# Dedupe by soundId (in case of overlap)
$seen = @{}
$dedupedNpcs = [System.Collections.ArrayList]::new()
foreach ($n in $mergedNpcs) {
    $kept = [System.Collections.ArrayList]::new()
    foreach ($q in $n.quotes) {
        $sid = [int]$q.soundId
        if (-not $seen.ContainsKey($sid)) {
            $seen[$sid] = $true
            [void]$kept.Add($q)
        }
    }
    if ($kept.Count -gt 0) { $n.quotes = @($kept); [void]$dedupedNpcs.Add($n) }
}

$out = [ordered]@{
    meta = [ordered]@{
        schemaVersion = 3
        dungeon       = $cfg.dungeon
        wowheadZoneId = [int]$cfg.wowheadZoneId
        expansion     = $cfg.expansion
        generated     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
        notes         = 'Mixed Tier-1 (Wowhead Quotes) + Tier-2 (wiki + Whisper) entries.'
    }
    npcs = @($dedupedNpcs)
}

$dataDir = Split-Path -Parent $dataPath
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
$json = $out | ConvertTo-Json -Depth 20
$json = [regex]::Replace($json, '\\u(?<n>[0-9a-fA-F]{4})', { param($mm) [char]::ConvertFromUtf32([Convert]::ToInt32($mm.Groups['n'].Value, 16)) })
$json = $json -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($dataPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host ('=' * 60)
Write-Host ("Tier-2 done. {0} wiki-matched, {1} bonus transcripts across {2} NPC(s)." -f $totalWiki, $totalBonus, $resultNpcs.Count)
Write-Host "Wrote: $DataFile"
