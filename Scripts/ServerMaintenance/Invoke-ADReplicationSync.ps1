# Force Active Directory replication sync across all domain controllers and report errors

param(
    [Parameter(Mandatory=$false)]
    [string]$TargetDC = "",
    [Parameter(Mandatory=$false)]
    [string]$Partition = ""
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "  $(Get-Date -Format 'HH:mm:ss')  $Message" -ForegroundColor $Color
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Log "ActiveDirectory module not found. Install RSAT." "Red"; exit 1
}

try {
    $domain = Get-ADDomain -ErrorAction Stop
} catch {
    Write-Log "Could not read domain information (is this machine domain-joined?): $($_.Exception.Message)" "Red"
    exit 1
}
$defaultPartition = $domain.DistinguishedName

$partition = if (-not [string]::IsNullOrEmpty($Partition)) { $Partition } else { $defaultPartition }

# Get DCs to sync
try {
    $dcs = if (-not [string]::IsNullOrEmpty($TargetDC)) {
        @(Get-ADDomainController -Identity $TargetDC -ErrorAction Stop)
    } else {
        @(Get-ADDomainController -Filter * -ErrorAction Stop)
    }
} catch {
    Write-Log "Failed to enumerate domain controllers: $($_.Exception.Message)" "Red"
    exit 1
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host "  Forcing replication for $($dcs.Count) DC(s)" -ForegroundColor Yellow
Write-Host "  Partition: $partition" -ForegroundColor Gray
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""

$synced = 0; $failed = 0
foreach ($dc in $dcs | Sort-Object Name) {
    Write-Log "Syncing: $($dc.Name) ($($dc.Site))" "Cyan"
    try {
        # Success is judged by exit code, not by parsing repadmin's (locale-dependent) text output.
        # /deP: /d = show DNs, /e = cross-site (enterprise), /P = push. /A (all partitions) was
        # dropped because it would override the explicitly passed partition.
        $result = & repadmin /syncall $dc.Name $partition /deP 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "  Sync reported errors (repadmin exit code $LASTEXITCODE):" "Yellow"
            $result | Select-Object -Last 10 | ForEach-Object { Write-Log "    $_" "Yellow" }
            $failed++
        } else {
            Write-Log "  Sync completed OK." "Green"
            $synced++
        }
    } catch {
        Write-Log "  Failed: $($_.Exception.Message)" "Red"
        $failed++
    }
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
$color = if ($failed -gt 0) { "Yellow" } else { "Green" }
Write-Host ("  Synced: $synced  |  Errors: $failed") -ForegroundColor $color
Write-Host ("=" * 60) -ForegroundColor DarkGray

# Final replication summary
Write-Host ""
if (Get-Command repadmin -ErrorAction SilentlyContinue) {
    Write-Log "Running repadmin /replsummary..." "Cyan"
    $summary = & repadmin /replsummary 2>&1
    $summary | ForEach-Object {
        $c = if ($_ -match "error|fail") { "Yellow" } else { "Gray" }
        Write-Host "  $_" -ForegroundColor $c
    }
} else {
    Write-Log "repadmin not available (RSAT AD DS tools not installed) — skipping /replsummary." "Yellow"
}
Write-Host ""

if ($failed -gt 0) { exit 1 }
