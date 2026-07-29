# Check Active Directory replication health across all domain controllers

param(
    [Parameter(Mandatory=$false)]
    [string]$TargetDC = "",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = Join-Path $env:USERPROFILE "Documents\AdminToolReports"
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "ADReplication_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "ADReplication_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Log "ActiveDirectory module not found. Install RSAT." "Red"; exit 1
}

Write-Log "Collecting AD replication metadata..." "Cyan"

try {
    # -Scope Domain expects a domain DNS name as Target; a specific DC needs -Scope Server.
    # Target is effectively required — omitting it makes the cmdlet prompt (fatal under -NonInteractive).
    $replParams = @{ ErrorAction = "Stop" }
    if (-not [string]::IsNullOrEmpty($TargetDC)) {
        $replParams["Target"] = $TargetDC
        $replParams["Scope"]  = "Server"
    } else {
        $replParams["Target"] = (Get-ADDomain -ErrorAction Stop).DNSRoot
        $replParams["Scope"]  = "Domain"
    }
    $replStatus = Get-ADReplicationPartnerMetadata @replParams
} catch {
    Write-Log "Failed to retrieve replication data: $($_.Exception.Message)" "Red"; exit 1
}

Write-Host ""
Write-Host ("  {0,-30} {1,-30} {2,-22} {3}" -f "Source DC", "Partner DC", "Last Success", "Failures") -ForegroundColor DarkGray
Write-Host ("  " + ("-" * 95)) -ForegroundColor DarkGray

$report = foreach ($r in $replStatus | Sort-Object Server, Partner) {
    $lastOK  = if ($r.LastReplicationSuccess) { $r.LastReplicationSuccess.ToString("yyyy-MM-dd HH:mm") } else { "Never" }
    $fails   = $r.ConsecutiveReplicationFailures
    $color   = if ($fails -gt 0) { "Red" } elseif ($r.LastReplicationResult -ne 0) { "Yellow" } else { "Green" }

    $source = ($r.Server -split '\.')[0]
    $partner = ($r.Partner -replace 'CN=NTDS Settings,CN=', '' -split ',')[0]

    Write-Host ("  {0,-30} {1,-30} {2,-22} {3}" -f $source, $partner, $lastOK, $fails) -ForegroundColor $color

    [PSCustomObject]@{
        SourceDC           = $r.Server
        PartnerDC          = $partner
        LastSuccess        = $lastOK
        LastResult         = $r.LastReplicationResult
        ConsecutiveFailures = $fails
        Partition          = $r.Partition
        TransportType      = $r.TransportType
    }
}

Write-Host ""
$errors    = @($report | Where-Object { $_.LastResult -ne 0 }).Count
$consec    = @($report | Where-Object { $_.ConsecutiveFailures -gt 0 }).Count
$statColor = if ($errors -gt 0) { "Red" } elseif ($consec -gt 0) { "Yellow" } else { "Green" }
Write-Log ("Links checked: $($report.Count)  |  Errors: $errors  |  Consecutive failures: $consec") $statColor

# Also run repadmin summary if available
try {
    Write-Host ""
    if (Get-Command repadmin -ErrorAction SilentlyContinue) {
        Write-Log "Running repadmin /replsummary..." "Cyan"
        $summary = & repadmin /replsummary 2>&1
        $summary | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    } else {
        Write-Log "repadmin not available (RSAT AD DS tools not installed) — skipping /replsummary." "Yellow"
    }
} catch { }

$report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
