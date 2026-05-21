#requires -Version 5.1
<#
.SYNOPSIS
  Aggregate all data/voicelines-*.json into a single data/game-pool.json that
  index.html loads at runtime.

.DESCRIPTION
  Pool inclusion rule (default):
    - status == 'accepted'  (only quotes the curator has accepted)
    - source filter does not apply — if the curator accepted a transcript-only
      entry, it counts.

  Each output quote carries a `selected` flag (curator's "★ picked" flag from
  curate.html). The game uses this to guarantee certain quotes always appear.

  Each output quote also carries an `idx` field — a stable, append-only integer
  index assigned the first time the quote enters the pool. The registry lives
  in data/pool-index.json and is used to encode compact share URLs (?r=...).
  Once assigned, an index is never re-used even if the quote is later rejected.

  Output schema (game-pool.json):
    {
      "generated": "2026-05-19T...",
      "count": 137,
      "quotes": [
        { "soundId": 156541, "idx": 0, "text": "...", "audioUrl": "...",
          "filename": "...", "npc": "Lord Chamberlain",
          "dungeon": "Halls of Atonement", "expansion": "Shadowlands",
          "source": "wiki", "selected": true },
        ...
      ]
    }

.PARAMETER IncludePending
  Also include status='pending' / unset quotes. Useful for previewing the pool
  before curation is complete.

.PARAMETER OutputFile
  Default: data/game-pool.json
#>
param(
    [switch] $IncludePending,
    [string] $OutputFile = 'data/game-pool.json'
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

# --- Load (or initialize) the stable pool-index registry ----------------------
# Append-only: every soundId that ever enters the pool gets a permanent idx.
# Indices are not re-used or shifted when quotes are rejected later, so old
# share URLs (?r=...) remain valid forever.
$indexPath = Join-Path $RepoRoot 'data/pool-index.json'
if (Test-Path $indexPath) {
    $idxData = Get-Content $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $idxNext = [int]$idxData.next
    $idxMap  = @{}
    foreach ($prop in $idxData.ids.PSObject.Properties) {
        $idxMap[$prop.Name] = [int]$prop.Value
    }
} else {
    $idxNext = 0
    $idxMap  = @{}
}
$newIndices = 0

$out = [System.Collections.ArrayList]::new()
$counts = @{ wowhead = 0; wiki = 0; transcript = 0 }
$selectedCount = 0
$dungeonCounts = @{}

foreach ($file in Get-ChildItem (Join-Path $RepoRoot 'data') -Filter 'voicelines-*.json') {
    $data = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $dungeon  = $data.meta.dungeon
    $expansion = $data.meta.expansion
    foreach ($npc in $data.npcs) {
        foreach ($q in $npc.quotes) {
            $isAccepted = ($q.status -eq 'accepted')
            $isPending  = (-not $q.status) -or ($q.status -eq 'pending')
            if (-not $isAccepted -and -not ($IncludePending -and $isPending)) { continue }
            if (-not $q.audioUrl) { continue }
            $src = if ($q.source) { $q.source } else { 'wowhead' }

            $isSelected = [bool]$q.selected
            $sidKey = [string][int]$q.soundId
            if (-not $idxMap.ContainsKey($sidKey)) {
                $idxMap[$sidKey] = $idxNext
                $idxNext++
                $newIndices++
            }
            $idx = $idxMap[$sidKey]
            [void]$out.Add([PSCustomObject]([ordered]@{
                soundId   = [int]$q.soundId
                idx       = $idx
                text      = $q.text
                audioUrl  = $q.audioUrl
                filename  = $q.filename
                npc       = $npc.name
                dungeon   = $dungeon
                expansion = $expansion
                source    = $src
                selected  = $isSelected
            }))
            $counts[$src]++
            if ($isSelected) { $selectedCount++ }
            $dungeonCounts[$dungeon] = ($dungeonCounts[$dungeon] | ForEach-Object { $_ + 1 }) ; if (-not $dungeonCounts[$dungeon]) { $dungeonCounts[$dungeon] = 1 }
        }
    }
}

$result = [ordered]@{
    generated = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    count     = $out.Count
    selected  = $selectedCount
    filter    = if ($IncludePending) { 'accepted-plus-pending' } else { 'accepted-only' }
    quotes    = @($out)
}

$json = $result | ConvertTo-Json -Depth 12
$json = [regex]::Replace($json, '\\u(?<n>[0-9a-fA-F]{4})', { param($mm) [char]::ConvertFromUtf32([Convert]::ToInt32($mm.Groups['n'].Value, 16)) })
$json = $json -replace "`r`n", "`n"

$outPath = Join-Path $RepoRoot $OutputFile
[System.IO.File]::WriteAllText($outPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))

# --- Persist the index registry (sorted, deterministic) ---------------------
$sortedIds = [ordered]@{}
foreach ($key in ($idxMap.Keys | Sort-Object { [int]$_ })) {
    $sortedIds[$key] = $idxMap[$key]
}
$idxOut = [ordered]@{
    next = $idxNext
    ids  = $sortedIds
}
$idxJson = $idxOut | ConvertTo-Json -Depth 4
$idxJson = $idxJson -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($indexPath, $idxJson + "`n", [System.Text.UTF8Encoding]::new($false))

Write-Host ("Wrote {0} quotes to {1}" -f $out.Count, $OutputFile)
Write-Host ("  Selected (always-in): {0}" -f $selectedCount)
Write-Host ("  Indices assigned this run: {0}  (total registry: {1})" -f $newIndices, $idxMap.Count)
Write-Host ("  Wowhead Quotes: {0}" -f $counts.wowhead)
Write-Host ("  Wiki Match:     {0}" -f $counts.wiki)
Write-Host ("  Sound Search:   {0}" -f $counts.transcript)
Write-Host ("  Unique dungeons: {0}" -f ($out | Select-Object -ExpandProperty dungeon -Unique).Count)
Write-Host ("  Unique NPCs:     {0}" -f ($out | Select-Object -ExpandProperty npc -Unique).Count)
