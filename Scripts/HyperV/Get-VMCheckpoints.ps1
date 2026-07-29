# List all checkpoints across Hyper-V VMs with age and disk size

param(
    [Parameter(Mandatory=$false)]
    [string]$VMName = "",
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = Join-Path $env:USERPROFILE "Documents\AdminToolReports"
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "VMCheckpoints_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "VMCheckpoints_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

# Hyper-V queries silently return no results without elevation, so fail loudly instead.
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "This script requires an elevated (Administrator) session — Hyper-V cmdlets return empty results without it." "Red"
    exit 1
}

# Get-VMSnapshot's -VMName is mandatory; default to "*" so a blank VMName means "all VMs"
# instead of an interactive prompt (fatal under -NonInteractive).
$getParams = @{ ErrorAction = "Stop" }
$getParams["VMName"] = if (-not [string]::IsNullOrEmpty($VMName)) { $VMName } else { "*" }
if (-not [string]::IsNullOrEmpty($ComputerName)) { $getParams["ComputerName"] = $ComputerName }

try {
    $snapshots = Get-VMSnapshot @getParams
} catch {
    Write-Log "Failed to retrieve checkpoints: $($_.Exception.Message)" "Red"; exit 1
}

if (-not $snapshots -or @($snapshots).Count -eq 0) {
    Write-Log "No checkpoints found." "Yellow"; exit 0
}

Write-Log "Found $(@($snapshots).Count) checkpoint(s)" "Cyan"
Write-Host ""
Write-Host ("  {0,-28} {1,-24} {2,-18} {3,-10} {4}" -f "VM Name", "Checkpoint", "Created", "Age", "Size") -ForegroundColor DarkGray
Write-Host ("  " + ("-" * 95)) -ForegroundColor DarkGray

$now    = Get-Date
$report = foreach ($s in $snapshots | Sort-Object VMName, CreationTime) {
    $ageDays = [math]::Round(($now - $s.CreationTime).TotalDays, 1)
    $ageStr  = if ($ageDays -lt 1) { "< 1 day" } elseif ($ageDays -lt 2) { "1 day" } else { "$ageDays days" }
    $color   = if ($ageDays -gt 30) { "Yellow" } elseif ($ageDays -gt 7) { "White" } else { "Green" }

    # On-disk size of the checkpoint's differencing disks (local host only).
    $sizeMB = $null
    if ([string]::IsNullOrEmpty($ComputerName) -and $s.HardDrives) {
        try {
            $bytes = ($s.HardDrives.Path | Where-Object { $_ -and (Test-Path $_) } |
                Get-Item -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            if ($bytes) { $sizeMB = [math]::Round($bytes / 1MB, 0) }
        } catch { }
    }
    $sizeStr = if ($null -ne $sizeMB) { "$sizeMB MB" } else { "-" }

    Write-Host ("  {0,-28} {1,-24} {2,-18} {3,-10} {4}" -f `
        $s.VMName,
        ($s.Name.Substring(0, [Math]::Min(22, $s.Name.Length))),
        $s.CreationTime.ToString("yyyy-MM-dd HH:mm"),
        $ageStr, $sizeStr) -ForegroundColor $color

    [PSCustomObject]@{
        VMName          = $s.VMName
        CheckpointName  = $s.Name
        Created         = $s.CreationTime
        AgeDays         = $ageDays
        SizeMB          = $sizeMB
        SnapshotType    = $s.SnapshotType
        ParentCheckpoint = $s.ParentSnapshotName
    }
}

Write-Host ""
$old = @($report | Where-Object { $_.AgeDays -gt 30 }).Count
if ($old -gt 0) { Write-Log "$old checkpoint(s) older than 30 days — consider removing." "Yellow" }

$report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
