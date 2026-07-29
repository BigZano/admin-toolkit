# Check Hyper-V Replica replication health, lag, and last sync time for all VMs

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
$outputFile = Join-Path $OutputDirectory "VMReplication_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "VMReplication_$timestamp.log"

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

$getParams = @{ ErrorAction = "Stop" }
if (-not [string]::IsNullOrEmpty($ComputerName)) { $getParams["ComputerName"] = $ComputerName }
if (-not [string]::IsNullOrEmpty($VMName))       { $getParams["VMName"]       = $VMName }

try {
    $replicas = Get-VMReplication @getParams
} catch {
    Write-Log "Failed to retrieve replication info: $($_.Exception.Message)" "Red"; exit 1
}

if (-not $replicas -or @($replicas).Count -eq 0) {
    Write-Log "No VMs with Hyper-V Replica configured." "Yellow"; exit 0
}

# Get-VMReplication returns settings; per-VM statistics (last replication time, errors)
# come from Measure-VMReplication.
$statsByVM = @{}
try {
    foreach ($st in @(Measure-VMReplication @getParams)) { $statsByVM[$st.VMName] = $st }
} catch {
    Write-Log "Could not retrieve replication statistics: $($_.Exception.Message)" "Yellow"
}

Write-Log "Found $(@($replicas).Count) replicated VM(s)" "Cyan"
Write-Host ""
Write-Host ("  {0,-28} {1,-10} {2,-14} {3,-24} {4}" -f "VM", "Mode", "Health", "Last Replicated", "Replica Server") -ForegroundColor DarkGray
Write-Host ("  " + ("-" * 95)) -ForegroundColor DarkGray

$report = foreach ($r in $replicas | Sort-Object VMName) {
    $st       = $statsByVM[$r.VMName]
    $lastRepl = if ($st) { $st.LastReplicationTime } else { $null }
    $health   = if ($st -and $st.Health) { $st.Health } else { $r.Health }
    $lastSync = if ($lastRepl) { $lastRepl.ToString("yyyy-MM-dd HH:mm") } else { "Never" }
    $lagMin   = if ($lastRepl) { [math]::Round(((Get-Date) - $lastRepl).TotalMinutes, 0) } else { -1 }
    $color    = switch ("$health") {
        "Normal"   { "Green" }
        "Warning"  { "Yellow" }
        "Critical" { "Red" }
        default    { "White" }
    }

    Write-Host ("  {0,-28} {1,-10} {2,-14} {3,-24} {4}" -f `
        $r.VMName, $r.Mode, $health, $lastSync, $r.ReplicaServerName) -ForegroundColor $color

    [PSCustomObject]@{
        VMName            = $r.VMName
        Mode              = $r.Mode
        Health            = $health
        State             = $r.State
        ReplicaServer     = $r.ReplicaServerName
        LastReplicated    = $lastSync
        LagMinutes        = if ($lagMin -ge 0) { $lagMin } else { "" }
        FrequencySec      = $r.FrequencySec
        HealthDetails     = if ($st) { @($st.ReplicationHealthDetails) -join "; " } else { "" }
        Host              = if ($ComputerName) { $ComputerName } else { $env:COMPUTERNAME }
    }
}

Write-Host ""
$critical = @($report | Where-Object { $_.Health -eq "Critical" }).Count
$warning  = @($report | Where-Object { $_.Health -eq "Warning" }).Count
$statusColor = if ($critical -gt 0) { "Red" } elseif ($warning -gt 0) { "Yellow" } else { "Green" }
Write-Log ("Normal: $(@($report | Where-Object {$_.Health -eq 'Normal'}).Count)  |  Warning: $warning  |  Critical: $critical") $statusColor

$report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
