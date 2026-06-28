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

$domain = Get-ADDomain -ErrorAction Stop
$defaultPartition = $domain.DistinguishedName

$partition = if (-not [string]::IsNullOrEmpty($Partition)) { $Partition } else { $defaultPartition }

# Get DCs to sync
$dcs = if (-not [string]::IsNullOrEmpty($TargetDC)) {
    @(Get-ADDomainController -Identity $TargetDC -ErrorAction Stop)
} else {
    @(Get-ADDomainController -Filter * -ErrorAction Stop)
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
        $result = & repadmin /syncall $dc.Name $partition /AdeP 2>&1
        $errors = $result | Where-Object { $_ -match "error|fail|SyncAll" -and $_ -notmatch "SyncAll completed" }

        if ($errors) {
            foreach ($err in $errors) { Write-Log "  $err" "Yellow" }
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
Write-Log "Running repadmin /replsummary..." "Cyan"
$summary = & repadmin /replsummary 2>&1
$summary | ForEach-Object {
    $c = if ($_ -match "error|fail") { "Yellow" } else { "Gray" }
    Write-Host "  $_" -ForegroundColor $c
}
Write-Host ""
