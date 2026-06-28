# List installed Windows Server roles and features with their status

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
    [Parameter(Mandatory=$false)]
    [string]$FilterName = "",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = Join-Path $env:USERPROFILE "Documents\AdminToolReports"
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "ServerRoles_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "ServerRoles_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$getParams = @{ ErrorAction = "Stop" }
if (-not [string]::IsNullOrEmpty($ComputerName)) { $getParams["ComputerName"] = $ComputerName }

Write-Log "Querying server roles and features..." "Cyan"

try {
    $features = Get-WindowsFeature @getParams | Where-Object { $_.InstallState -eq "Installed" }
} catch {
    Write-Log "Failed to retrieve features: $($_.Exception.Message)" "Red"; exit 1
}

if (-not [string]::IsNullOrEmpty($FilterName)) {
    $features = $features | Where-Object { $_.DisplayName -match $FilterName -or $_.Name -match $FilterName }
}

$roles        = @($features | Where-Object { $_.FeatureType -eq "Role" })
$roleServices = @($features | Where-Object { $_.FeatureType -eq "Role Service" })
$featuresList = @($features | Where-Object { $_.FeatureType -eq "Feature" })

$host_name = if (-not [string]::IsNullOrEmpty($ComputerName)) { $ComputerName } else { $env:COMPUTERNAME }

Write-Host ""
Write-Host ("  Server: $host_name") -ForegroundColor Yellow
Write-Host ""

Write-Host "  ROLES ($($roles.Count)):" -ForegroundColor Cyan
foreach ($r in $roles | Sort-Object DisplayName) {
    Write-Host ("    [+] {0}" -f $r.DisplayName) -ForegroundColor Green
}

if ($roleServices.Count -gt 0) {
    Write-Host ""
    Write-Host "  ROLE SERVICES ($($roleServices.Count)):" -ForegroundColor Cyan
    foreach ($rs in $roleServices | Sort-Object DisplayName) {
        Write-Host ("    [+] {0}  [{1}]" -f $rs.DisplayName, $rs.Name) -ForegroundColor White
    }
}

Write-Host ""
Write-Host "  FEATURES ($($featuresList.Count)):" -ForegroundColor Cyan
foreach ($f in $featuresList | Sort-Object DisplayName) {
    Write-Host ("    [+] {0}" -f $f.DisplayName) -ForegroundColor Gray
}

$report = $features | Select-Object @{N="Server";E={$host_name}}, Name, DisplayName, FeatureType, InstallState, Description

Write-Host ""
Write-Log ("Installed: $($roles.Count) role(s), $($roleServices.Count) role service(s), $($featuresList.Count) feature(s)") "Green"

$report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
