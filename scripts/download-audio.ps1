#requires -Version 5.1
<#
.SYNOPSIS
  Download .ogg audio files for sounds listed in data/voicelines.json into audio/cache/.

.DESCRIPTION
  Reads the `sounds` array, downloads each entry's `url` to audio/cache/{id}.ogg.
  Idempotent: files that already exist on disk are skipped.

.PARAMETER NpcFilter
  If provided, only sounds whose `npc` field equals this value are downloaded.

.EXAMPLE
  ./scripts/download-audio.ps1 -NpcFilter Odyn
#>
param(
    [string] $DataFile = 'data/voicelines.json',
    [string] $CacheDir = 'audio/cache',
    [string] $NpcFilter
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$DataPath  = Join-Path $RepoRoot $DataFile
$CachePath = Join-Path $RepoRoot $CacheDir

if (-not (Test-Path $DataPath)) { throw "Data file not found: $DataPath" }
if (-not (Test-Path $CachePath)) {
    Write-Host "Creating cache directory: $CachePath"
    New-Item -ItemType Directory -Path $CachePath -Force | Out-Null
}

$data   = Get-Content $DataPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sounds = $data.sounds
if ($NpcFilter) { $sounds = @($sounds | Where-Object { $_.npc -eq $NpcFilter }) }

$total = $sounds.Count
if ($total -eq 0) { Write-Host 'No sounds matched.'; exit 0 }

Write-Host "Processing $total sounds$(if($NpcFilter){" for npc='$NpcFilter'"})..."

# Speed up Invoke-WebRequest by disabling progress UI
$ProgressPreference = 'SilentlyContinue'

$downloaded = 0; $skipped = 0; $failed = 0; $i = 0
foreach ($s in $sounds) {
    $i++
    $out = Join-Path $CachePath "$($s.id).ogg"
    if (Test-Path $out) { $skipped++; continue }

    try {
        Invoke-WebRequest -Uri $s.url -OutFile $out -UseBasicParsing -ErrorAction Stop
        $downloaded++
        if ($downloaded % 25 -eq 0) {
            Write-Host ("  [{0}/{1}] downloaded {2} so far..." -f $i, $total, $downloaded)
        }
    } catch {
        Write-Warning "  Failed id=$($s.id) url=$($s.url): $($_.Exception.Message)"
        if (Test-Path $out) { Remove-Item $out -Force }  # clean partial file
        $failed++
    }
}

Write-Host ''
Write-Host ("Done. Downloaded {0}, skipped {1} (already present), failed {2}. Total: {3}." -f $downloaded, $skipped, $failed, $total)
