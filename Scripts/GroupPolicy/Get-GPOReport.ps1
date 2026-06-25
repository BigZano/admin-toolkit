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

Write-Log "Retrieving all GPOs in domain..." "Cyan"

try {
    $gpos = Get-GPO -All | Sort-Object DisplayName
    Write-Log "Found $($gpos.Count) GPOs." "Cyan"

    $type = $ReportType.ToUpper()

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
    $summary = $gpos | ForEach-Object {
        $links = (Get-GPOReport -Guid $_.Id -ReportType XML | Select-Xml -XPath "//LinksTo/SOMPath").Node.InnerText
        [PSCustomObject]@{
            Name            = $_.DisplayName
            Status          = $_.GpoStatus
            CreationTime    = $_.CreationTime.ToString("yyyy-MM-dd")
            ModificationTime = $_.ModificationTime.ToString("yyyy-MM-dd HH:mm")
            WMIFilter       = if ($_.WmiFilter) { $_.WmiFilter.Name } else { "None" }
            LinkedTo        = ($links -join "; ")
        }
    }
    $summary | Export-Csv -Path $summaryFile -NoTypeInformation -Encoding UTF8
    Write-Log "Summary CSV saved to: $summaryFile" "Green"

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
