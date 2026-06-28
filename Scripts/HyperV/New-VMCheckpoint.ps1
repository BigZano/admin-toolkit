# Create a named checkpoint (snapshot) for a Hyper-V virtual machine

param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    [Parameter(Mandatory=$false)]
    [string]$CheckpointName = "",
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = ""
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "  $(Get-Date -Format 'HH:mm:ss')  $Message" -ForegroundColor $Color
}

$snapName = if (-not [string]::IsNullOrEmpty($CheckpointName)) {
    $CheckpointName
} else {
    "$VMName - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host "  VM:         $VMName" -ForegroundColor Yellow
Write-Host "  Checkpoint: $snapName" -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""

$getParams = @{ Name = $VMName; ErrorAction = "Stop" }
if (-not [string]::IsNullOrEmpty($ComputerName)) { $getParams["ComputerName"] = $ComputerName }

try {
    $vm = Get-VM @getParams
} catch {
    Write-Log "VM '$VMName' not found: $($_.Exception.Message)" "Red"; exit 1
}

Write-Log "VM state: $($vm.State)" "Cyan"

if ($vm.State -ne "Running" -and $vm.State -ne "Off" -and $vm.State -ne "Saved") {
    Write-Log "VM is in state '$($vm.State)' — cannot checkpoint now." "Yellow"; exit 1
}

Write-Log "Creating checkpoint..." "Cyan"
try {
    $cpParams = @{ VMName = $VMName; SnapshotName = $snapName; ErrorAction = "Stop" }
    if (-not [string]::IsNullOrEmpty($ComputerName)) { $cpParams["ComputerName"] = $ComputerName }
    Checkpoint-VM @cpParams
    Write-Log "Checkpoint created successfully." "Green"
} catch {
    Write-Log "Failed to create checkpoint: $($_.Exception.Message)" "Red"; exit 1
}

# Show updated checkpoint list
$listParams = @{ VMName = $VMName; ErrorAction = "SilentlyContinue" }
if (-not [string]::IsNullOrEmpty($ComputerName)) { $listParams["ComputerName"] = $ComputerName }
$checkpoints = Get-VMSnapshot @listParams | Sort-Object CreationTime

Write-Host ""
Write-Host "  Checkpoints for $VMName ($($checkpoints.Count) total):" -ForegroundColor DarkGray
foreach ($cp in $checkpoints) {
    $marker = if ($cp.Name -eq $snapName) { " <-- new" } else { "" }
    Write-Host ("    {0}  [{1}]{2}" -f $cp.Name, ($cp.CreationTime.ToString("yyyy-MM-dd HH:mm")), $marker) -ForegroundColor $(if ($marker) { "Green" } else { "Gray" })
}
Write-Host ""
