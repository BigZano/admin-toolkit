# List all Hyper-V virtual machines with state, CPU usage, memory, and uptime

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
    [Parameter(Mandatory=$false)]
    [string]$VMName = "",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = Join-Path $env:USERPROFILE "Documents\AdminToolReports"
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "VMStatus_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "VMStatus_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$getParams = @{ ErrorAction = "Stop" }
if (-not [string]::IsNullOrEmpty($ComputerName)) { $getParams["ComputerName"] = $ComputerName }
if (-not [string]::IsNullOrEmpty($VMName))       { $getParams["Name"]         = $VMName }

try {
    $vms = Get-VM @getParams
} catch {
    Write-Log "Failed to retrieve VMs: $($_.Exception.Message)" "Red"; exit 1
}

if ($vms.Count -eq 0) { Write-Log "No VMs found." "Yellow"; exit 0 }

Write-Log "Found $($vms.Count) VM(s)" "Cyan"
Write-Host ""
Write-Host ("  {0,-30} {1,-12} {2,-8} {3,-12} {4}" -f "Name", "State", "CPU%", "Mem (GB)", "Uptime") -ForegroundColor DarkGray
Write-Host ("  " + ("-" * 80)) -ForegroundColor DarkGray

$report = foreach ($vm in $vms | Sort-Object Name) {
    $uptime = if ($vm.State -eq "Running" -and $vm.Uptime.TotalSeconds -gt 0) {
        "{0}d {1:D2}h {2:D2}m" -f $vm.Uptime.Days, $vm.Uptime.Hours, $vm.Uptime.Minutes
    } else { "-" }

    $memGB  = if ($vm.MemoryAssigned -gt 0) { [math]::Round($vm.MemoryAssigned / 1GB, 2) } else { 0 }
    $cpu    = if ($vm.State -eq "Running") { $vm.CPUUsage } else { 0 }

    $color = switch ($vm.State) {
        "Running"     { "Green" }
        "Off"         { "DarkGray" }
        "Saved"       { "Yellow" }
        "Paused"      { "Yellow" }
        default       { "White" }
    }

    Write-Host ("  {0,-30} {1,-12} {2,-8} {3,-12} {4}" -f $vm.Name, $vm.State, "$cpu%", "$memGB GB", $uptime) -ForegroundColor $color

    [PSCustomObject]@{
        Name            = $vm.Name
        State           = $vm.State
        CPUUsagePct     = $cpu
        MemoryGB        = $memGB
        Uptime          = $uptime
        Generation      = $vm.Generation
        ProcessorCount  = $vm.ProcessorCount
        DynamicMemory   = $vm.DynamicMemoryEnabled
        CheckpointType  = $vm.CheckpointType
        Host            = if ($ComputerName) { $ComputerName } else { $env:COMPUTERNAME }
    }
}

Write-Host ""
$running = @($report | Where-Object { $_.State -eq "Running" }).Count
$off     = @($report | Where-Object { $_.State -eq "Off" }).Count
$other   = $report.Count - $running - $off
Write-Log ("Running: $running  |  Off: $off  |  Other: $other") "Cyan"

$report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
