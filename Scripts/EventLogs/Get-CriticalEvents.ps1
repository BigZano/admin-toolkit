# List critical and error events from the last X hours

param(
    [Parameter(Mandatory=$false)]
    [string]$HoursBack = "24",
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
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
$outputFile = Join-Path $OutputDirectory "Get-CriticalEvents_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Get-CriticalEvents_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$hours  = [int]$HoursBack
$cutoff = (Get-Date).AddHours(-$hours)
$logs   = @("System", "Application")
$target = if ([string]::IsNullOrEmpty($ComputerName)) { $env:COMPUTERNAME } else { $ComputerName }

Write-Log "Collecting critical/error events on $target since $($cutoff.ToString('yyyy-MM-dd HH:mm'))..." "Cyan"

$results = @()
$levelNames = @{ 1 = "Critical"; 2 = "Error" }

foreach ($log in $logs) {
    try {
        $params = @{ FilterHashtable = @{LogName=$log; Level=1,2; StartTime=$cutoff}; ErrorAction = "Stop" }
        if (-not [string]::IsNullOrEmpty($ComputerName)) { $params.ComputerName = $ComputerName }
        $events = Get-WinEvent @params

        foreach ($evt in $events) {
            $msg = if ($evt.Message) { ($evt.Message -replace '\s+', ' ').Trim() } else { "" }
            if ($msg.Length -gt 200) { $msg = $msg.Substring(0, 200) + "..." }
            $results += [PSCustomObject]@{
                Time     = $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                Log      = $log
                Level    = if ($levelNames.ContainsKey([int]$evt.Level)) { $levelNames[[int]$evt.Level] } else { "$($evt.Level)" }
                Id       = $evt.Id
                Provider = $evt.ProviderName
                Message  = $msg
            }
        }
        Write-Log "  ${log}: $(@($events).Count) event(s)"
    } catch {
        if ($_.Exception.Message -match '(?i)No events were found') {
            Write-Log "  ${log}: 0 events" "Green"
        } else {
            Write-Log "  ${log}: query failed - $($_.Exception.Message)" "Yellow"
        }
    }
}

if ($results.Count -eq 0) {
    Write-Log "No critical or error events on $target in the last $hours hour(s)." "Green"
    exit 0
}

$results = @($results | Sort-Object Time -Descending)
$results | Export-Csv -Path $outputFile -NoTypeInformation

Write-Host ""
$results | Select-Object -First 40 | Format-Table Time, Log, Level, Id, Provider -AutoSize
if ($results.Count -gt 40) {
    Write-Log "(Showing latest 40 of $($results.Count) events - full list with messages in CSV)" "Yellow"
}

$criticals = @($results | Where-Object { $_.Level -eq "Critical" })
Write-Log "Total: $($results.Count) event(s), $($criticals.Count) critical." $(if ($criticals.Count -gt 0) { "Red" } else { "Yellow" })
Write-Log "Report saved: $outputFile" "Green"
