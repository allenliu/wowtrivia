#requires -Version 5.1
<#
.SYNOPSIS
  Scrape a Wowhead dungeon zone page -> its elite NPCs with Quotes sections ->
  write all curated (quote text, sound) pairs to data/voicelines.json.

.DESCRIPTION
  Pipeline:
    1. Fetch the zone page; parse the inline NPC Listview.
    2. Filter to classification=1 (elite).
    3. For each elite, fetch the NPC page and check for a "Quotes (N)" section.
    4. For each quote, extract (soundId, filename slug, fileDataId, quote text).
    5. For each quote, fetch the sound page once to grab the canonical zamimg URL.
    6. Merge into voicelines.json, preserving per-quote status/selected/notes.

.PARAMETER ZoneId
  Wowhead zone ID for the dungeon (e.g., 14032 for Algeth'ar Academy).

.PARAMETER Dungeon
  Display name for the dungeon (e.g., "Algeth'ar Academy").

.PARAMETER Expansion
  Optional. Recorded in meta only (e.g., "Dragonflight").

.EXAMPLE
  ./scripts/fetch-dungeon-quotes.ps1 -ZoneId 14032 -Dungeon "Algeth'ar Academy" -Expansion "Dragonflight"
#>
param(
    [Parameter(Mandatory = $true)] [int]    $ZoneId,
    [Parameter(Mandatory = $true)] [string] $Dungeon,
    [string] $Expansion,
    [string] $DataFile = 'data/voicelines.json',
    [int]    $DelayMs  = 800,
    [string] $CacheDir = '.cache/wowhead',
    [switch] $NoCache,
    # Default exclusions: Dragonflight Follower Dungeon AI companions. These appear
    # in every DF dungeon when run as a Follower Dungeon and have curated Quotes,
    # but they aren't part of the dungeon's story.
    [int[]]  $ExcludeNpcIds = @(
        209057,  # Captain Garrick
        209059,  # Meredy Huntswell
        209065,  # Austin Huxworth
        209072,  # Crenna Earth-Daughter
        214390   # Shuja Grimaxe
    )
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# Browser UA + standard headers so CloudFront's WAF doesn't flag us as a bot.
# (Just setting a Chrome UA is NOT enough — the WAF also checks for the headers a real
# browser would send. Without these we get 403 even from clean IPs.)
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

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$DataPath  = Join-Path $RepoRoot $DataFile
$CachePath = Join-Path $RepoRoot $CacheDir

if (-not $NoCache -and -not (Test-Path $CachePath)) {
    New-Item -ItemType Directory -Path $CachePath -Force | Out-Null
}

# Track cache hits/misses for the run summary
$script:CacheHits   = 0
$script:CacheMisses = 0

function Get-BalancedArray {
    param([string]$Text, [int]$OpenBracketIdx)
    $depth = 0; $i = $OpenBracketIdx
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        if     ($c -eq '[') { $depth++ }
        elseif ($c -eq ']') { $depth--; if ($depth -eq 0) { return $Text.Substring($OpenBracketIdx, $i - $OpenBracketIdx + 1) } }
        $i++
    }
    throw 'Unterminated JSON array'
}

# Cache-aware HTTP GET with retry-on-403 (transient WAF throttling).
function Get-WowheadPage {
    param([string]$Url, [string]$CacheKey)
    if (-not $NoCache) {
        $f = Join-Path $CachePath "$CacheKey.html"
        if (Test-Path $f) {
            $script:CacheHits++
            return Get-Content $f -Raw -Encoding UTF8
        }
    }

    # Jittered delay to look less mechanical
    if ($DelayMs -gt 0) {
        $j = Get-Random -Minimum $DelayMs -Maximum ($DelayMs * 2)
        Start-Sleep -Milliseconds $j
    }

    $maxAttempts = 4
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            $r = Invoke-WebRequest -UserAgent $UserAgent -Headers $BrowserHeaders -Uri $Url -UseBasicParsing -ErrorAction Stop
            $script:CacheMisses++
            if (-not $NoCache) {
                [System.IO.File]::WriteAllText((Join-Path $CachePath "$CacheKey.html"), $r.Content, [System.Text.UTF8Encoding]::new($false))
            }
            return $r.Content
        } catch {
            $status = $_.Exception.Response.StatusCode.value__
            if ($status -eq 403 -and $attempt -lt $maxAttempts) {
                # Aggressive backoff: 30s, 60s, 120s. WAF rate-limits are minute-scale.
                $backoff = 30 * [math]::Pow(2, $attempt - 1)
                Write-Host ''  # break the inline NoNewline line cleanly
                Write-Host ("    (403, backing off {0}s, attempt {1}/{2})" -f $backoff, ($attempt + 1), $maxAttempts) -NoNewline
                Start-Sleep -Seconds $backoff
                continue
            }
            throw
        }
    }
}

