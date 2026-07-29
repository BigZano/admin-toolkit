# Search event logs by ID, keyword, or provider

param(
    [Parameter(Mandatory=$false)]
    [string]$LogName = "System",
    [Parameter(Mandatory=$false)]
    [string]$EventId = "",
    [Parameter(Mandatory=$false)]
    [string]$Keyword = "",
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
$outputFile = Join-Path $OutputDirectory "Search-EventLog_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Search-EventLog_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

if ([string]::IsNullOrEmpty($EventId) -and [string]::IsNullOrEmpty($Keyword)) {
    Write-Log "Please provide at least one of EventId (comma-separated IDs) or Keyword to search for." "Red"
    exit 1
}

$hours  = [int]$HoursBack
$cutoff = (Get-Date).AddHours(-$hours)

# Build filter hashtable dynamically
$filter = @{ LogName = $LogName; StartTime = $cutoff }
if (-not [string]::IsNullOrEmpty($EventId)) {
    try {
        $ids = @($EventId -split ',' | ForEach-Object { [int]$_.Trim() })
        $filter.Id = $ids
    } catch {
        Write-Log "ERROR: EventId must be a comma-separated list of numbers (got '$EventId')." "Red"
        exit 1
    }
}

$criteria = @()
if ($filter.ContainsKey('Id')) { $criteria += "Id in [$($filter.Id -join ', ')]" }
if (-not [string]::IsNullOrEmpty($Keyword)) { $criteria += "message contains '$Keyword'" }
Write-Log "Searching '$LogName' log (last $hours h) where $($criteria -join ' and ')..." "Cyan"

$events = @()
try {
    $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
} catch {
    if ($_.Exception.Message -match '(?i)No events were found') {
        $events = @()
    } else {
        Write-Log "ERROR: Event log query failed: $($_.Exception.Message)" "Red"
        exit 1
    }
}

# Client-side keyword filter on message text
if (-not [string]::IsNullOrEmpty($Keyword)) {
    $events = @($events | Where-Object { $_.Message -and $_.Message -match [regex]::Escape($Keyword) })
}

if ($events.Count -eq 0) {
    Write-Log "No matching events found in '$LogName' for the last $hours hour(s)." "Yellow"
    exit 0
}

$levelNames = @{ 0 = "Info"; 1 = "Critical"; 2 = "Error"; 3 = "Warning"; 4 = "Information"; 5 = "Verbose" }

$results = foreach ($evt in $events) {
    $msg = if ($evt.Message) { ($evt.Message -replace '\s+', ' ').Trim() } else { "" }
    if ($msg.Length -gt 200) { $msg = $msg.Substring(0, 200) + "..." }
    [PSCustomObject]@{
        Time     = $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
        Log      = $LogName
        Level    = if ($levelNames.ContainsKey([int]$evt.Level)) { $levelNames[[int]$evt.Level] } else { "$($evt.Level)" }
        Id       = $evt.Id
        Provider = $evt.ProviderName
        Message  = $msg
    }
}

$results = @($results | Sort-Object Time -Descending)
$results | Export-Csv -Path $outputFile -NoTypeInformation

Write-Host ""
$results | Select-Object -First 40 | Format-Table Time, Level, Id, Provider -AutoSize
if ($results.Count -gt 40) {
    Write-Log "(Showing latest 40 of $($results.Count) matches - full list with messages in CSV)" "Yellow"
}

Write-Log "Found $($results.Count) matching event(s)." "Cyan"
Write-Log "Report saved: $outputFile" "Green"
