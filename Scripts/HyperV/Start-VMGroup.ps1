# Start one or more Hyper-V VMs by name; starts all stopped VMs if no name given

param(
    [Parameter(Mandatory=$false)]
    [string]$VMName = "",
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = ""
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "  $(Get-Date -Format 'HH:mm:ss')  $Message" -ForegroundColor $Color
}

$getParams = @{ ErrorAction = "Stop" }
if (-not [string]::IsNullOrEmpty($ComputerName)) { $getParams["ComputerName"] = $ComputerName }

try {
    $allVMs = Get-VM @getParams
} catch {
    Write-Log "Failed to connect to Hyper-V: $($_.Exception.Message)" "Red"; exit 1
}

# Resolve target VMs
$targets = if (-not [string]::IsNullOrEmpty($VMName)) {
    $names = $VMName -split ',' | ForEach-Object { $_.Trim() }
    $allVMs | Where-Object { $names -contains $_.Name }
} else {
    $allVMs | Where-Object { $_.State -eq "Off" -or $_.State -eq "Saved" }
}

if (-not $targets -or @($targets).Count -eq 0) {
    Write-Log "No matching VMs found to start." "Yellow"; exit 0
}

Write-Host ""
Write-Host ("=" * 55) -ForegroundColor DarkGray
Write-Host "  Starting $(@($targets).Count) VM(s)" -ForegroundColor Yellow
Write-Host ("=" * 55) -ForegroundColor DarkGray
Write-Host ""

$started = 0; $failed = 0
foreach ($vm in $targets | Sort-Object Name) {
    if ($vm.State -eq "Running") {
        Write-Log "$($vm.Name) is already running — skipped." "DarkGray"
        continue
    }
    Write-Log "Starting: $($vm.Name)  [currently: $($vm.State)]" "Cyan"
    try {
        $startParams = @{ Name = $vm.Name; ErrorAction = "Stop" }
        if (-not [string]::IsNullOrEmpty($ComputerName)) { $startParams["ComputerName"] = $ComputerName }
        Start-VM @startParams
        Write-Log "  Started OK." "Green"
        $started++
    } catch {
        Write-Log "  Failed: $($_.Exception.Message)" "Red"
        $failed++
    }
}

Write-Host ""
Write-Host ("=" * 55) -ForegroundColor DarkGray
$color = if ($failed -gt 0) { "Yellow" } else { "Green" }
Write-Host ("  Started: $started  |  Failed: $failed") -ForegroundColor $color
Write-Host ("=" * 55) -ForegroundColor DarkGray
Write-Host ""
