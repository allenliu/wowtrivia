#requires -Version 5.1
<#
.SYNOPSIS
  Build data/dungeons.json by resolving each dungeon's Wowhead zone ID via the
  slug-redirect trick: hit https://www.wowhead.com/<slug>, follow redirect, capture
  the canonical /zone=NNN/<slug> URL.

  Tries multiple slug variants per dungeon to handle apostrophes/colons/etc.
#>
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

# Hardcoded catalog. zoneId filled by this script.
$dungeons = @(
    # Wrath of the Lich King (still rotated in M+ pools occasionally)
    @{ name = "Pit of Saron";                            expansion = "Wrath of the Lich King"; slug = "pit-of-saron" }

    # Cataclysm
    @{ name = "Throne of the Tides";                     expansion = "Cataclysm"; slug = "throne-of-the-tides" }
    @{ name = "Grim Batol";                              expansion = "Cataclysm"; slug = "grim-batol" }
    @{ name = "Vortex Pinnacle";                         expansion = "Cataclysm"; slug = "vortex-pinnacle" }

    # Warlords of Draenor
    @{ name = "Grimrail Depot";                          expansion = "Warlords of Draenor"; slug = "grimrail-depot" }
    @{ name = "Iron Docks";                              expansion = "Warlords of Draenor"; slug = "iron-docks" }
    @{ name = "Skyreach";                                expansion = "Warlords of Draenor"; slug = "skyreach" }
    @{ name = "The Everbloom";                           expansion = "Warlords of Draenor"; slug = "the-everbloom" }

    # Legion
    @{ name = "Black Rook Hold";                         expansion = "Legion"; slug = "black-rook-hold" }
    @{ name = "Court of Stars";                          expansion = "Legion"; slug = "court-of-stars" }
    @{ name = "Darkheart Thicket";                       expansion = "Legion"; slug = "darkheart-thicket" }
    @{ name = "Eye of Azshara";                          expansion = "Legion"; slug = "eye-of-azshara" }
    @{ name = "Halls of Valor";                          expansion = "Legion"; slug = "halls-of-valor" }
    @{ name = "Maw of Souls";                            expansion = "Legion"; slug = "maw-of-souls" }
    @{ name = "Neltharion's Lair";                       expansion = "Legion"; slug = "neltharions-lair" }
    @{ name = "The Arcway";                              expansion = "Legion"; slug = "the-arcway" }
    @{ name = "Vault of the Wardens";                    expansion = "Legion"; slug = "vault-of-the-wardens" }
    @{ name = "Cathedral of Eternal Night";              expansion = "Legion"; slug = "cathedral-of-eternal-night" }
    @{ name = "Return to Karazhan: Lower";               expansion = "Legion"; slug = "return-to-karazhan-lower" }
    @{ name = "Return to Karazhan: Upper";               expansion = "Legion"; slug = "return-to-karazhan-upper" }
    @{ name = "Seat of the Triumvirate";                 expansion = "Legion"; slug = "seat-of-the-triumvirate" }

    # Battle for Azeroth
    @{ name = "Atal'Dazar";                              expansion = "Battle for Azeroth"; slug = "ataldazar" }
    @{ name = "Freehold";                                expansion = "Battle for Azeroth"; slug = "freehold"; zoneId = 9164 }
    @{ name = "King's Rest";                             expansion = "Battle for Azeroth"; slug = "kings-rest" }
    @{ name = "Operation: Mechagon - Junkyard";          expansion = "Battle for Azeroth"; slug = "operation-mechagon-junkyard" }
    @{ name = "Operation: Mechagon - Workshop";          expansion = "Battle for Azeroth"; slug = "operation-mechagon-workshop" }
    @{ name = "Shrine of the Storm";                     expansion = "Battle for Azeroth"; slug = "shrine-of-the-storm" }
    @{ name = "Siege of Boralus";                        expansion = "Battle for Azeroth"; slug = "siege-of-boralus" }
    @{ name = "Temple of Sethraliss";                    expansion = "Battle for Azeroth"; slug = "temple-of-sethraliss" }
    @{ name = "The MOTHERLODE!!";                        expansion = "Battle for Azeroth"; slug = "the-motherlode" }
    @{ name = "Tol Dagor";                               expansion = "Battle for Azeroth"; slug = "tol-dagor" }
    @{ name = "The Underrot";                            expansion = "Battle for Azeroth"; slug = "the-underrot" }
    @{ name = "Waycrest Manor";                          expansion = "Battle for Azeroth"; slug = "waycrest-manor" }

    # Shadowlands
    @{ name = "De Other Side";                           expansion = "Shadowlands"; slug = "de-other-side" }
    @{ name = "Halls of Atonement";                      expansion = "Shadowlands"; slug = "halls-of-atonement"; zoneId = 12831 }
    @{ name = "Mists of Tirna Scithe";                   expansion = "Shadowlands"; slug = "mists-of-tirna-scithe" }
    @{ name = "Plaguefall";                              expansion = "Shadowlands"; slug = "plaguefall" }
    @{ name = "Sanguine Depths";                         expansion = "Shadowlands"; slug = "sanguine-depths" }
    @{ name = "Spires of Ascension";                     expansion = "Shadowlands"; slug = "spires-of-ascension" }
    @{ name = "Tazavesh: So'leah's Gambit";              expansion = "Shadowlands"; slug = "tazavesh-soleahs-gambit" }
    @{ name = "Tazavesh: Streets of Wonder";             expansion = "Shadowlands"; slug = "tazavesh-streets-of-wonder" }
    @{ name = "The Necrotic Wake";                       expansion = "Shadowlands"; slug = "the-necrotic-wake" }
    @{ name = "Theater of Pain";                         expansion = "Shadowlands"; slug = "theater-of-pain" }

    # Dragonflight
    @{ name = "Algeth'ar Academy";                       expansion = "Dragonflight"; slug = "algethar-academy"; zoneId = 14032 }
    @{ name = "The Azure Vault";                         expansion = "Dragonflight"; slug = "the-azure-vault" }
    @{ name = "Brackenhide Hollow";                      expansion = "Dragonflight"; slug = "brackenhide-hollow" }
    @{ name = "Dawn of the Infinite: Galakrond's Fall";  expansion = "Dragonflight"; slug = "dawn-of-the-infinite-galakronds-fall" }
    @{ name = "Dawn of the Infinite: Murozond's Rise";   expansion = "Dragonflight"; slug = "dawn-of-the-infinite-murozonds-rise" }
    @{ name = "Halls of Infusion";                       expansion = "Dragonflight"; slug = "halls-of-infusion" }
    @{ name = "Neltharus";                               expansion = "Dragonflight"; slug = "neltharus" }
    @{ name = "The Nokhud Offensive";                    expansion = "Dragonflight"; slug = "the-nokhud-offensive" }
    @{ name = "Ruby Life Pools";                         expansion = "Dragonflight"; slug = "ruby-life-pools" }
    @{ name = "Uldaman: Legacy of Tyr";                  expansion = "Dragonflight"; slug = "uldaman-legacy-of-tyr" }

    # The War Within
    @{ name = "Ara-Kara, City of Echoes";                expansion = "The War Within"; slug = "ara-kara-city-of-echoes" }
    @{ name = "Cinderbrew Meadery";                      expansion = "The War Within"; slug = "cinderbrew-meadery" }
    @{ name = "City of Threads";                         expansion = "The War Within"; slug = "city-of-threads" }
    @{ name = "Darkflame Cleft";                         expansion = "The War Within"; slug = "darkflame-cleft" }
    @{ name = "Operation: Floodgate";                    expansion = "The War Within"; slug = "operation-floodgate" }
    @{ name = "Priory of the Sacred Flame";              expansion = "The War Within"; slug = "priory-of-the-sacred-flame" }
    @{ name = "The Dawnbreaker";                         expansion = "The War Within"; slug = "the-dawnbreaker" }
    @{ name = "The Rookery";                             expansion = "The War Within"; slug = "the-rookery" }
    @{ name = "The Stonevault";                          expansion = "The War Within"; slug = "the-stonevault" }
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$out       = Join-Path $RepoRoot 'data/dungeons.json'

$resolved = [System.Collections.ArrayList]::new()
$resolvedCount = 0; $failed = 0; $i = 0

foreach ($d in $dungeons) {
    $i++
    if ($d.zoneId) {
        Write-Host ("[{0,2}/{1}]  {2,-45}  (already known: {3})" -f $i, $dungeons.Count, $d.name, $d.zoneId)
        [void]$resolved.Add([PSCustomObject]([ordered]@{
            name      = $d.name
            slug      = $d.slug
            expansion = $d.expansion
            zoneId    = [int]$d.zoneId
        }))
        $resolvedCount++
        continue
    }
    Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 400)
    try {
        $r = Invoke-WebRequest -Uri "https://www.wowhead.com/$($d.slug)" -UserAgent $UserAgent -Headers $BrowserHeaders -UseBasicParsing -MaximumRedirection 5 -ErrorAction Stop
        $final = $r.BaseResponse.ResponseUri.AbsolutePath
        $m = [regex]::Match($final, '/zone=(\d+)')
        if ($m.Success) {
            $zid = [int]$m.Groups[1].Value
            Write-Host ("[{0,2}/{1}]  {2,-45}  -> zone={3}" -f $i, $dungeons.Count, $d.name, $zid)
            [void]$resolved.Add([PSCustomObject]([ordered]@{
                name      = $d.name
                slug      = $d.slug
                expansion = $d.expansion
                zoneId    = $zid
            }))
            $resolvedCount++
        } else {
            Write-Warning "[{0,2}/{1}]  {2,-45}  -> final URI did not match /zone=NNN: $final" -f $i, $dungeons.Count, $d.name
            [void]$resolved.Add([PSCustomObject]([ordered]@{
                name      = $d.name
                slug      = $d.slug
                expansion = $d.expansion
                zoneId    = $null
            }))
            $failed++
        }
    } catch {
        Write-Warning ("[{0,2}/{1}]  {2,-45}  -> ERROR: $($_.Exception.Message)" -f $i, $dungeons.Count, $d.name)
        [void]$resolved.Add([PSCustomObject]([ordered]@{
            name      = $d.name
            slug      = $d.slug
            expansion = $d.expansion
            zoneId    = $null
        }))
        $failed++
    }
}

# Write
$json = (@{ dungeons = @($resolved) } | ConvertTo-Json -Depth 6) -replace "`r`n", "`n"
$dir = Split-Path -Parent $out
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
[System.IO.File]::WriteAllText($out, $json + "`n", [System.Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host ("Done. Resolved {0}/{1}, failed {2}. Wrote {3}" -f $resolvedCount, $dungeons.Count, $failed, $out)
