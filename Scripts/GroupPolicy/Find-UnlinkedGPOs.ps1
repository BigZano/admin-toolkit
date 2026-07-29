# Find Group Policy Objects that are not linked to any site, domain, or OU

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

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "UnlinkedGPOs_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "UnlinkedGPOs_$timestamp.log"

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

Write-Log "Scanning all GPOs for link status..." "Cyan"

try {
    $allGPOs = Get-GPO -All
    Write-Log "Total GPOs found: $($allGPOs.Count)" "Cyan"

    $unlinked = $allGPOs | ForEach-Object {
        $gpo = $_
        try {
            $xmlReport = [xml](Get-GPOReport -Guid $gpo.Id -ReportType XML -ErrorAction Stop)
            $links = $xmlReport.GPO.LinksTo

            if (-not $links) {
                [PSCustomObject]@{
                    Name             = $gpo.DisplayName
                    Status           = $gpo.GpoStatus
                    CreationTime     = $gpo.CreationTime.ToString("yyyy-MM-dd")
                    ModificationTime = $gpo.ModificationTime.ToString("yyyy-MM-dd HH:mm")
                    GUID             = $gpo.Id
                }
            }
        } catch {
            Write-Log "Warning: Could not read XML report for '$($gpo.DisplayName)': $($_.Exception.Message)" "Yellow"
        }
    } | Where-Object { $_ -ne $null } | Sort-Object Name

    Write-Log "Unlinked GPOs: $($unlinked.Count) of $($allGPOs.Count)" "$(if ($unlinked.Count -gt 0) { 'Yellow' } else { 'Green' })"
    Write-Log "NOTE: GPO XML reports do not include AD *site* links. A GPO linked only to a site will appear here as unlinked - verify in GPMC before deleting." "Yellow"

    if ($unlinked.Count -gt 0) {
        $unlinked | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
        Write-Log "Report saved to: $outputFile" "Green"

        Write-Host ""
        Write-Host "  Unlinked GPOs (candidates for cleanup - verify site links first):" -ForegroundColor Yellow
        $unlinked | ForEach-Object {
            Write-Host ("  {0,-50} Status: {1}" -f $_.Name, $_.Status) -ForegroundColor Yellow
            Write-Host ("  {0,-50} Modified: {1}" -f "", $_.ModificationTime) -ForegroundColor DarkGray
        }
    } else {
        Write-Log "All GPOs are linked. No cleanup needed." "Green"
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"
    exit 1
}
