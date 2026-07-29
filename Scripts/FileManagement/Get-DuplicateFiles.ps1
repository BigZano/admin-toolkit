# Find duplicate files by size and content hash

param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [Parameter(Mandatory=$false)]
    [string]$MinSizeMB = "10",
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
$outputFile = Join-Path $OutputDirectory "Get-DuplicateFiles_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Get-DuplicateFiles_$timestamp.log"

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

$minBytes = [long]([int]$MinSizeMB) * 1MB

Write-Log "Scanning $Path for duplicate files >= $MinSizeMB MB (this may take a while)..." "Cyan"

$files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
         Where-Object { $_.Length -ge $minBytes }

Write-Log "Found $($files.Count) file(s) at or above the size threshold."

# Group by size first - only same-size files can be duplicates
$sizeGroups = $files | Group-Object Length | Where-Object { $_.Count -gt 1 }
Write-Log "Hashing $((($sizeGroups | Measure-Object -Property Count -Sum).Sum)) candidate file(s) in $($sizeGroups.Count) size group(s)..."

$hashed  = @()
$skipped = 0

foreach ($group in $sizeGroups) {
    foreach ($file in $group.Group) {
        try {
            $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            $hashed += [PSCustomObject]@{
                Hash     = $hash
                FullName = $file.FullName
                SizeMB   = [math]::Round($file.Length / 1MB, 2)
                Length   = $file.Length
            }
        } catch {
            $skipped++
            Write-Log "Could not hash: $($file.FullName) ($($_.Exception.Message))" "Yellow"
        }
    }
}

$dupGroups = $hashed | Group-Object Hash | Where-Object { $_.Count -gt 1 }

$results     = @()
$wastedBytes = [long]0
$groupNum    = 0

foreach ($group in $dupGroups) {
    $groupNum++
    $wastedBytes += ($group.Group[0].Length) * ($group.Count - 1)
    foreach ($item in $group.Group) {
        $results += [PSCustomObject]@{
            Group  = $groupNum
            SizeMB = $item.SizeMB
            File   = $item.FullName
            Hash   = $item.Hash
        }
    }
}

if ($results.Count -eq 0) {
    Write-Log "No duplicate files found ($skipped file(s) could not be read)." "Green"
    exit 0
}

$results | Export-Csv -Path $outputFile -NoTypeInformation
$results | Select-Object Group, SizeMB, File | Format-Table -AutoSize

$wastedMB = [math]::Round($wastedBytes / 1MB, 2)
Write-Log "Found $($dupGroups.Count) duplicate group(s) covering $($results.Count) file(s)." "Cyan"
Write-Log "Wasted space (duplicate copies): $wastedMB MB. Skipped (unreadable): $skipped." "Yellow"
Write-Log "Report saved: $outputFile" "Green"
