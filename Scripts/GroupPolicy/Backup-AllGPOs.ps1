# Back up all GPOs in the domain to a dated folder

param(
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
$outputFile = Join-Path $OutputDirectory "GPOBackupManifest_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "GPOBackup_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module GroupPolicy -ErrorAction Stop
} catch {
    Write-Log "GroupPolicy module not available. Install RSAT (Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0)." "Red"
    exit 1
}

$backupDir = Join-Path $OutputDirectory "GPOBackup_$timestamp"
New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
Write-Log "Backing up all GPOs to: $backupDir" "Cyan"

try {
    $gpos = @(Get-GPO -All -ErrorAction Stop)
} catch {
    Write-Log "Error enumerating GPOs: $($_.Exception.Message)" "Red"
    exit 1
}

Write-Log "Found $($gpos.Count) GPOs to back up." "Cyan"

$manifest  = @()
$failCount = 0

foreach ($gpo in $gpos) {
    try {
        $backup = Backup-GPO -Guid $gpo.Id -Path $backupDir -ErrorAction Stop
        $manifest += [PSCustomObject]@{
            DisplayName    = $gpo.DisplayName
            GpoId          = $gpo.Id
            BackupId       = $backup.Id
            BackupTime     = $backup.Timestamp
            GpoStatus      = $gpo.GpoStatus
            ModifiedTime   = $gpo.ModificationTime
            Result         = "Success"
        }
        Write-Log "Backed up: $($gpo.DisplayName)" "Green"
    } catch {
        $failCount++
        $manifest += [PSCustomObject]@{
            DisplayName    = $gpo.DisplayName
            GpoId          = $gpo.Id
            BackupId       = ""
            BackupTime     = ""
            GpoStatus      = $gpo.GpoStatus
            ModifiedTime   = $gpo.ModificationTime
            Result         = "FAILED: $($_.Exception.Message)"
        }
        Write-Log "FAILED to back up: $($gpo.DisplayName) - $($_.Exception.Message)" "Red"
    }
}

$manifest | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host ""
$manifest | Format-Table DisplayName, BackupId, Result -AutoSize | Out-String | Write-Host
$successCount = $gpos.Count - $failCount
Write-Log "Backup complete: $successCount succeeded, $failCount failed, of $($gpos.Count) GPOs." $(if ($failCount -gt 0) { "Yellow" } else { "Green" })
Write-Log "Backup folder: $backupDir" "Green"
Write-Log "Report saved: $outputFile" "Green"

if ($successCount -eq 0 -and $gpos.Count -gt 0) {
    exit 1
}
