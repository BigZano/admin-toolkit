# Audit permissions on all Group Policy Objects in the domain

param(
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
$outputFile = Join-Path $OutputDirectory "GPOPermissions_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "GPOPermissions_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module GroupPolicy -ErrorAction Stop
} catch {
    Write-Log "GroupPolicy module not found. Install RSAT: Group Policy Management Tools." "Red"
    exit 1
}

Write-Log "Auditing GPO permissions across the domain..." "Cyan"

try {
    $allGPOs = Get-GPO -All | Sort-Object DisplayName
    Write-Log "Processing $($allGPOs.Count) GPOs..." "Cyan"

    $report = foreach ($gpo in $allGPOs) {
        $permissions = Get-GPPermission -Guid $gpo.Id -All -ErrorAction SilentlyContinue
        foreach ($perm in $permissions) {
            [PSCustomObject]@{
                GPOName     = $gpo.DisplayName
                Trustee     = $perm.Trustee.Name
                TrusteeType = $perm.Trustee.SidType
                Permission  = $perm.Permission
                Denied      = $perm.Denied
            }
        }
    }

    $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Log "Full permissions report saved to: $outputFile" "Green"

    # Highlight non-standard edit rights
    $editRights = @($report | Where-Object {
        $_.Permission -in @("GpoEditDeleteModifySecurity", "GpoEdit", "GpoCustom") -and
        $_.Trustee -notin @("Domain Admins", "Enterprise Admins", "SYSTEM", "Group Policy Creator Owners")
    })

    Write-Host ""
    if ($editRights.Count -gt 0) {
        Write-Host "  Non-standard GPO edit permissions (review these):" -ForegroundColor Yellow
        $editRights | ForEach-Object {
            Write-Host ("  {0,-45} Trustee: {1,-25} [{2}]" -f $_.GPOName, $_.Trustee, $_.Permission) -ForegroundColor Yellow
        }
    } else {
        Write-Log "No non-standard edit permissions found." "Green"
    }

    # Summary by GPO
    Write-Host ""
    Write-Host "  Permission summary per GPO:" -ForegroundColor DarkGray
    $allGPOs | ForEach-Object {
        $gpoName = $_.DisplayName
        $permCount = ($report | Where-Object { $_.GPOName -eq $gpoName }).Count
        Write-Host ("  {0,-50} {1} entries" -f $gpoName, $permCount) -ForegroundColor Gray
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"
    exit 1
}
