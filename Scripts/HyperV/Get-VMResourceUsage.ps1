# Show CPU, memory, and disk usage for running VMs

param(
    [Parameter(Mandatory=$false)]
    [string]$VMName = "",
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
$outputFile = Join-Path $OutputDirectory "Get-VMResourceUsage_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Get-VMResourceUsage_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "This script must be run as Administrator to query Hyper-V. Please relaunch the tool elevated." "Red"
    exit 1
}

try {
    Import-Module Hyper-V -ErrorAction Stop
} catch {
    Write-Log "ERROR: The Hyper-V PowerShell module is not available on this system: $($_.Exception.Message)" "Red"
    exit 1
}

Write-Log "Querying running VMs$(if ($VMName) { " matching '$VMName'" })..." "Cyan"

try {
    if ([string]::IsNullOrEmpty($VMName)) {
        $vms = @(Get-VM -ErrorAction Stop | Where-Object { $_.State -eq "Running" })
    } else {
        $vms = @(Get-VM -Name $VMName -ErrorAction Stop | Where-Object { $_.State -eq "Running" })
    }
} catch {
    Write-Log "ERROR: Could not enumerate VMs: $($_.Exception.Message)" "Red"
    exit 1
}

if ($vms.Count -eq 0) {
    Write-Log "No running VMs found$(if ($VMName) { " matching '$VMName'" })." "Yellow"
    exit 0
}

$results     = @()
$vhdSkipped  = 0

foreach ($vm in $vms) {
    $vhdFileGB = [double]0
    $vhdMaxGB  = [double]0
    foreach ($drive in $vm.HardDrives) {
        try {
            $vhd = Get-VHD -Path $drive.Path -ErrorAction Stop
            $vhdFileGB += $vhd.FileSize / 1GB
            $vhdMaxGB  += $vhd.Size / 1GB
        } catch {
            $vhdSkipped++
            Write-Log "  Could not read VHD for $($vm.Name): $($drive.Path)" "Yellow"
        }
    }

    $uptime = "{0}d {1}h {2}m" -f $vm.Uptime.Days, $vm.Uptime.Hours, $vm.Uptime.Minutes
    $row = [PSCustomObject]@{
        VMName          = $vm.Name
        CPUUsagePct     = $vm.CPUUsage
        MemAssignedGB   = [math]::Round($vm.MemoryAssigned / 1GB, 2)
        MemDemandGB     = [math]::Round($vm.MemoryDemand / 1GB, 2)
        VhdFileSizeGB   = [math]::Round($vhdFileGB, 2)
        VhdMaxSizeGB    = [math]::Round($vhdMaxGB, 2)
        Uptime          = $uptime
    }
    $results += $row

    $color = if ($vm.CPUUsage -ge 80) { "Red" } elseif ($vm.CPUUsage -ge 50) { "Yellow" } else { "Green" }
    Write-Log ("  {0,-30} CPU {1,3}%  Mem {2,7} GB  Disk {3,8}/{4} GB  up {5}" -f $vm.Name, $vm.CPUUsage, $row.MemAssignedGB, $row.VhdFileSizeGB, $row.VhdMaxSizeGB, $uptime) $color
}

$results | Export-Csv -Path $outputFile -NoTypeInformation
Write-Host ""
$results | Format-Table -AutoSize

Write-Log "Running VMs: $($results.Count); inaccessible VHDs skipped: $vhdSkipped" "Cyan"
Write-Log "Report saved: $outputFile" "Green"
