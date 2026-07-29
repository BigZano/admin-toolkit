# Find files not modified within the specified number of days, for archival or cleanup

param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [Parameter(Mandatory=$false)]
    [string]$DaysOld = "365",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = if ($IsWindows -or $env:OS -match "Windows") {
        Join-Path $env:USERPROFILE "Documents\AdminToolReports"
    } else { Join-Path $env:HOME "Documents/AdminToolReports" }
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile    = Join-Path $OutputDirectory "OldFiles_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$days = 0
if (-not [int]::TryParse($DaysOld, [ref]$days) -or $days -lt 0) {
    Write-Log "Invalid DaysOld value: '$DaysOld' (expected a non-negative integer)" "Red"; exit 1
}
$cutoff     = (Get-Date).AddDays(-$days)
$outputFile = Join-Path $OutputDirectory "OldFiles_${days}days_$timestamp.csv"

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Log "Path not found: $Path" "Red"; exit 1
}

Write-Log "Scanning for files not modified since: $($cutoff.ToString('yyyy-MM-dd'))  ($days days)" "Cyan"
Write-Log "Large directory trees may take several minutes..." "DarkGray"

try {
    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue -ErrorVariable scanErrors |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Sort-Object LastWriteTime |
        ForEach-Object {
            [PSCustomObject]@{
                LastModified = $_.LastWriteTime.ToString("yyyy-MM-dd")
                LastAccessed = $_.LastAccessTime.ToString("yyyy-MM-dd")
                DaysOld      = [int]((Get-Date) - $_.LastWriteTime).TotalDays
                SizeMB       = [math]::Round($_.Length / 1MB, 2)
                Name         = $_.Name
                Extension    = $_.Extension
                FullPath     = $_.FullName
            }
        }

    if ($scanErrors.Count -gt 0) { Write-Log "Skipped $($scanErrors.Count) inaccessible item(s)" "Yellow" }
    $totalSizeGB = [math]::Round(($files | Measure-Object -Property SizeMB -Sum).Sum / 1024, 2)
    Write-Log "Found $($files.Count) files older than $days days  (total: $totalSizeGB GB)" "$(if ($files.Count -gt 0) { 'Yellow' } else { 'Green' })"

    if ($files.Count -gt 0) {
        # Group by extension
        Write-Host ""
        Write-Host "  Top extensions by count:" -ForegroundColor DarkGray
        $files | Group-Object Extension | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object {
            Write-Host ("  {0,-10} {1,6} files" -f $_.Name, $_.Count) -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "  Oldest files:" -ForegroundColor DarkGray
        $files | Select-Object -First 10 | ForEach-Object {
            Write-Host ("  {0}  ({1} days)  {2}" -f $_.LastModified, $_.DaysOld, $_.FullPath) -ForegroundColor Yellow
        }

        $files | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
        Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
    } else {
        Write-Log "No files older than $days days; no CSV report generated." "Gray"
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
