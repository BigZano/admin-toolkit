# Check Windows Server Backup job history, last run status, and next schedule

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerList = "",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = Join-Path $env:USERPROFILE "Documents\AdminToolReports"
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "BackupStatus_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "BackupStatus_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$computers = if (-not [string]::IsNullOrEmpty($ComputerList) -and (Test-Path $ComputerList -ErrorAction SilentlyContinue)) {
    Get-Content $ComputerList | Where-Object { $_ -match '\S' }
} elseif (-not [string]::IsNullOrEmpty($ComputerList)) {
    $ComputerList -split ',' | ForEach-Object { $_.Trim() }
} else {
    @($env:COMPUTERNAME)
}

Write-Log "Checking Windows Server Backup on $($computers.Count) server(s)..." "Cyan"
Write-Host ""

$collectScript = {
    $backupPolicy = $null; $summary = $null
    try {
        Import-Module WindowsServerBackup -ErrorAction Stop
        # Get-WBPolicy has no -Cached parameter; it requires Administrators or Backup Operators rights.
        $backupPolicy = Get-WBPolicy -ErrorAction SilentlyContinue
        $summary      = Get-WBSummary -ErrorAction SilentlyContinue
    } catch { }

    $lastJob = if ($summary) {
        [PSCustomObject]@{
            LastSuccessTime  = $summary.LastSuccessfulBackupTime
            LastBackupTime   = $summary.LastBackupTime
            LastBackupResult = $summary.LastBackupResultHR
            NextBackupTime   = $summary.NextBackupTime
            NumberOfVersions = $summary.NumberOfVersions
            DetailedMessage  = $summary.DetailedMessage
        }
    } else { $null }

    [PSCustomObject]@{
        Computer        = $env:COMPUTERNAME
        HasPolicy       = ($null -ne $backupPolicy)
        Summary         = $lastJob
    }
}

$report = foreach ($computer in $computers) {
    Write-Host "  $computer" -ForegroundColor Cyan

    try {
        $result = if ($computer -eq $env:COMPUTERNAME) {
            & $collectScript
        } else {
            Invoke-Command -ComputerName $computer -ErrorAction Stop -ScriptBlock $collectScript
        }

        $summary = $result.Summary
        if (-not $result.HasPolicy -or -not $summary) {
            Write-Host "    Windows Server Backup not configured, no backup history, or insufficient rights (requires Administrators/Backup Operators)." -ForegroundColor Yellow
            [PSCustomObject]@{
                Computer = $computer; Status = "Not Configured"; LastSuccess = ""; LastBackup = ""
                AgeDays = ""; NextBackup = ""; Versions = 0; Result = ""
            }
            continue
        }

        $lastOK   = if ($summary.LastSuccessTime) { $summary.LastSuccessTime.ToString("yyyy-MM-dd HH:mm") } else { "Never" }
        $lastRun  = if ($summary.LastBackupTime)  { $summary.LastBackupTime.ToString("yyyy-MM-dd HH:mm")  } else { "Never" }
        $next     = if ($summary.NextBackupTime)  { $summary.NextBackupTime.ToString("yyyy-MM-dd HH:mm")  } else { "Not scheduled" }
        $ageDays  = if ($summary.LastSuccessTime) { [math]::Round(((Get-Date) - $summary.LastSuccessTime).TotalDays, 1) } else { 999 }
        # Precedence: a failed last backup (or no successful backup ever) beats a stale-age warning.
        $status   = if ($summary.LastBackupResult -ne 0) { "FAILED" }
                    elseif ($ageDays -ge 999) { "FAILED" }
                    elseif ($ageDays -gt 3) { "WARNING" }
                    else { "OK" }
        $color    = switch ($status) { "OK" { "Green" } "WARNING" { "Yellow" } "FAILED" { "Red" } default { "White" } }

        Write-Host ("    Status: {0,-10} Last success: {1}  ({2} days ago)" -f $status, $lastOK, $ageDays) -ForegroundColor $color
        Write-Host ("    Next scheduled: {0}   Versions stored: {1}" -f $next, $summary.NumberOfVersions) -ForegroundColor Gray

        [PSCustomObject]@{
            Computer    = $computer
            Status      = $status
            LastSuccess = $lastOK
            LastBackup  = $lastRun
            AgeDays     = $ageDays
            NextBackup  = $next
            Versions    = $summary.NumberOfVersions
            Result      = $summary.LastBackupResult
        }
    } catch {
        Write-Log "  Failed to connect to $computer : $($_.Exception.Message)" "Red"
        [PSCustomObject]@{
            Computer = $computer; Status = "ERROR"; LastSuccess = ""; LastBackup = ""
            AgeDays = ""; NextBackup = ""; Versions = 0; Result = $_.Exception.Message
        }
    }
    Write-Host ""
}

$failed  = @($report | Where-Object { $_.Status -eq "FAILED" -or $_.Status -eq "ERROR" }).Count
$warning = @($report | Where-Object { $_.Status -eq "WARNING" }).Count
$color   = if ($failed -gt 0) { "Red" } elseif ($warning -gt 0) { "Yellow" } else { "Green" }
Write-Log ("Servers: $($computers.Count)  |  OK: $(@($report | Where-Object {$_.Status -eq 'OK'}).Count)  |  Warning: $warning  |  Failed/Error: $failed") $color

$report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
