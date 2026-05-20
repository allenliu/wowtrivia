#requires -Version 5.1
<#
.SYNOPSIS
  Given a Wowhead sound URL/ID, identify which dungeon (if any) it belongs to
  by extracting the NPC name from the filename and cross-referencing every
  cached zone NPC list in .cache/wowhead/zone-*.html.

.DESCRIPTION
  Wowhead sound pages don't backlink to their NPC. But filenames like
  "VO_91_Corsair_Cannoneer_05_M" embed the NPC name. This script parses the
  filename, searches every cached zone for an NPC with that name, and reports
  matches. Useful for figuring out which dungeon a stray sound URL belongs to.

.PARAMETER Input
  Sound URL (https://www.wowhead.com/sound=123/...), sound ID, or filename slug.

.EXAMPLE
  ./scripts/find-sound-dungeon.ps1 'https://www.wowhead.com/sound=179798/vo-91-corsair-cannoneer-05-m'
  ./scripts/find-sound-dungeon.ps1 179798
  ./scripts/find-sound-dungeon.ps1 'vo-91-corsair-cannoneer-05-m'
#>
param([Parameter(Mandatory = $true)] [string] $InputValue)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$CacheDir  = Join-Path $RepoRoot '.cache/wowhead'

$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
$Headers = @{
    'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8'
    'Accept-Language' = 'en-US,en;q=0.9'; 'Accept-Encoding' = 'gzip, deflate, br'
    'Sec-Fetch-Site' = 'none'; 'Sec-Fetch-Mode' = 'navigate'; 'Sec-Fetch-User' = '?1'; 'Sec-Fetch-Dest' = 'document'
    'Sec-Ch-Ua' = '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"'
    'Sec-Ch-Ua-Mobile' = '?0'; 'Sec-Ch-Ua-Platform' = '"Windows"'; 'Upgrade-Insecure-Requests' = '1'
}

# --- Step 1: Get the filename slug ---
$slug = $null
if ($InputValue -match '^\d+$') {
    # bare sound ID — fetch the page to get the filename
    Write-Host "Fetching sound page for id=$InputValue..."
    $cachePath = Join-Path $CacheDir "sound-$InputValue.html"
    if (Test-Path $cachePath) {
        $html = Get-Content $cachePath -Raw -Encoding UTF8
    } else {
        $html = (Invoke-WebRequest -Uri "https://www.wowhead.com/sound=$InputValue" -UserAgent $UserAgent -Headers $Headers -UseBasicParsing).Content
    }
    $m = [regex]::Match($html, '<title>([^<]+)</title>')
    if ($m.Success) {
        # Title is usually "VO_NN_Name_NN_M - Sound - World of Warcraft"
        $t = $m.Groups[1].Value
        $sm = [regex]::Match($t, '^([A-Za-z0-9_]+)')
        if ($sm.Success) { $slug = $sm.Groups[1].Value }
    }
    if (-not $slug) {
        $um = [regex]::Match($html, '"og:url"\s+content="[^"]+/sound=\d+/([a-z0-9\-]+)"')
        if ($um.Success) { $slug = $um.Groups[1].Value }
    }
} elseif ($InputValue -match '/sound=\d+/([a-z0-9\-_]+)') {
    $slug = $hits[1]
} else {
    $slug = $InputValue
}

if (-not $slug) { throw "Could not extract filename from input: $InputValue" }
Write-Host "Filename: $slug"

# --- Step 2: Parse NPC name from filename ---
# Filenames are typically VO_<patch>_<NpcName>_<num>_<gender>
# or VO_<patch>_<NpcName>_<activity>_<num>
# Strip the VO_<patch>_ prefix and trailing _NN_M / _Activity_NN
$name = $slug -replace '^vo[-_]\d+[-_]', '' -replace '^VO[-_]\d+[-_]', ''
# Drop trailing _NN_M / _NN_F / _NN_M_<suffix>
$name = $name -replace '[-_]\d+[-_][mfMF]$', ''
$name = $name -replace '[-_](Attack|Wound|Death|Aggro|Greeting|Farewell|Angry|Fidget|Injury|Critical|Alert|BattleShout|AttackCrit|WoundCrit|PreAggro)([-_]\d+.*)?$', ''
# Underscore form for regex matching against NPC names
$nameWordsRegex = ($name -replace '[-_]', ' ').Trim() -replace '\s+', ' '
Write-Host "Parsed NPC name: '$nameWordsRegex'"

if (-not $nameWordsRegex) { throw "Could not parse NPC name from filename '$slug'" }

# --- Step 3: Search every cached zone for an NPC with this name ---
$hits = [System.Collections.ArrayList]::new()
$catalog = Get-Content (Join-Path $RepoRoot 'data/dungeons.json') -Raw -Encoding UTF8 | ConvertFrom-Json

foreach ($d in $catalog.dungeons) {
    $cache = Join-Path $CacheDir "zone-$($d.zoneId).html"
    if (-not (Test-Path $cache)) { continue }
    $html = Get-Content $cache -Raw -Encoding UTF8
    $idx = $html.IndexOf("template: 'npc'")
    if ($idx -lt 0) { continue }
    $b = $html.IndexOf('[', $html.IndexOf('data: [', $idx))
    if ($b -lt 0) { continue }
    $depth = 0; $i = $b
    while ($i -lt $html.Length) { $c = $html[$i]; if ($c -eq '[') {$depth++} elseif ($c -eq ']') {$depth--; if ($depth -eq 0) {break}}; $i++ }
    try { $arr = $html.Substring($b, $i - $b + 1) | ConvertFrom-Json } catch { continue }
    foreach ($npc in $arr) {
        if ($npc.name -match [regex]::Escape($nameWordsRegex)) {
            [void]$hits.Add([PSCustomObject]@{ Dungeon = $d.name; Slug = $d.slug; ZoneId = $d.zoneId; NpcId = $npc.id; NpcName = $npc.name; Classification = $npc.classification })
        }
    }
}

Write-Host ''
if ($hits.Count -eq 0) {
    Write-Host "No matching NPC found in any cached zone." -ForegroundColor Yellow
    Write-Host "(Either the NPC isn't in a cached zone, or the name parsing failed.)"
} else {
    Write-Host "Found $($hits.Count) match(es):" -ForegroundColor Green
    $hits | Sort-Object Dungeon | Format-Table -AutoSize
}
