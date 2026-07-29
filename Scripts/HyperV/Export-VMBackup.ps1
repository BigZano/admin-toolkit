# Export a Hyper-V VM to a folder for offline backup or migration

param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    [Parameter(Mandatory=$true)]
    [string]$ExportPath,
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = ""
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "  $(Get-Date -Format 'HH:mm:ss')  $Message" -ForegroundColor $Color
}

# Hyper-V queries silently return no results without elevation, so fail loudly instead.
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "This script requires an elevated (Administrator) session — Hyper-V cmdlets return empty results without it." "Red"
    exit 1
}

$isRemote = -not [string]::IsNullOrEmpty($ComputerName)

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host "  VM:          $VMName" -ForegroundColor Yellow
Write-Host "  Export path: $ExportPath$(if ($isRemote) { "  (resolved on $ComputerName)" })" -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""

$getParams = @{ Name = $VMName; ErrorAction = "Stop" }
if (-not [string]::IsNullOrEmpty($ComputerName)) { $getParams["ComputerName"] = $ComputerName }

try {
    $vm = Get-VM @getParams
} catch {
    Write-Log "VM '$VMName' not found: $($_.Exception.Message)" "Red"; exit 1
}

# Hyper-V supports live (online) export of running VMs since Server 2012 R2.
if ($vm.State -eq "Running") {
    Write-Log "VM is running — Hyper-V will perform a live (online) export." "Cyan"
}

if ($isRemote) {
    # The export path is created and written by the Hyper-V service on the remote host;
    # do not create directories or measure sizes locally.
    Write-Log "Remote export: ensure '$ExportPath' exists and has enough free space on $ComputerName." "Yellow"
} else {
    if (-not (Test-Path $ExportPath)) {
        try {
            New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
            Write-Log "Created export directory: $ExportPath" "Cyan"
        } catch {
            Write-Log "Cannot create export path: $($_.Exception.Message)" "Red"; exit 1
        }
    }

    # Destination free-space check: exports need at least the size of the VM's disks.
    try {
        $neededBytes = ($vm.HardDrives.Path | Where-Object { $_ -and (Test-Path $_) } |
            Get-Item -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $root = [System.IO.Path]::GetPathRoot((Resolve-Path $ExportPath).Path)
        $freeBytes = ([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.Name -eq $root }).AvailableFreeSpace
        if ($neededBytes -and $freeBytes -and $freeBytes -lt $neededBytes) {
            Write-Log ("Insufficient free space on {0}: need ~{1} GB, only {2} GB free." -f `
                $root, [math]::Round($neededBytes / 1GB, 1), [math]::Round($freeBytes / 1GB, 1)) "Red"
            exit 1
        }
    } catch {
        Write-Log "Could not verify destination free space: $($_.Exception.Message)" "Yellow"
    }
}

Write-Log "Starting export — this may take several minutes..." "Cyan"
$start = Get-Date

try {
    $exportParams = @{ Name = $VMName; Path = $ExportPath; ErrorAction = "Stop" }
    if (-not [string]::IsNullOrEmpty($ComputerName)) { $exportParams["ComputerName"] = $ComputerName }
    Export-VM @exportParams
} catch {
    Write-Log "Export failed: $($_.Exception.Message)" "Red"; exit 1
}

$elapsed  = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
$destDir  = Join-Path $ExportPath $VMName
$sizeGB   = if (-not $isRemote -and (Test-Path $destDir)) {
    [math]::Round((Get-ChildItem $destDir -Recurse -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum / 1GB, 2)
} else { "?" }

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host "  EXPORT COMPLETE" -ForegroundColor Green
Write-Host ("  {0,-20} {1}" -f "VM:", $VMName) -ForegroundColor White
Write-Host ("  {0,-20} {1}" -f "Destination:", "$destDir$(if ($isRemote) { "  (on $ComputerName)" })") -ForegroundColor White
Write-Host ("  {0,-20} {1} GB" -f "Size on disk:", $sizeGB) -ForegroundColor White
Write-Host ("  {0,-20} {1} seconds" -f "Duration:", $elapsed) -ForegroundColor White
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""
