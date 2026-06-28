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

Write-Log "Found $(@($replicas).Count) replicated VM(s)" "Cyan"
Write-Host ""
Write-Host ("  {0,-28} {1,-10} {2,-14} {3,-24} {4}" -f "VM", "Mode", "Health", "Last Replicated", "Replica Server") -ForegroundColor DarkGray
Write-Host ("  " + ("-" * 95)) -ForegroundColor DarkGray

$report = foreach ($r in $replicas | Sort-Object VMName) {
    $lastSync = if ($r.LastReplicationTime) { $r.LastReplicationTime.ToString("yyyy-MM-dd HH:mm") } else { "Never" }
    $lagMin   = if ($r.LastReplicationTime) { [math]::Round(((Get-Date) - $r.LastReplicationTime).TotalMinutes, 0) } else { -1 }
    $color    = switch ($r.Health) {
        "Normal"   { "Green" }
        "Warning"  { "Yellow" }
        "Critical" { "Red" }
        default    { "White" }
    }

    Write-Host ("  {0,-28} {1,-10} {2,-14} {3,-24} {4}" -f `
        $r.VMName, $r.Mode, $r.Health, $lastSync, $r.ReplicaServerName) -ForegroundColor $color

    [PSCustomObject]@{
        VMName            = $r.VMName
        Mode              = $r.Mode
        Health            = $r.Health
        State             = $r.State
        ReplicaServer     = $r.ReplicaServerName
        LastReplicated    = $lastSync
        LagMinutes        = if ($lagMin -ge 0) { $lagMin } else { "" }
        FrequencySec      = $r.ReplicationFrequencySec
        ReplicationErrors = $r.LastReplicationErrors
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
