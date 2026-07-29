# Show domain controllers, FSMO role holders, and functional levels

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
$outputFile = Join-Path $OutputDirectory "DomainInfo_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "DomainInfo_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Log "ActiveDirectory module not available. Install RSAT (Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0)." "Red"
    exit 1
}

try {
    $forest = Get-ADForest -ErrorAction Stop
    $domain = Get-ADDomain -ErrorAction Stop
} catch {
    Write-Log "Error querying forest/domain: $($_.Exception.Message)" "Red"
    exit 1
}

Write-Host ""
Write-Log "=== Forest / Domain ===" "Cyan"
Write-Log "Forest:                  $($forest.Name)"
Write-Log "Forest Functional Level: $($forest.ForestMode)"
Write-Log "Domain:                  $($domain.DNSRoot) (NetBIOS: $($domain.NetBIOSName))"
Write-Log "Domain Functional Level: $($domain.DomainMode)"

Write-Host ""
Write-Log "=== FSMO Role Holders ===" "Cyan"
Write-Log "Schema Master:         $($forest.SchemaMaster)"
Write-Log "Domain Naming Master:  $($forest.DomainNamingMaster)"
Write-Log "PDC Emulator:          $($domain.PDCEmulator)"
Write-Log "RID Master:            $($domain.RIDMaster)"
Write-Log "Infrastructure Master: $($domain.InfrastructureMaster)"

Write-Host ""
Write-Log "=== Domain Controllers ===" "Cyan"

$dcResults = @()
$skipCount = 0
try {
    $dcs = Get-ADDomainController -Filter * -ErrorAction Stop
    foreach ($dc in $dcs) {
        try {
            $dcResults += [PSCustomObject]@{
                Name            = $dc.Name
                IPAddress       = $dc.IPv4Address
                Site            = $dc.Site
                GlobalCatalog   = $dc.IsGlobalCatalog
                ReadOnly        = $dc.IsReadOnly
                OperatingSystem = $dc.OperatingSystem
            }
        } catch {
            $skipCount++
            Write-Log "Skipped DC $($dc.Name): $($_.Exception.Message)" "Yellow"
        }
    }
} catch {
    Write-Log "Error enumerating domain controllers: $($_.Exception.Message)" "Red"
    exit 1
}

if ($dcResults.Count -gt 0) {
    $dcResults | Format-Table Name, IPAddress, Site, GlobalCatalog, ReadOnly, OperatingSystem -AutoSize | Out-String | Write-Host
}

# CSV: one row per DC, plus forest/domain/FSMO context on each row
$csvRows = foreach ($dc in $dcResults) {
    [PSCustomObject]@{
        Forest                = $forest.Name
        ForestFunctionalLevel = $forest.ForestMode
        Domain                = $domain.DNSRoot
        DomainFunctionalLevel = $domain.DomainMode
        SchemaMaster          = $forest.SchemaMaster
        DomainNamingMaster    = $forest.DomainNamingMaster
        PDCEmulator           = $domain.PDCEmulator
        RIDMaster             = $domain.RIDMaster
        InfrastructureMaster  = $domain.InfrastructureMaster
        DCName                = $dc.Name
        DCIPAddress           = $dc.IPAddress
        DCSite                = $dc.Site
        DCGlobalCatalog       = $dc.GlobalCatalog
        DCReadOnly            = $dc.ReadOnly
        DCOperatingSystem     = $dc.OperatingSystem
    }
}
@($csvRows) | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Log "Domain controllers: $($dcResults.Count)" "Green"
if ($skipCount -gt 0) {
    Write-Log "DCs skipped due to errors: $skipCount" "Yellow"
}
Write-Log "Report saved: $outputFile" "Green"
