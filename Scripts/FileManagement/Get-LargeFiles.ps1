# Find files exceeding a size threshold in a directory tree

param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [Parameter(Mandatory=$false)]
    [string]$MinSizeMB = "100",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = if ($IsWindows -or $env:OS -match "Windows") {
        Join-Path $env:USERPROFILE "Documents\AdminToolReports"
    } else { Join-Path $env:HOME "Documents/AdminToolReports" }
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$minBytes  = [double]$MinSizeMB * 1MB
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "LargeFiles_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "LargeFiles_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

if (-not (Test-Path $Path)) {
    Write-Log "Path not found: $Path" "Red"; exit 1
}

Write-Log "Scanning: $Path  (min size: ${MinSizeMB} MB)" "Cyan"

try {
    $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge $minBytes } |
        Sort-Object Length -Descending |
        ForEach-Object {
            [PSCustomObject]@{
                SizeMB       = [math]::Round($_.Length / 1MB, 2)
                Name         = $_.Name
                Extension    = $_.Extension
                LastModified = $_.LastWriteTime.ToString("yyyy-MM-dd")
                LastAccessed = $_.LastAccessTime.ToString("yyyy-MM-dd")
                FullPath     = $_.FullName
            }
        }

    Write-Log "Found $($files.Count) files >= ${MinSizeMB} MB" "$(if ($files.Count -gt 0) { 'Yellow' } else { 'Green' })"

    if ($files.Count -gt 0) {
        $totalGB = [math]::Round(($files | Measure-Object -Property SizeMB -Sum).Sum / 1024, 2)
        Write-Log "Total size: $totalGB GB" "Yellow"
        Write-Host ""

        $files | Select-Object -First 20 | ForEach-Object {
            Write-Host ("  {0,8} MB  {1}" -f $_.SizeMB, $_.FullPath) -ForegroundColor Yellow
        }
        if ($files.Count -gt 20) { Write-Host "  ... ($($files.Count - 20) more in CSV)" -ForegroundColor DarkGray }

        $files | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
        Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
