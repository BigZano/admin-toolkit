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

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "FolderSizes_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "FolderSizes_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

# NOTE: PowerShell variables are case-insensitive, so the parsed value needs a
# name distinct from the $Depth parameter
$parsedDepth = 0
if (-not [int]::TryParse($Depth, [ref]$parsedDepth) -or $parsedDepth -lt 1) {
    Write-Log "Invalid Depth value: '$Depth' (expected an integer >= 1)" "Red"; exit 1
}
$depth = $parsedDepth

$script:SkippedItems = 0

function Get-FolderSize {
    param([string]$FolderPath)
    $errs = $null
    $size = (Get-ChildItem -LiteralPath $FolderPath -Recurse -File -ErrorAction SilentlyContinue -ErrorVariable errs |
        Measure-Object -Property Length -Sum).Sum
    $script:SkippedItems += @($errs).Count
    if ($size) { return $size } else { return 0 }
}

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Log "Path not found: $Path" "Red"; exit 1
}

Write-Log "Calculating folder sizes in: $Path  (depth: $depth)" "Cyan"
Write-Log "Large directory trees may take several minutes..." "DarkGray"

try {
    $folders = Get-ChildItem -LiteralPath $Path -Directory -Depth ($depth - 1) -ErrorAction SilentlyContinue |
        Sort-Object FullName

    Write-Log "Processing $($folders.Count) folders..." "Cyan"

    $sizeByPath = @{}
    $report = $folders | ForEach-Object {
        $sizeBytes = Get-FolderSize -FolderPath $_.FullName
        $sizeByPath[$_.FullName] = $sizeBytes
        [PSCustomObject]@{
            SizeGB       = [math]::Round($sizeBytes / 1GB, 3)
            SizeMB       = [math]::Round($sizeBytes / 1MB, 1)
            FolderName   = $_.Name
            LastModified = $_.LastWriteTime.ToString("yyyy-MM-dd")
            FullPath     = $_.FullName
        }
    } | Sort-Object SizeGB -Descending

    # Root total = sum of top-level subfolder sizes + files directly in the root.
    # (Avoids re-walking the entire tree a second time.)
    $rootItem = Get-Item -LiteralPath $Path
    $rootFilesSum = (Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if (-not $rootFilesSum) { $rootFilesSum = 0 }
    $childSum = ($folders | Where-Object { $_.Parent.FullName -eq $rootItem.FullName } |
        ForEach-Object { $sizeByPath[$_.FullName] } | Measure-Object -Sum).Sum
    if (-not $childSum) { $childSum = 0 }
    $rootSize = $childSum + $rootFilesSum

    Write-Host ""
    Write-Host ("  Root total: {0:N2} GB  ({1})" -f ($rootSize / 1GB), $Path) -ForegroundColor Cyan
    Write-Host ""

    $report | ForEach-Object {
        $bar = "#" * [math]::Min([int]($_.SizeGB * 4), 40)
        $color = if ($_.SizeGB -ge 10) { "Red" } elseif ($_.SizeGB -ge 1) { "Yellow" } else { "Gray" }
        Write-Host ("  {0,8:N2} GB  {1,-35} {2}" -f $_.SizeGB, $_.FolderName, $bar) -ForegroundColor $color
    }

    if ($script:SkippedItems -gt 0) { Write-Log "Skipped $($script:SkippedItems) inaccessible item(s)" "Yellow" }

    if ($report) {
        $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
        Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
    } else {
        Write-Log "No subfolders found; no CSV report generated." "Gray"
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
