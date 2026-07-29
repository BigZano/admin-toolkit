# Gracefully shut down or force-off one or more Hyper-V VMs

param(
    [Parameter(Mandatory=$false)]
    [string]$VMName = "",
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
    [Parameter(Mandatory=$false)]
    [string]$Force = "false"
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "  $(Get-Date -Format 'HH:mm:ss')  $Message" -ForegroundColor $Color
}

$forceStop = $Force -eq "true" -or $Force -eq "1"

# Hyper-V queries silently return no results without elevation, so fail loudly instead.
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "This script requires an elevated (Administrator) session — Hyper-V cmdlets return empty results without it." "Red"
    exit 1
}

# Refuse to mass-shutdown by accident: an empty VMName no longer means "all VMs".
if ([string]::IsNullOrEmpty($VMName)) {
    Write-Log "No VM specified. Pass VM name(s) (comma-separated), or the literal word ALL to shut down every running VM." "Red"
    exit 1
}

$getParams = @{ ErrorAction = "Stop" }
if (-not [string]::IsNullOrEmpty($ComputerName)) { $getParams["ComputerName"] = $ComputerName }

try {
    $allVMs = Get-VM @getParams
} catch {
    Write-Log "Failed to connect to Hyper-V: $($_.Exception.Message)" "Red"; exit 1
}

if ($VMName -eq "ALL") {
    $targets = @($allVMs | Where-Object { $_.State -eq "Running" })
    if ($targets.Count -eq 0) {
        Write-Log "No running VMs found to stop." "Yellow"; exit 0
    }
} else {
    $names   = $VMName -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $targets = @($allVMs | Where-Object { $names -contains $_.Name })
    $missing = @($names | Where-Object { $targets.Name -notcontains $_ })
    if ($missing.Count -gt 0) {
        Write-Log "Requested VM(s) not found on this host: $($missing -join ', ')" "Yellow"
    }
    if ($targets.Count -eq 0) {
        Write-Log "None of the requested VMs exist — nothing stopped." "Red"; exit 1
    }
}

$method = if ($forceStop) { "FORCE-OFF" } else { "Graceful Shutdown" }

Write-Host ""
Write-Host ("=" * 55) -ForegroundColor DarkGray
Write-Host "  Stopping $(@($targets).Count) VM(s) — $method" -ForegroundColor Yellow
Write-Host ("=" * 55) -ForegroundColor DarkGray
Write-Host ""

$stopped = 0; $failed = 0
foreach ($vm in $targets | Sort-Object Name) {
    if ($vm.State -eq "Off") {
        Write-Log "$($vm.Name) is already off — skipped." "DarkGray"
        continue
    }
    Write-Log "Stopping: $($vm.Name)  [currently: $($vm.State)]" "Cyan"
    try {
        # -Force suppresses the unsaved-data prompt (fatal under -NonInteractive); shutdown is still graceful.
        $stopParams = @{ Name = $vm.Name; Force = $true; ErrorAction = "Stop" }
        if (-not [string]::IsNullOrEmpty($ComputerName)) { $stopParams["ComputerName"] = $ComputerName }
        if ($forceStop) { $stopParams["TurnOff"] = $true }
        Stop-VM @stopParams
        Write-Log "  Stopped OK." "Green"
        $stopped++
    } catch {
        Write-Log "  Failed: $($_.Exception.Message)" "Red"
        $failed++
    }
}

Write-Host ""
Write-Host ("=" * 55) -ForegroundColor DarkGray
$color = if ($failed -gt 0) { "Yellow" } else { "Green" }
Write-Host ("  Stopped: $stopped  |  Failed: $failed") -ForegroundColor $color
Write-Host ("=" * 55) -ForegroundColor DarkGray
Write-Host ""

if ($failed -gt 0) { exit 1 }
