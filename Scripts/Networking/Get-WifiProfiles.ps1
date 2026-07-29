# List saved Wi-Fi profiles on this machine

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    if ($IsWindows -or $env:OS -match "Windows") {
        $OutputDirectory = Join-Path $env:USERPROFILE "Documents\AdminToolReports"
    } else {
        $OutputDirectory = Join-Path $env:HOME "Documents/AdminToolReports"
    }
}
if (-not (Test-Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "Get-WifiProfiles_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Get-WifiProfiles_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "Enumerating saved Wi-Fi profiles..." "Cyan"

$raw = netsh wlan show profiles 2>&1 | Out-String

if ($raw -match '(?i)(no wireless interface|not running|is not running)') {
    Write-Log "No wireless interface found on this machine (or the WLAN service is not running)." "Yellow"
    Write-Log "Log saved: $logFile" "Green"
    exit 0
}

$profileNames = @()
foreach ($line in ($raw -split "`r?`n")) {
    if ($line -match 'All User Profile\s*:\s*(.+)') {
        $profileNames += $Matches[1].Trim()
    }
}

if ($profileNames.Count -eq 0) {
    Write-Log "No saved Wi-Fi profiles found on this machine." "Yellow"
    Write-Log "Log saved: $logFile" "Green"
    exit 0
}

$results = @()
$skipped = 0

foreach ($name in $profileNames) {
    try {
        $detail = netsh wlan show profile name="$name" 2>&1 | Out-String
        $auth   = "Unknown"
        $cipher = "Unknown"
        $mode   = "Unknown"
        if ($detail -match 'Authentication\s*:\s*(.+)') { $auth   = $Matches[1].Trim() }
        if ($detail -match 'Cipher\s*:\s*(.+)')         { $cipher = $Matches[1].Trim() }
        if ($detail -match 'Connection mode\s*:\s*(.+)'){ $mode   = $Matches[1].Trim() }

        $results += [PSCustomObject]@{
            ProfileName    = $name
            Authentication = $auth
            Cipher         = $cipher
            ConnectionMode = $mode
        }
    } catch {
        $skipped++
        Write-Log "Could not read profile '$name': $($_.Exception.Message)" "Yellow"
    }
}

$results | Export-Csv -Path $outputFile -NoTypeInformation
$results | Format-Table -AutoSize

$openProfiles = @($results | Where-Object { $_.Authentication -match '(?i)open' })
Write-Log "Found $($results.Count) Wi-Fi profile(s); $($openProfiles.Count) using Open authentication; $skipped skipped." "Cyan"
if ($openProfiles.Count -gt 0) {
    Write-Log "Open (unsecured) profiles: $(($openProfiles.ProfileName) -join ', ')" "Yellow"
}
Write-Log "Report saved: $outputFile" "Green"