# --- 1. Fetch zone page, extract NPCs ---
Write-Host "Fetching zone $ZoneId ($Dungeon)$(if($NoCache){' [no cache]'})..."
$zoneHtml = Get-WowheadPage -Url "https://www.wowhead.com/zone=$ZoneId" -CacheKey "zone-$ZoneId"

$tmplIdx = $zoneHtml.IndexOf("template: 'npc'")
if ($tmplIdx -lt 0) { throw 'Zone page has no NPC Listview.' }

$dataIdx = $zoneHtml.IndexOf('data: [', $tmplIdx)
if ($dataIdx -lt 0) { $dataIdx = $zoneHtml.IndexOf('"data":[', $tmplIdx) }
if ($dataIdx -lt 0) { throw 'Could not find data array in NPC Listview.' }

$openBracketIdx = $zoneHtml.IndexOf('[', $dataIdx)
$npcs           = (Get-BalancedArray $zoneHtml $openBracketIdx) | ConvertFrom-Json

# Filter 1: exclude follower NPCs (DF AI companions appearing in every DF dungeon).
# Filter 2: location must include this zone. The zone NPC listview is broader than
# "lives here" — toy summons, world-event overlays, etc. show up. The NPC's own
# location field is the authoritative signal (e.g., Karam Magespear is listed in
# HoA's zone but his location is [7545,8026,0,-1], not 12831).
$candidates = @($npcs |
    Where-Object { [int]$_.id -notin $ExcludeNpcIds } |
    Where-Object {
        # Some entries don't have a location field; keep those (better to over-include than miss bosses).
        if (-not $_.PSObject.Properties['location']) { return $true }
        if (-not $_.location) { return $true }
        return ($_.location -contains $ZoneId)
    } |
    Sort-Object name)
$excludedCount = $npcs.Count - $candidates.Count
Write-Host "  $($npcs.Count) NPCs total; $excludedCount excluded (followers + zone-overlay)."

