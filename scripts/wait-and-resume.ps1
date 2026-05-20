#requires -Version 5.1
<#
.SYNOPSIS
  Polls Wowhead until the WAF unblocks us, then resumes process-all-dungeons.ps1.
#>
$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
$Headers = @{
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
$ProgressPreference = 'SilentlyContinue'

Write-Host "Waiting for Wowhead to unblock... (polling every 60s)"
$attempts = 0
$maxWait = 30  # max 30 minutes
while ($attempts -lt $maxWait) {
    $attempts++
    try {
        $r = Invoke-WebRequest -Uri 'https://www.wowhead.com/zone=14032/algethar-academy' -UserAgent $UserAgent -Headers $Headers -UseBasicParsing -ErrorAction Stop
        Write-Host ("  attempt {0}: OK ({1} bytes) - resuming" -f $attempts, $r.RawContentLength)
        break
    } catch {
        Write-Host ("  attempt {0}: still blocked ($($_.Exception.Message))" -f $attempts)
        Start-Sleep -Seconds 60
    }
}

if ($attempts -ge $maxWait) {
    Write-Warning "Gave up after $maxWait attempts (30 min)"
    exit 1
}

# Pause briefly to let the unblock fully settle before hammering
Start-Sleep -Seconds 30
Write-Host ''
Write-Host '== Resuming orchestrator =='
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'process-all-dungeons.ps1')
