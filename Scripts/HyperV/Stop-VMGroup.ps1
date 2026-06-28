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

$getParams = @{ ErrorAction = "Stop" }
if (-not [string]::IsNullOrEmpty($ComputerName)) { $getParams["ComputerName"] = $ComputerName }

try {
    $allVMs = Get-VM @getParams
} catch {
    Write-Log "Failed to connect to Hyper-V: $($_.Exception.Message)" "Red"; exit 1
}

$targets = if (-not [string]::IsNullOrEmpty($VMName)) {
    $names = $VMName -split ',' | ForEach-Object { $_.Trim() }
    $allVMs | Where-Object { $names -contains $_.Name }
} else {
    $allVMs | Where-Object { $_.State -eq "Running" }
}

if (-not $targets -or @($targets).Count -eq 0) {
    Write-Log "No running VMs found to stop." "Yellow"; exit 0
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
        $stopParams = @{ Name = $vm.Name; ErrorAction = "Stop" }
        if (-not [string]::IsNullOrEmpty($ComputerName)) { $stopParams["ComputerName"] = $ComputerName }
        if ($forceStop) {
            $stopParams["Force"] = $true
            $stopParams["TurnOff"] = $true
        }
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