# --- 2. For each NPC, look for a Quotes section ---
# Note: we don't filter by classification (elite vs normal) because some non-elite
# NPCs (e.g., Davey "Two Eyes" in Freehold) have curated Quotes; the Quotes section
# itself is the quality filter.
$resultNpcs  = [System.Collections.ArrayList]::new()
$totalQuotes = 0
$i = 0
foreach ($n in $candidates) {
    $i++
    Write-Host "  [$i/$($candidates.Count)] $($n.name) (id=$($n.id))" -NoNewline

    try {
        $npcHtml = Get-WowheadPage -Url "https://www.wowhead.com/npc=$($n.id)" -CacheKey "npc-$($n.id)"
    } catch {
        Write-Host "  -- skip ($($_.Exception.Message))"
        continue
    }

    $qm = [regex]::Match($npcHtml, '"heading-size-3"><a[^>]*onclick="return WH\.disclose\(WH\.ge\(''([^'']+)''\), this\)">Quotes \((\d+)\)')
    if (-not $qm.Success) { Write-Host '  -- no Quotes'; continue }

    $divIdx     = $npcHtml.IndexOf("<div id=`"$($qm.Groups[1].Value)`"")
    $endIdx     = $npcHtml.IndexOf('</div></div>', $divIdx)
    $quotesHtml = $npcHtml.Substring($divIdx, $endIdx - $divIdx)

    # Each quote is wrapped in <li>...</li>. Match each separately so the soundId
    # and data-sound-id stay paired together.
    $liMatches = [regex]::Matches($quotesHtml, '<li>(.*?)</li>')
    $quotes    = [System.Collections.ArrayList]::new()
    foreach ($li in $liMatches) {
        $liText = $li.Groups[1].Value
        $am  = [regex]::Match($liText, '<a href="/sound=(\d+)/([a-z0-9\-]+)"><span class="blizzard-ui-text">([^<]+)</span></a>')
        $dsm = [regex]::Match($liText, 'data-sound-id="(\d+)"')
        if (-not $am.Success -or -not $dsm.Success) { continue }

        $soundId    = [int]$am.Groups[1].Value
        $filename   = $am.Groups[2].Value
        $text       = $am.Groups[3].Value
        $fileDataId = [int]$dsm.Groups[1].Value

        # Fetch sound page to extract canonical zamimg URL (avoids guessing filename casing)
        $audioUrl = $null
        try {
            $soundHtml = Get-WowheadPage -Url "https://www.wowhead.com/sound=$soundId" -CacheKey "sound-$soundId"
            $um = [regex]::Match($soundHtml, '(https?:\\?/\\?/wow\.zamimg\.com\\?/sound-ids[^"]*?\.ogg)')
            if ($um.Success) { $audioUrl = $um.Groups[1].Value -replace '\\/', '/' }
        } catch { }

        [void]$quotes.Add([PSCustomObject]([ordered]@{
            soundId    = $soundId
            filename   = $filename
            fileDataId = $fileDataId
            audioUrl   = $audioUrl
            text       = $text
            status     = 'pending'
            selected   = $false
            notes      = ''
        }))
    }

    if ($quotes.Count -gt 0) {
        [void]$resultNpcs.Add([PSCustomObject]([ordered]@{
            id     = [int]$n.id
            name   = $n.name
            elite  = ($n.classification -eq 1)
            quotes = @($quotes)
        }))
        $totalQuotes += $quotes.Count
        Write-Host "  -- $($quotes.Count) quotes"
    } else {
        Write-Host '  -- Quotes section present but no voiced rows (text-only)'
    }
}

# --- Dedupe: the same character can appear under multiple NPC IDs sharing sounds ---
# (e.g., Alleria Windrunner has id 123743 and 125836 in Seat of the Triumvirate;
# both Wowhead entries reference the same sound files). Keep the first occurrence;
# drop empty NPC entries.
$seenSoundIds = @{}
$dedupedNpcs  = [System.Collections.ArrayList]::new()
$dupesDropped = 0
foreach ($n in $resultNpcs) {
    $kept = [System.Collections.ArrayList]::new()
    foreach ($q in $n.quotes) {
        if ($seenSoundIds.ContainsKey([int]$q.soundId)) {
            $dupesDropped++
            continue
        }
        $seenSoundIds[[int]$q.soundId] = $true
        [void]$kept.Add($q)
    }
    if ($kept.Count -gt 0) {
        $n.quotes = @($kept)
        [void]$dedupedNpcs.Add($n)
    }
}
if ($dupesDropped -gt 0) {
    Write-Host ("  Deduped: dropped $dupesDropped duplicate quote(s) across NPC IDs.")
}
$resultNpcs = $dedupedNpcs

# --- 3. Merge with existing file (preserve user-set status/selected/notes) ---
$existing = $null
if (Test-Path $DataPath) {
    try { $existing = Get-Content $DataPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
}
if ($existing -and $existing.meta -and $existing.meta.dungeon -eq $Dungeon) {
    $map = @{}
    foreach ($en in $existing.npcs) { foreach ($eq in $en.quotes) { $map[[int]$eq.soundId] = $eq } }
    $preserved = 0
    foreach ($nn in $resultNpcs) {
        foreach ($nq in $nn.quotes) {
            if ($map.ContainsKey([int]$nq.soundId)) {
                $eq = $map[[int]$nq.soundId]
                $nq.status   = $eq.status
                $nq.selected = $eq.selected
                $nq.notes    = $eq.notes
                $preserved++
            }
        }
    }
    if ($preserved -gt 0) { Write-Host "  Preserved status/selected/notes on $preserved existing quote(s)." }
}

# --- 4. Build and write the output ---
$now = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
$output = [ordered]@{
    meta = [ordered]@{
        schemaVersion = 2
        dungeon       = $Dungeon
        wowheadZoneId = $ZoneId
        expansion     = $Expansion
        generated     = $now
    }
    npcs = @($resultNpcs)
}

$dataDir = Split-Path -Parent $DataPath
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }

$json = $output | ConvertTo-Json -Depth 20
$json = [regex]::Replace($json, '\\u(?<n>[0-9a-fA-F]{4})', {
    param($mm) [char]::ConvertFromUtf32([Convert]::ToInt32($mm.Groups['n'].Value, 16))
})
$json = $json -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($DataPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host ("Done. $totalQuotes quotes across $($resultNpcs.Count) NPC(s) wrote to $DataFile  (cache: {0} hits, {1} misses)" -f $script:CacheHits, $script:CacheMisses)
