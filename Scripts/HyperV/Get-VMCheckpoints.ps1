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

$getParams = @{ ErrorAction = "Stop" }
if (-not [string]::IsNullOrEmpty($VMName))       { $getParams["VMName"]       = $VMName }
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
Write-Host ("  {0,-28} {1,-24} {2,-18} {3}" -f "VM Name", "Checkpoint", "Created", "Age") -ForegroundColor DarkGray
Write-Host ("  " + ("-" * 85)) -ForegroundColor DarkGray

$now    = Get-Date
$report = foreach ($s in $snapshots | Sort-Object VMName, CreationTime) {
    $ageDays = [math]::Round(($now - $s.CreationTime).TotalDays, 1)
    $ageStr  = if ($ageDays -lt 1) { "< 1 day" } elseif ($ageDays -lt 2) { "1 day" } else { "$ageDays days" }
    $color   = if ($ageDays -gt 30) { "Yellow" } elseif ($ageDays -gt 7) { "White" } else { "Green" }

    Write-Host ("  {0,-28} {1,-24} {2,-18} {3}" -f `
        $s.VMName,
        ($s.Name.Substring(0, [Math]::Min(22, $s.Name.Length))),
        $s.CreationTime.ToString("yyyy-MM-dd HH:mm"),
        $ageStr) -ForegroundColor $color

    [PSCustomObject]@{
        VMName          = $s.VMName
        CheckpointName  = $s.Name
        Created         = $s.CreationTime
        AgeDays         = $ageDays
        SnapshotType    = $s.SnapshotType
        ParentCheckpoint = $s.ParentSnapshotName
    }
}

Write-Host ""
$old = @($report | Where-Object { $_.AgeDays -gt 30 }).Count
if ($old -gt 0) { Write-Log "$old checkpoint(s) older than 30 days — consider removing." "Yellow" }

$report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
