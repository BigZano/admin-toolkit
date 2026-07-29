# Show shutdown and reboot history with reasons

param(
    [Parameter(Mandatory=$false)]
    [string]$DaysBack = "30",
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
$outputFile = Join-Path $OutputDirectory "Get-RebootHistory_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Get-RebootHistory_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$days   = [int]$DaysBack
$cutoff = (Get-Date).AddDays(-$days)

Write-Log "Querying shutdown/reboot events since $($cutoff.ToString('yyyy-MM-dd'))..." "Cyan"

$events = $null
try {
    $events = Get-WinEvent -FilterHashtable @{LogName='System'; Id=1074,6008,41; StartTime=$cutoff} -ErrorAction Stop
} catch {
    if ($_.Exception.Message -match '(?i)No events were found') {
        $events = @()
    } else {
        Write-Log "ERROR: Failed to query the System event log: $($_.Exception.Message)" "Red"
        exit 1
    }
}

if (-not $events -or @($events).Count -eq 0) {
    Write-Log "No shutdown or reboot events found in the last $days day(s)." "Yellow"
    exit 0
}

$results = @()

foreach ($evt in $events) {
    $type    = ""
    $process = ""
    $user    = ""
    $reason  = ""
    $color   = "White"

    switch ($evt.Id) {
        1074 {
            $type = "Planned shutdown/restart"
            # Properties: 0=process, 1=?, 2=reason text, 4=shutdown type, 6=user
            try {
                if ($evt.Properties.Count -gt 0) { $process = "$($evt.Properties[0].Value)" }
                if ($evt.Properties.Count -gt 2) { $reason  = "$($evt.Properties[2].Value)" }
                if ($evt.Properties.Count -gt 4) { $type    = "Initiated: $($evt.Properties[4].Value)" }
                if ($evt.Properties.Count -gt 6) { $user    = "$($evt.Properties[6].Value)" }
            } catch { }
            $color = "White"
        }
        6008 {
            $type   = "Unexpected shutdown"
            $reason = "Previous system shutdown was unexpected"
            $color  = "Red"
        }
        41 {
            $type   = "Kernel-Power (dirty reboot)"
            $reason = "System rebooted without a clean shutdown (crash/power loss)"
            $color  = "Red"
        }
    }

    $row = [PSCustomObject]@{
        Time    = $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
        EventId = $evt.Id
        Type    = $type
        Process = $process
        User    = $user
        Reason  = $reason
    }
    $results += $row
    Write-Log ("  {0}  [{1,4}]  {2}  {3}" -f $row.Time, $row.EventId, $row.Type, $row.User) $color
}

$results | Export-Csv -Path $outputFile -NoTypeInformation

Write-Host ""
$results | Format-Table Time, EventId, Type, User, Reason -AutoSize

$unexpected = @($results | Where-Object { $_.EventId -in 6008, 41 })
Write-Log "Total events: $($results.Count); unexpected/dirty: $($unexpected.Count)" $(if ($unexpected.Count -gt 0) { "Yellow" } else { "Cyan" })
Write-Log "Report saved: $outputFile" "Green"
