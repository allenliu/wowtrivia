#requires -Version 5.1
<#
.SYNOPSIS
  Build data/voicelines-halls-of-atonement.json from Tier-2 NPC manifests
  (sounds-*.json files with transcripts) + hardcoded wiki quote lists.

  This is the "merge step" of the Tier-2 pipeline: it matches wiki quote
  text against Whisper transcripts using Levenshtein similarity, then emits
  the canonical voicelines schema that curate.html consumes.

  Currently scoped to HoA with hand-curated wiki quotes for Lord Chamberlain
  and Echelon. Will generalize once the pattern is proven.
#>
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

# --- Wiki quote lists (from warcraft.wiki.gg, extracted via WebFetch earlier) ---
$wikiQuotesLordChamberlain = @(
    @{ context = 'Intro';               text = 'I tire of your boorish presence. It seems I must deal with you myself.' }
    @{ context = 'Aggro';               text = 'Begone, rabble!' }
    @{ context = 'Telekinetic Toss';    text = 'I am losing my patience!' }
    @{ context = 'Stigma of Pride';     text = 'Feel the weight of your sins.' }
    @{ context = 'Unleashed Suffering'; text = 'You are no match for my power!' }
    @{ context = 'Ritual of Woe';       text = 'The anima overflows!' }
    @{ context = 'Ritual of Woe';       text = 'I have anima to spare!' }
    @{ context = 'Death';               text = 'Worthless... servants...' }
)

$wikiQuotesEchelon = @(
    @{ context = 'Greeting';              text = 'You are late!' }
    @{ context = 'Greeting';              text = 'Humph, you are the Maw Walker?' }
    @{ context = 'Greeting';              text = 'Pay attention, I will not repeat myself!' }
    @{ context = 'Farewell';              text = 'Move out.' }
    @{ context = 'Farewell';              text = 'Out of my way.' }
    @{ context = 'Farewell';              text = 'Finally.' }
    @{ context = 'Aggro';                 text = 'Begone, rebel filth!' }
    @{ context = 'Blood Torrent';         text = 'Blood take you!' }
    @{ context = 'Stone Call';            text = 'Slay the trespassers!' }
    @{ context = 'Curse of Stone';        text = 'Be still, mortal!' }
    @{ context = 'Stone Shattering Leap'; text = 'Dust to dust!' }
    @{ context = 'Death';                 text = 'This... cannot... be...' }
)

# --- Fuzzy match helpers ---

function Get-Levenshtein {
    param([string]$a, [string]$b)
    $m = $a.Length; $n = $b.Length
    if ($m -eq 0) { return $n }
    if ($n -eq 0) { return $m }

    # Rolling-row implementation. PS5.1's parser doesn't like 2D array indexing
    # like $d[$i,$j], so use two 1D arrays we swap each row.
    $prev = New-Object 'int[]' ($n + 1)
    $curr = New-Object 'int[]' ($n + 1)
    for ($j = 0; $j -le $n; $j++) { $prev[$j] = $j }

    for ($i = 1; $i -le $m; $i++) {
        $curr[0] = $i
        for ($j = 1; $j -le $n; $j++) {
            $cost = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
            $a1 = $curr[$j - 1] + 1
            $a2 = $prev[$j] + 1
            $a3 = $prev[$j - 1] + $cost
            $curr[$j] = [Math]::Min([Math]::Min($a1, $a2), $a3)
        }
        $tmp = $prev; $prev = $curr; $curr = $tmp
    }
    return $prev[$n]
}

function Normalize-Text {
    param([string]$s)
    return (($s.ToLower() -replace '[^a-z0-9\s]', ' ' -replace '\s+', ' ').Trim())
}

function Get-Similarity {
    param([string]$a, [string]$b)
    $na = Normalize-Text $a
    $nb = Normalize-Text $b
    $maxLen = [Math]::Max($na.Length, $nb.Length)
    if ($maxLen -eq 0) { return 0 }
    $dist = Get-Levenshtein $na $nb
    return [math]::Round(1 - ($dist / $maxLen), 3)
}

# --- Build one NPC entry from a manifest + wiki quotes ---

function Build-NpcEntry {
    param(
        [int]    $NpcId,
        [string] $NpcName,
        [string] $ManifestFile,
        [array]  $WikiQuotes,
        [double] $MatchThreshold = 0.55,
        [int]    $MinBonusChars  = 10
    )
    $path = Join-Path $RepoRoot $ManifestFile
    $manifest = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

    $quotes  = [System.Collections.ArrayList]::new()
    $usedIds = @{}

    # Pass 1: wiki quotes → best transcript match
    foreach ($wq in $WikiQuotes) {
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
            Write-Host ("    [wiki match {0:F2}]  '{1}'  -> id={2}" -f $bestSim, $wq.text, $best.soundId)
        } else {
            Write-Host ("    [no match]      '{0}'  (best={1:F2})" -f $wq.text, $bestSim)
        }
    }

    # Pass 2: bonus transcripts (not matched to any wiki quote)
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
    }

    return [PSCustomObject]([ordered]@{
        id     = $NpcId
        name   = $NpcName
        elite  = $true
        quotes = @($quotes)
    })
}

# --- Build the dungeon file ---

Write-Host '=== Lord Chamberlain ==='
$lc = Build-NpcEntry -NpcId 164218 -NpcName 'Lord Chamberlain' -ManifestFile 'data/sounds-lord-chamberlain.json' -WikiQuotes $wikiQuotesLordChamberlain
$wikiLC = ($lc.quotes | Where-Object { $_.source -eq 'wiki' }).Count
$bonusLC = ($lc.quotes | Where-Object { $_.source -eq 'transcript' }).Count
Write-Host "  -> $wikiLC wiki-matched, $bonusLC bonus transcripts"

Write-Host ''
Write-Host '=== Echelon ==='
$ec = Build-NpcEntry -NpcId 164185 -NpcName 'Echelon' -ManifestFile 'data/sounds-echelon.json' -WikiQuotes $wikiQuotesEchelon
$wikiEC = ($ec.quotes | Where-Object { $_.source -eq 'wiki' }).Count
$bonusEC = ($ec.quotes | Where-Object { $_.source -eq 'transcript' }).Count
Write-Host "  -> $wikiEC wiki-matched, $bonusEC bonus transcripts"

# Output
$output = [ordered]@{
    meta = [ordered]@{
        schemaVersion = 3
        dungeon       = 'Halls of Atonement'
        wowheadZoneId = 12831
        expansion     = 'Shadowlands'
        generated     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
        notes         = 'Tier-2 build: wiki quotes (Lord Chamberlain, Echelon) + bonus Whisper transcripts.'
    }
    npcs = @($lc, $ec)
}

$outFile = Join-Path $RepoRoot 'data/voicelines-halls-of-atonement.json'
$json = $output | ConvertTo-Json -Depth 20
$json = [regex]::Replace($json, '\\u(?<n>[0-9a-fA-F]{4})', {
    param($mm) [char]::ConvertFromUtf32([Convert]::ToInt32($mm.Groups['n'].Value, 16))
})
$json = $json -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($outFile, $json + "`n", [System.Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host "Wrote $outFile"
$total = ($lc.quotes.Count + $ec.quotes.Count)
$totalWiki = $wikiLC + $wikiEC
Write-Host "Totals: 2 NPCs, $total quotes ($totalWiki wiki-matched, $($total - $totalWiki) bonus transcripts)"
