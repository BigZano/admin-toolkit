# Report M365 license SKUs with consumed vs available counts

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
$outputFile = Join-Path $OutputDirectory "LicenseReport_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "LicenseReport_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
} catch {
    Write-Log "Microsoft.Graph.Identity.DirectoryManagement module not available. Install with: Install-Module Microsoft.Graph -Scope CurrentUser" "Red"
    exit 1
}

if (-not (Get-MgContext)) {
    Write-Log "Not connected to Microsoft Graph. Opening sign-in (browser)..." "Cyan"
    try {
        Connect-MgGraph -Scopes "Organization.Read.All" -NoWelcome -ErrorAction Stop
    } catch {
        Write-Log "Failed to connect to Microsoft Graph: $($_.Exception.Message)" "Red"
        exit 1
    }
}

$skuFriendlyNames = @{
    "SPE_E3"                    = "Microsoft 365 E3"
    "SPE_E5"                    = "Microsoft 365 E5"
    "ENTERPRISEPACK"            = "Office 365 E3"
    "ENTERPRISEPREMIUM"         = "Office 365 E5"
    "EXCHANGESTANDARD"          = "Exchange Online Plan 1"
    "EXCHANGEENTERPRISE"        = "Exchange Online Plan 2"
    "O365_BUSINESS_PREMIUM"     = "M365 Business Standard"
    "O365_BUSINESS_ESSENTIALS"  = "M365 Business Basic"
    "SPB"                       = "M365 Business Premium"
    "AAD_PREMIUM"               = "Entra ID P1"
    "AAD_PREMIUM_P2"            = "Entra ID P2"
    "EMS"                       = "Enterprise Mobility + Security E3"
    "EMSPREMIUM"                = "Enterprise Mobility + Security E5"
    "POWER_BI_STANDARD"         = "Power BI Free"
    "PROJECTPROFESSIONAL"       = "Project Plan 3"
    "VISIOCLIENT"               = "Visio Plan 2"
    "DEFENDER_ENDPOINT_P1"      = "Defender for Endpoint P1"
    "ATP_ENTERPRISE"            = "Defender for Office 365 P1"
    "FLOW_FREE"                 = "Power Automate Free"
    "TEAMS_EXPLORATORY"         = "Teams Exploratory"
    "PHONESYSTEM_VIRTUALUSER"   = "Teams Phone Resource Account"
    "MCOMEETADV"                = "Audio Conferencing"
}

Write-Log "Retrieving subscribed SKUs..." "Cyan"
try {
    $skus = @(Get-MgSubscribedSku -All -ErrorAction Stop)
} catch {
    Write-Log "Error retrieving SKUs: $($_.Exception.Message)" "Red"
    exit 1
}

$results = @()
foreach ($sku in $skus) {
    try {
        $friendly  = if ($skuFriendlyNames.ContainsKey($sku.SkuPartNumber)) { $skuFriendlyNames[$sku.SkuPartNumber] } else { $sku.SkuPartNumber }
        $enabled   = $sku.PrepaidUnits.Enabled
        $consumed  = $sku.ConsumedUnits
        $available = $enabled - $consumed
        $results += [PSCustomObject]@{
            Sku          = $sku.SkuPartNumber
            FriendlyName = $friendly
            Enabled      = $enabled
            Consumed     = $consumed
            Available    = $available
            Warning      = if ($available -le 0) { "NO LICENSES AVAILABLE" } else { "" }
        }
    } catch {
        Write-Log "Skipped SKU $($sku.SkuPartNumber): $($_.Exception.Message)" "Yellow"
    }
}

$results = @($results | Sort-Object Consumed -Descending)

Write-Host ""
$results | Format-Table Sku, FriendlyName, Enabled, Consumed, Available, Warning -AutoSize | Out-String | Write-Host

$exhausted = @($results | Where-Object { $_.Available -le 0 })
foreach ($sku in $exhausted) {
    Write-Log "WARNING: $($sku.FriendlyName) ($($sku.Sku)) has no available licenses ($($sku.Consumed)/$($sku.Enabled) consumed)." "Yellow"
}

$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Log "SKUs reported: $($results.Count) (exhausted: $($exhausted.Count))" "Cyan"
Write-Log "Report saved: $outputFile" "Green"
