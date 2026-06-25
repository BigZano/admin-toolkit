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

$days      = [int]$DaysOld
$cutoff    = (Get-Date).AddDays(-$days)
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "OldFiles_${days}days_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "OldFiles_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

if (-not (Test-Path $Path)) {
    Write-Log "Path not found: $Path" "Red"; exit 1
}

Write-Log "Scanning for files not modified since: $($cutoff.ToString('yyyy-MM-dd'))  ($days days)" "Cyan"

try {
    $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
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
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
