# Export a full report of all Group Policy Objects in the domain

param(
    [Parameter(Mandatory=$false)]
    [string]$ReportType = "HTML",
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
$logFile   = Join-Path $OutputDirectory "GPOReport_$timestamp.log"

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

# Validate ReportType (TUI passes free-form strings)
$type = $ReportType.ToUpper()
if ($type -notin @("HTML", "XML", "BOTH")) {
    Write-Log "Invalid ReportType '$ReportType'. Valid values: HTML, XML, BOTH." "Red"
    exit 1
}

Write-Log "Retrieving all GPOs in domain..." "Cyan"

try {
    $gpos = Get-GPO -All | Sort-Object DisplayName
    Write-Log "Found $($gpos.Count) GPOs." "Cyan"

    if ($type -eq "HTML" -or $type -eq "BOTH") {
        $htmlReport = Join-Path $OutputDirectory "GPOReport_All_$timestamp.html"
        Get-GPOReport -All -ReportType HTML -Path $htmlReport -ErrorAction Stop
        Write-Log "HTML report saved to: $htmlReport" "Green"
    }

    if ($type -eq "XML" -or $type -eq "BOTH") {
        $xmlReport = Join-Path $OutputDirectory "GPOReport_All_$timestamp.xml"
        Get-GPOReport -All -ReportType XML -Path $xmlReport -ErrorAction Stop
        Write-Log "XML report saved to: $xmlReport" "Green"
    }

    # Summary CSV
    $summaryFile = Join-Path $OutputDirectory "GPOSummary_$timestamp.csv"
    $summary = foreach ($gpo in $gpos) {
        # Property navigation is namespace-agnostic; XPath without a namespace
        # manager would silently match nothing (GPO reports use a default namespace).
        $links = @()
        try {
            $gpoXml = [xml](Get-GPOReport -Guid $gpo.Id -ReportType XML -ErrorAction Stop)
            $links = @($gpoXml.GPO.LinksTo | Where-Object { $_ } | ForEach-Object { $_.SOMPath })
        } catch {
            Write-Log "Warning: Could not read XML report for '$($gpo.DisplayName)': $($_.Exception.Message)" "Yellow"
        }
        [PSCustomObject]@{
            Name            = $gpo.DisplayName
            Status          = $gpo.GpoStatus
            CreationTime    = $gpo.CreationTime.ToString("yyyy-MM-dd")
            ModificationTime = $gpo.ModificationTime.ToString("yyyy-MM-dd HH:mm")
            WMIFilter       = if ($gpo.WmiFilter) { $gpo.WmiFilter.Name } else { "None" }
            LinkedTo        = ($links -join "; ")
        }
    }
    if ($summary) {
        $summary | Export-Csv -Path $summaryFile -NoTypeInformation -Encoding UTF8
        Write-Log "Summary CSV saved to: $summaryFile" "Green"
    } else {
        Write-Log "No GPOs found - summary CSV not written." "Yellow"
    }

    Write-Host ""
    Write-Host "  GPO Summary:" -ForegroundColor DarkGray
    $gpos | ForEach-Object {
        $statusColor = switch ($_.GpoStatus) {
            "AllSettingsEnabled"       { "Green" }
            "AllSettingsDisabled"      { "Red" }
            "UserSettingsDisabled"     { "Yellow" }
            "ComputerSettingsDisabled" { "Yellow" }
            default                    { "White" }
        }
        Write-Host ("  {0,-50} [{1}]" -f $_.DisplayName, $_.GpoStatus) -ForegroundColor $statusColor
    }
} catch {
    Write-Log "Error generating report: $($_.Exception.Message)" "Red"
    exit 1
}
