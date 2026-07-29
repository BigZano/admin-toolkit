# Summarize errors and warnings by source across main logs

param(
    [Parameter(Mandatory=$false)]
    [string]$HoursBack = "24",
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
$outputFile = Join-Path $OutputDirectory "Get-EventLogSummary_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Get-EventLogSummary_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$hours  = [int]$HoursBack
$cutoff = (Get-Date).AddHours(-$hours)
$logs   = @("System", "Application")

Write-Log "Summarizing errors/warnings in $($logs -join ', ') since $($cutoff.ToString('yyyy-MM-dd HH:mm'))..." "Cyan"

$allEvents = @()

foreach ($log in $logs) {
    try {
        $events = Get-WinEvent -FilterHashtable @{LogName=$log; Level=1,2,3; StartTime=$cutoff} -ErrorAction Stop
        $allEvents += @($events | ForEach-Object { $_ | Add-Member -NotePropertyName SourceLog -NotePropertyValue $log -PassThru })
        Write-Log "  ${log}: $(@($events).Count) event(s)"
    } catch {
        if ($_.Exception.Message -match '(?i)No events were found') {
            Write-Log "  ${log}: 0 events" "Green"
        } else {
            Write-Log "  ${log}: query failed - $($_.Exception.Message)" "Yellow"
        }
    }
}

if ($allEvents.Count -eq 0) {
    Write-Log "No errors or warnings in the last $hours hour(s). All quiet." "Green"
    exit 0
}

$levelNames = @{ 1 = "Critical"; 2 = "Error"; 3 = "Warning" }

$results = $allEvents |
    Group-Object -Property { "$($_.ProviderName)|$($_.Level)" } |
    ForEach-Object {
        $first  = $_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1
        $sample = if ($first.Message) { ($first.Message -replace '\s+', ' ').Trim() } else { "" }
        if ($sample.Length -gt 120) { $sample = $sample.Substring(0, 120) + "..." }
        [PSCustomObject]@{
            Provider   = $first.ProviderName
            Level      = if ($levelNames.ContainsKey([int]$first.Level)) { $levelNames[[int]$first.Level] } else { "$($first.Level)" }
            Log        = $first.SourceLog
            Count      = $_.Count
            LastSeen   = $first.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
            SampleMsg  = $sample
        }
    } | Sort-Object Count -Descending

$results = @($results)
$results | Export-Csv -Path $outputFile -NoTypeInformation

Write-Host ""
$results | Select-Object -First 20 | Format-Table Provider, Level, Log, Count, LastSeen -AutoSize
if ($results.Count -gt 20) {
    Write-Log "(Showing top 20 of $($results.Count) provider/level groups - full list in CSV)" "Yellow"
}

$criticals = @($allEvents | Where-Object { $_.Level -eq 1 })
$errors    = @($allEvents | Where-Object { $_.Level -eq 2 })
$warnings  = @($allEvents | Where-Object { $_.Level -eq 3 })
Write-Log "Total: $($allEvents.Count) events - Critical: $($criticals.Count), Error: $($errors.Count), Warning: $($warnings.Count)" $(if ($criticals.Count -gt 0) { "Red" } elseif ($errors.Count -gt 0) { "Yellow" } else { "Cyan" })
Write-Log "Report saved: $outputFile" "Green"
