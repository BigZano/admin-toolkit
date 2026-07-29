# Find files modified in the last X hours (troubleshooting aid)

param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
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
$outputFile = Join-Path $OutputDirectory "Get-RecentlyModifiedFiles_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Get-RecentlyModifiedFiles_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

if (-not (Test-Path $Path)) {
    Write-Log "ERROR: Path not found: $Path" "Red"
    exit 1
}

$hours  = [int]$HoursBack
$cutoff = (Get-Date).AddHours(-$hours)

Write-Log "Scanning $Path for files modified since $($cutoff.ToString('yyyy-MM-dd HH:mm'))..." "Cyan"

$results = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $cutoff } |
    Sort-Object LastWriteTime -Descending |
    ForEach-Object {
        [PSCustomObject]@{
            LastWriteTime = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            SizeMB        = [math]::Round($_.Length / 1MB, 2)
            File          = $_.FullName
        }
    }

$results = @($results)

if ($results.Count -eq 0) {
    Write-Log "No files modified in the last $hours hour(s) under $Path." "Yellow"
    exit 0
}

$results | Export-Csv -Path $outputFile -NoTypeInformation

$results | Select-Object -First 50 | Format-Table -AutoSize
if ($results.Count -gt 50) {
    Write-Log "(Showing first 50 of $($results.Count) files - full list in CSV)" "Yellow"
}

Write-Log "Found $($results.Count) file(s) modified in the last $hours hour(s)." "Cyan"
Write-Log "Report saved: $outputFile" "Green"
