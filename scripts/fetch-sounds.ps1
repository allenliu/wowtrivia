#requires -Version 5.1
<#
.SYNOPSIS
  Fetch Wowhead's full sound inventory for an NPC and merge into data/voicelines.json.

.DESCRIPTION
  Hits https://www.wowhead.com/sounds?filter=na=<filter>, extracts the inline JSON
  data array, and adds each matching sound to the `sounds` array in voicelines.json.

  Idempotent: existing sound entries are preserved (status, notes, transcript, etc.).
  Only sounds not already present are added.

.PARAMETER Name
  Display name of the NPC, e.g. "Odyn". Used as the `npc` field on each row.

.PARAMETER Filter
  Wowhead filter string (substring of sound filename). Defaults to lowercased Name.

.EXAMPLE
  ./scripts/fetch-sounds.ps1 -Name Odyn
#>
param(
    [Parameter(Mandatory = $true)] [string] $Name,
    [string] $Filter,
    [string] $DataFile = 'data/voicelines.json'
)

$ErrorActionPreference = 'Stop'

if (-not $Filter) { $Filter = $Name.ToLower() }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$DataPath  = Join-Path $RepoRoot $DataFile

if (-not (Test-Path $DataPath)) { throw "Data file not found: $DataPath" }

$url = "https://www.wowhead.com/sounds?filter=na=$Filter"
Write-Host "Fetching $url ..."
$response = Invoke-WebRequest -Uri $url -UseBasicParsing

# Locate the inline "data":[...] array
$m = [regex]::Match($response.Content, '"data":\s*\[')
if (-not $m.Success) { throw 'Could not find data array in Wowhead response.' }

$start = $m.Index + $m.Length - 1
$depth = 0
$i = $start
while ($i -lt $response.Content.Length) {
    $c = $response.Content[$i]
    if     ($c -eq '[') { $depth++ }
    elseif ($c -eq ']') { $depth--; if ($depth -eq 0) { break } }
    $i++
}
$jsonText = $response.Content.Substring($start, $i - $start + 1)
$fetched  = $jsonText | ConvertFrom-Json

# Detect truncation (Wowhead caps display at 1,000)
$noteMatch = [regex]::Match($response.Content, '"note":"([^"]+)"')
if ($noteMatch.Success -and $noteMatch.Groups[1].Value -match 'displayed') {
    Write-Warning "Wowhead truncated results: $($noteMatch.Groups[1].Value)"
}

Write-Host "Wowhead returned $($fetched.Count) sounds matching filter '$Filter'."

# Defensive: keep only entries whose filename actually contains the Name (case-insensitive by default for -match)
$escapedName = [regex]::Escape($Name)
$relevant = $fetched | Where-Object { $_.name -match $escapedName }
Write-Host "After name-substring filter on '$Name': $($relevant.Count) entries."

# Load existing data
$data = Get-Content $DataPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Build map of existing sound ids
$existing = @{}
if ($data.sounds) {
    foreach ($s in $data.sounds) { $existing[[int]$s.id] = $s }
}

# Walk relevant sounds, add new entries
$soundList = [System.Collections.ArrayList]::new()
if ($data.sounds) { foreach ($s in $data.sounds) { [void]$soundList.Add($s) } }

$added = 0; $skipped = 0; $now = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')

foreach ($f in $relevant) {
    if ($existing.ContainsKey([int]$f.id)) { $skipped++; continue }

    # Patch prefix is the first two underscore-separated tokens (e.g., VO_701, Spell_HelheimRaid)
    $tokens = $f.name -split '_'
    $patchPrefix = if ($tokens.Count -ge 2) { "$($tokens[0])_$($tokens[1])" } else { $tokens[0] }

    $entry = [ordered]@{
        id             = [int]$f.id
        name           = $f.name
        url            = $f.files[0].url
        npc            = $Name
        patchPrefix    = $patchPrefix
        fetchedAt      = $now
        transcript     = $null
        transcribedAt  = $null
        matchedQuoteId = $null
        matchScore     = $null
        status         = 'pending'
        selected       = $false
        notes          = ''
    }
    [void]$soundList.Add([PSCustomObject]$entry)
    $added++
}

$data.sounds = @($soundList)

# Serialize with sufficient depth; ConvertTo-Json escapes non-ASCII to \uXXXX — undo for readability
$json = $data | ConvertTo-Json -Depth 20
$json = [regex]::Replace($json, '\\u(?<n>[0-9a-fA-F]{4})', {
    param($mm) [char]::ConvertFromUtf32([Convert]::ToInt32($mm.Groups['n'].Value, 16))
})

# UTF-8 without BOM, LF line endings
$json = $json -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($DataPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))

Write-Host ("Done. Added {0}, skipped {1} (already present). Total sounds: {2}." -f $added, $skipped, $data.sounds.Count)
