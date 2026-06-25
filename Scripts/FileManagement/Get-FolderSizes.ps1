# Report folder sizes at a given depth to identify disk space usage

param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [Parameter(Mandatory=$false)]
    [string]$Depth = "1",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = if ($IsWindows -or $env:OS -match "Windows") {
        Join-Path $env:USERPROFILE "Documents\AdminToolReports"
    } else { Join-Path $env:HOME "Documents/AdminToolReports" }
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$depth     = [int]$Depth
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "FolderSizes_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "FolderSizes_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

function Get-FolderSize {
    param([string]$FolderPath)
    $size = (Get-ChildItem -Path $FolderPath -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    return if ($size) { $size } else { 0 }
}

if (-not (Test-Path $Path)) {
    Write-Log "Path not found: $Path" "Red"; exit 1
}

Write-Log "Calculating folder sizes in: $Path  (depth: $depth)" "Cyan"

try {
    $folders = Get-ChildItem -Path $Path -Directory -Depth ($depth - 1) -ErrorAction SilentlyContinue |
        Sort-Object FullName

    Write-Log "Processing $($folders.Count) folders..." "Cyan"

    $report = $folders | ForEach-Object {
        $sizeBytes = Get-FolderSize -FolderPath $_.FullName
        [PSCustomObject]@{
            SizeGB       = [math]::Round($sizeBytes / 1GB, 3)
            SizeMB       = [math]::Round($sizeBytes / 1MB, 1)
            FolderName   = $_.Name
            LastModified = $_.LastWriteTime.ToString("yyyy-MM-dd")
            FullPath     = $_.FullName
        }
    } | Sort-Object SizeGB -Descending

    # Root size
    $rootSize = Get-FolderSize -FolderPath $Path
    Write-Host ""
    Write-Host ("  Root total: {0:N2} GB  ({1})" -f ($rootSize / 1GB), $Path) -ForegroundColor Cyan
    Write-Host ""

    $report | ForEach-Object {
        $bar = "#" * [math]::Min([int]($_.SizeGB * 4), 40)
        $color = if ($_.SizeGB -ge 10) { "Red" } elseif ($_.SizeGB -ge 1) { "Yellow" } else { "Gray" }
        Write-Host ("  {0,8:N2} GB  {1,-35} {2}" -f $_.SizeGB, $_.FolderName, $bar) -ForegroundColor $color
    }

    $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
