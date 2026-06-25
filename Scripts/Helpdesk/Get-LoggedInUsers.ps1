# Show all active and disconnected user sessions on a local or remote computer

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = ""
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "  $(Get-Date -Format 'HH:mm:ss')  $Message" -ForegroundColor $Color
}

$target  = if ([string]::IsNullOrEmpty($ComputerName)) { $env:COMPUTERNAME } else { $ComputerName }
$isLocal = $target -eq $env:COMPUTERNAME

Write-Host ""
Write-Host ("  Sessions on: {0}" -f $target) -ForegroundColor Cyan
Write-Host ""

try {
    # quser works locally and remotely, output needs parsing
    $raw = if ($isLocal) {
        quser 2>&1
    } else {
        quser /server:$target 2>&1
    }

    if ($LASTEXITCODE -ne 0 -or $raw -match "No User exists") {
        Write-Log "No active sessions found on $target." "Green"
        exit 0
    }

    # Parse quser output — fixed-width columns
    # Header: USERNAME  SESSIONNAME  ID  STATE  IDLE TIME  LOGON TIME
    $sessions = $raw | Select-Object -Skip 1 | ForEach-Object {
        $line = $_
        if ($line -match '^\s*>?\s*(\S+)\s+(\S*)\s+(\d+)\s+(\w+)\s+(\S+)\s+(.+)$') {
            $username    = $Matches[1] -replace '>', ''
            $sessionName = $Matches[2]
            $sessionId   = $Matches[3]
            $state       = $Matches[4]
            $idleTime    = $Matches[5]
            $logonTime   = $Matches[6].Trim()

            [PSCustomObject]@{
                Username    = $username
                Session     = $sessionName
                ID          = $sessionId
                State       = $state
                IdleTime    = $idleTime
                LogonTime   = $logonTime
                IsActive    = $state -eq "Active"
            }
        }
    } | Where-Object { $_ -ne $null }

    if (-not $sessions -or $sessions.Count -eq 0) {
        Write-Log "No sessions could be parsed on $target." "Yellow"
        Write-Host "  Raw output:" -ForegroundColor DarkGray
        $raw | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        exit 0
    }

    $active       = @($sessions | Where-Object { $_.IsActive })
    $disconnected = @($sessions | Where-Object { -not $_.IsActive })

    Write-Host ("  Active: {0}  |  Disconnected: {1}" -f $active.Count, $disconnected.Count) -ForegroundColor Cyan
    Write-Host ""

    $sessions | ForEach-Object {
        $color = if ($_.IsActive) { "Green" } else { "Yellow" }
        $flag  = if ($_.IsActive) { "[Active      ]" } else { "[Disconnected]" }
        Write-Host ("  {0} {1,-20} Session: {2,-15} ID: {3,-4} Idle: {4,-10} Logon: {5}" -f
            $flag, $_.Username, $_.Session, $_.ID, $_.IdleTime, $_.LogonTime) -ForegroundColor $color
    }

    Write-Host ""
    if ($disconnected.Count -gt 0) {
        Write-Log "$($disconnected.Count) disconnected session(s) — consider logging off idle sessions." "Yellow"
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"
    Write-Log "Ensure Remote Registry and Remote Desktop services are accessible on $target." "Yellow"
    exit 1
}
