# Report where each Group Policy Object is linked across the domain

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
$outputFile = Join-Path $OutputDirectory "GPOLinks_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "GPOLinks_$timestamp.log"

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

Write-Log "Retrieving GPO link information..." "Cyan"

try {
    $allGPOs = Get-GPO -All | Sort-Object DisplayName
    Write-Log "Processing $($allGPOs.Count) GPOs..." "Cyan"

    $report = foreach ($gpo in $allGPOs) {
        $xmlReport = [xml](Get-GPOReport -Guid $gpo.Id -ReportType XML)
        $links = $xmlReport.GPO.LinksTo

        if ($links) {
            foreach ($link in $links) {
                [PSCustomObject]@{
                    GPOName      = $gpo.DisplayName
                    GPOStatus    = $gpo.GpoStatus
                    LinkTarget   = $link.SOMPath
                    LinkEnabled  = $link.Enabled
                    LinkEnforced = $link.NoOverride
                    ModifiedDate = $gpo.ModificationTime.ToString("yyyy-MM-dd HH:mm")
                }
            }
        } else {
            [PSCustomObject]@{
                GPOName      = $gpo.DisplayName
                GPOStatus    = $gpo.GpoStatus
                LinkTarget   = "[UNLINKED]"
                LinkEnabled  = "N/A"
                LinkEnforced = "N/A"
                ModifiedDate = $gpo.ModificationTime.ToString("yyyy-MM-dd HH:mm")
            }
        }
    }

    $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Log "Report saved to: $outputFile" "Green"

    $linked   = @($report | Where-Object { $_.LinkTarget -ne "[UNLINKED]" })
    $unlinked = @($report | Where-Object { $_.LinkTarget -eq "[UNLINKED]" })
    $enforced = @($linked | Where-Object { $_.LinkEnforced -eq $true })
    $disabled = @($linked | Where-Object { $_.LinkEnabled -eq $false })

    Write-Host ""
    Write-Host ("  Total GPOs: {0}  |  Linked: {1}  |  Unlinked: {2}" -f $allGPOs.Count, $linked.Count, $unlinked.Count) -ForegroundColor Cyan
    Write-Host ("  Enforced links: {0}  |  Disabled links: {1}" -f $enforced.Count, $disabled.Count) -ForegroundColor $(if ($enforced.Count -gt 0) { "Yellow" } else { "Green" })
    Write-Host ""

    $report | Where-Object { $_.LinkTarget -ne "[UNLINKED]" } | ForEach-Object {
        $statusColor = if (-not $_.LinkEnabled) { "DarkGray" } elseif ($_.LinkEnforced) { "Yellow" } else { "White" }
        $flags = @()
        if (-not $_.LinkEnabled) { $flags += "DISABLED" }
        if ($_.LinkEnforced)   { $flags += "ENFORCED" }
        $flagStr = if ($flags) { "  [" + ($flags -join ", ") + "]" } else { "" }
        Write-Host ("  {0,-45} -> {1}{2}" -f $_.GPOName, $_.LinkTarget, $flagStr) -ForegroundColor $statusColor
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"
    exit 1
}
