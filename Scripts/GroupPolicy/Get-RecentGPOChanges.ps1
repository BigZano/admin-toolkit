# List GPOs modified in the last X days

param(
    [Parameter(Mandatory=$false)]
    [string]$DaysBack = "30",
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

$days       = [int]$DaysBack
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "RecentGPOChanges_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "RecentGPOChanges_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module GroupPolicy -ErrorAction Stop
} catch {
    Write-Log "GroupPolicy module not available. Install RSAT (Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0)." "Red"
    exit 1
}

$cutoff = (Get-Date).AddDays(-$days)
Write-Log "Searching for GPOs modified since $($cutoff.ToString('yyyy-MM-dd')) ($days days)..." "Cyan"

try {
    $gpos = @(Get-GPO -All -ErrorAction Stop)
} catch {
    Write-Log "Error enumerating GPOs: $($_.Exception.Message)" "Red"
    exit 1
}

$results = @($gpos | Where-Object { $_.ModificationTime -ge $cutoff } |
    Sort-Object ModificationTime -Descending |
    ForEach-Object {
        [PSCustomObject]@{
            DisplayName      = $_.DisplayName
            ModificationTime = $_.ModificationTime.ToString("yyyy-MM-dd HH:mm")
            CreationTime     = $_.CreationTime.ToString("yyyy-MM-dd HH:mm")
            GpoStatus        = $_.GpoStatus
            Id               = $_.Id
        }
    })

Write-Host ""
if ($results.Count -gt 0) {
    $results | Format-Table DisplayName, ModificationTime, CreationTime, GpoStatus -AutoSize | Out-String | Write-Host
    Write-Log "GPOs modified in last $days days: $($results.Count) of $($gpos.Count) total GPOs" "Yellow"
} else {
    Write-Log "No GPOs modified in the last $days days (checked $($gpos.Count) GPOs)." "Green"
}
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Log "Report saved: $outputFile" "Green"
