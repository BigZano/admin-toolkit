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

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "LargeFiles_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "LargeFiles_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$minSize = 0.0
if (-not [double]::TryParse($MinSizeMB, [ref]$minSize) -or $minSize -lt 0) {
    Write-Log "Invalid MinSizeMB value: '$MinSizeMB' (expected a non-negative number)" "Red"; exit 1
}
$minBytes = $minSize * 1MB

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Log "Path not found: $Path" "Red"; exit 1
}

Write-Log "Scanning: $Path  (min size: ${MinSizeMB} MB)" "Cyan"
Write-Log "Large directory trees may take several minutes..." "DarkGray"

try {
    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue -ErrorVariable scanErrors |
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

    if ($scanErrors.Count -gt 0) { Write-Log "Skipped $($scanErrors.Count) inaccessible item(s)" "Yellow" }
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
    } else {
        Write-Log "No files met the threshold; no CSV report generated." "Gray"
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
