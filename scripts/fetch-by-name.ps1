#requires -Version 5.1
<#
.SYNOPSIS
  Tier-2 fetcher: pulls all Wowhead sounds matching a filename substring (typically an
  NPC's name), downloads the .ogg files locally, and writes a manifest JSON.

.DESCRIPTION
  Used when an NPC has no curated Wowhead Quotes section but their voicelines
  exist in Wowhead's broader sound database. The match step (separate) pairs
  these transcripts against known quote text (from wiki or manual entry).

  Same browser-headers + cache + delay pattern as fetch-dungeon-quotes.ps1.

.PARAMETER FilterName
  Substring to filter on (case-insensitive). For Lord Chamberlain, use 'lord_chamberlain'
  (matches VO_901_Lord_Chamberlain_NN_M). The underscore-separated form matches
  more precisely than just 'chamberlain'.

.PARAMETER Npc
  Display name for the NPC (recorded in the manifest).

.PARAMETER Dungeon
  Optional. Recorded in the manifest.

.PARAMETER OutputFile
  Where to write the manifest JSON. Default: data/sounds-<lowercased filter>.json

.PARAMETER NamePattern
  Optional regex. Sounds whose `name` field doesn't match this are skipped.
  Useful to limit to a specific patch's voicelines (e.g., '^VO_901_Lord_Chamberlain_').

.EXAMPLE
  ./scripts/fetch-by-name.ps1 -FilterName 'lord_chamberlain' -Npc 'Lord Chamberlain' -Dungeon 'Halls of Atonement' -NamePattern '^VO_901_Lord_Chamberlain_'
#>
param(
    [Parameter(Mandatory = $true)] [string] $FilterName,
    [Parameter(Mandatory = $true)] [string] $Npc,
    [string] $Dungeon,
    [string] $OutputFile,
    [string] $NamePattern,
    [string] $AudioCacheDir = 'audio/cache',
    [int]    $DelayMs       = 250
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
$BrowserHeaders = @{
    'Accept'                    = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8'
    'Accept-Language'           = 'en-US,en;q=0.9'
    'Accept-Encoding'           = 'gzip, deflate, br'
    'Sec-Fetch-Site'            = 'none'
    'Sec-Fetch-Mode'            = 'navigate'
    'Sec-Fetch-User'            = '?1'
    'Sec-Fetch-Dest'            = 'document'
    'Sec-Ch-Ua'                 = '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"'
    'Sec-Ch-Ua-Mobile'          = '?0'
    'Sec-Ch-Ua-Platform'        = '"Windows"'
    'Upgrade-Insecure-Requests' = '1'
}

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot    = Split-Path -Parent $ScriptDir
$AudioPath   = Join-Path $RepoRoot $AudioCacheDir
if (-not $OutputFile) {
    $slug = ($FilterName -replace '[^a-z0-9]+', '-' -replace '^-|-$', '').ToLower()
    $OutputFile = "data/sounds-$slug.json"
}
$OutputPath  = Join-Path $RepoRoot $OutputFile

if (-not (Test-Path $AudioPath)) { New-Item -ItemType Directory -Path $AudioPath -Force | Out-Null }

# --- Fetch search results ---
$searchUrl = "https://www.wowhead.com/sounds?filter=na=$FilterName"
Write-Host "Fetching $searchUrl ..."
$r = Invoke-WebRequest -UserAgent $UserAgent -Headers $BrowserHeaders -Uri $searchUrl -UseBasicParsing
$m = [regex]::Match($r.Content, '"data":\s*\[')
if (-not $m.Success) { throw 'No data array in response.' }
$start = $m.Index + $m.Length - 1
$depth = 0; $i = $start
while ($i -lt $r.Content.Length) { $c = $r.Content[$i]; if ($c -eq '[') { $depth++ } elseif ($c -eq ']') { $depth--; if ($depth -eq 0) { break } }; $i++ }
$arr = $r.Content.Substring($start, $i - $start + 1) | ConvertFrom-Json
Write-Host "  Got $($arr.Count) sounds."

# Filter by NamePattern if given
if ($NamePattern) {
    $before = $arr.Count
    $arr = @($arr | Where-Object { $_.name -match $NamePattern })
    Write-Host "  After NamePattern '$NamePattern': $($arr.Count) of $before."
}

# --- Download each .ogg to cache + build manifest entries ---
$manifest = [System.Collections.ArrayList]::new()
$downloaded = 0; $skipped = 0; $failed = 0; $idx = 0
foreach ($s in $arr) {
    $idx++
    $url = $s.files[0].url
    if (-not $url) { $failed++; continue }
    $outPath = Join-Path $AudioPath "$($s.id).ogg"

    if (Test-Path $outPath) {
        $skipped++
    } else {
        if ($DelayMs -gt 0) { Start-Sleep -Milliseconds (Get-Random -Minimum $DelayMs -Maximum ($DelayMs * 2)) }
        try {
            Invoke-WebRequest -Uri $url -OutFile $outPath -UseBasicParsing -ErrorAction Stop
            $downloaded++
        } catch {
            Write-Warning "  Failed id=$($s.id): $($_.Exception.Message)"
            if (Test-Path $outPath) { Remove-Item $outPath -Force }
            $failed++
            continue
        }
    }

    [void]$manifest.Add([PSCustomObject]([ordered]@{
        soundId    = [int]$s.id
        filename   = $s.name
        audioUrl   = $url
        npc        = $Npc
        dungeon    = $Dungeon
        transcript = $null
    }))

    if (($downloaded + $skipped) % 25 -eq 0) {
        Write-Host "  Progress: $($downloaded + $skipped) / $($arr.Count)"
    }
}

# --- Write manifest ---
$dataDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
$out = [ordered]@{
    meta = [ordered]@{
        npc          = $Npc
        dungeon      = $Dungeon
        filterName   = $FilterName
        namePattern  = $NamePattern
        generated    = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
        soundCount   = $manifest.Count
    }
    sounds = @($manifest)
}
$json = $out | ConvertTo-Json -Depth 12
$json = [regex]::Replace($json, '\\u(?<n>[0-9a-fA-F]{4})', {
    param($mm) [char]::ConvertFromUtf32([Convert]::ToInt32($mm.Groups['n'].Value, 16))
})
$json = $json -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($OutputPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host ("Done. Downloaded {0}, skipped {1} (cached), failed {2}." -f $downloaded, $skipped, $failed)
Write-Host "Manifest: $OutputFile  ($($manifest.Count) sounds)"
