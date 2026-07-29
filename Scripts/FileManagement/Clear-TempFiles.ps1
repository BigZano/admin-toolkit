# Clean temp folders and report space freed (dry-run by default)

param(
    [Parameter(Mandatory=$false)]
    [string]$DryRun = "true",
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
$outputFile = Join-Path $OutputDirectory "Clear-TempFiles_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Clear-TempFiles_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$dryRunFlag = $DryRun -match '^(?i)(true|yes|1)$'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$targets = @($env:TEMP)
if ($isAdmin) {
    $targets += "C:\Windows\Temp"
} else {
    Write-Log "Not elevated - skipping C:\Windows\Temp (run as Administrator to include it)." "Yellow"
}

if ($dryRunFlag) {
    Write-Log "DRY RUN - no files will be deleted. Set DryRun=false to actually clean." "Yellow"
} else {
    Write-Log "LIVE RUN - deleting temp files..." "Cyan"
}

$results      = @()
$totalFreed   = [long]0
$totalSkipped = 0

foreach ($folder in $targets) {
    if (-not (Test-Path $folder)) {
        Write-Log "Folder not found, skipping: $folder" "Yellow"
        continue
    }

    Write-Log "Processing: $folder" "Cyan"
    $files = Get-ChildItem -Path $folder -Recurse -File -Force -ErrorAction SilentlyContinue

    $folderBytes   = [long]0
    $folderFreed   = [long]0
    $folderSkipped = 0
    $fileCount     = 0

    foreach ($file in $files) {
        $fileCount++
        $folderBytes += $file.Length
        if (-not $dryRunFlag) {
            try {
                Remove-Item -Path $file.FullName -Force -Confirm:$false -ErrorAction Stop
                $folderFreed += $file.Length
            } catch {
                $folderSkipped++
            }
        }
    }

    # Sweep now-empty directories on live runs (best effort)
    if (-not $dryRunFlag) {
        Get-ChildItem -Path $folder -Recurse -Directory -Force -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending |
            ForEach-Object { Remove-Item -Path $_.FullName -Force -Confirm:$false -ErrorAction SilentlyContinue }
    }

    $sizeMB  = [math]::Round($folderBytes / 1MB, 2)
    $freedMB = [math]::Round($folderFreed / 1MB, 2)

    if ($dryRunFlag) {
        Write-Log "  $fileCount file(s), would free $sizeMB MB" "Yellow"
    } else {
        Write-Log "  Freed $freedMB MB; $folderSkipped file(s) skipped (in use/locked)" "Green"
    }

    $results += [PSCustomObject]@{
        Folder       = $folder
        Files        = $fileCount
        TotalMB      = $sizeMB
        FreedMB      = if ($dryRunFlag) { 0 } else { $freedMB }
        SkippedFiles = $folderSkipped
        Mode         = if ($dryRunFlag) { "DryRun" } else { "Deleted" }
    }

    $totalFreed   += if ($dryRunFlag) { $folderBytes } else { $folderFreed }
    $totalSkipped += $folderSkipped
}

$results | Export-Csv -Path $outputFile -NoTypeInformation
$results | Format-Table -AutoSize

$totalMB = [math]::Round($totalFreed / 1MB, 2)
if ($dryRunFlag) {
    Write-Log "DRY RUN complete: would free approximately $totalMB MB." "Yellow"
} else {
    Write-Log "Cleanup complete: freed $totalMB MB; $totalSkipped file(s) skipped (locked/in use)." "Green"
}
Write-Log "Report saved: $outputFile" "Green"
