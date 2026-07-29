# Find local user profiles with no matching Active Directory account

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = if ($IsWindows -or $env:OS -match "Windows") {
        Join-Path $env:USERPROFILE "Documents\AdminToolReports"
    } else { Join-Path $env:HOME "Documents/AdminToolReports" }
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$target    = if ([string]::IsNullOrEmpty($ComputerName)) { $env:COMPUTERNAME } else { $ComputerName }
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "OrphanedProfiles_${target}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "OrphanedProfiles_${target}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Log "ActiveDirectory module not found. Install RSAT." "Red"; exit 1
}

Write-Log "Scanning user profiles on: $target" "Cyan"

try {
    $cimParams = if ($target -ne $env:COMPUTERNAME) { @{ ComputerName = $target } } else { @{} }

    $profiles = Get-CimInstance -ClassName Win32_UserProfile @cimParams -ErrorAction Stop |
        Where-Object { -not $_.Special }

    Write-Log "Found $($profiles.Count) non-system profiles." "Cyan"

    # Machine SID prefix, used to classify local (non-domain) accounts before any AD lookup
    $machineSidPrefix = $null
    try {
        $localAcct = Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount=TRUE" @cimParams -ErrorAction Stop |
            Select-Object -First 1
        if ($localAcct) { $machineSidPrefix = $localAcct.SID -replace '-\d+$', '' }
    } catch {
        Write-Log "Could not determine machine SID prefix; local accounts may be reported as Orphaned." "Yellow"
    }

    $report = foreach ($prof in $profiles) {
        $sid       = $prof.SID
        $localPath = $prof.LocalPath
        # Get-CimInstance returns LastUseTime as [datetime] already (no DMTF conversion needed)
        $lastUse   = if ($prof.LastUseTime) { $prof.LastUseTime.ToString("yyyy-MM-dd") } else { "Unknown" }

        $adUser = $null
        if ($machineSidPrefix -and $sid -like "$machineSidPrefix-*") {
            # Local machine account - a valid profile that will never match AD
            $status = "LocalAccount"
        } else {
            $status = "Unknown"
            try {
                $adUser = Get-ADUser -Filter "SID -eq '$sid'" -Properties DisplayName, Enabled -ErrorAction SilentlyContinue
                $status = if ($adUser) {
                    if ($adUser.Enabled) { "Active" } else { "Disabled" }
                } else { "Orphaned" }
            } catch { $status = "ADLookupFailed" }
        }

        [PSCustomObject]@{
            ProfilePath = $localPath
            SID         = $sid
            LastUse     = $lastUse
            ADAccount   = if ($adUser) { $adUser.SamAccountName } else { "Not found" }
            DisplayName = if ($adUser) { $adUser.DisplayName } else { "" }
            Status      = $status
        }
    }

    $orphaned   = @($report | Where-Object { $_.Status -eq "Orphaned" })
    $disabled   = @($report | Where-Object { $_.Status -eq "Disabled" })
    $active     = @($report | Where-Object { $_.Status -eq "Active" })
    $localAccts = @($report | Where-Object { $_.Status -eq "LocalAccount" })

    Write-Log "Active: $($active.Count)  |  Disabled AD account: $($disabled.Count)  |  Local accounts: $($localAccts.Count)  |  Orphaned (no AD match): $($orphaned.Count)" `
        "$(if ($orphaned.Count -gt 0) { 'Yellow' } else { 'Green' })"

    if ($orphaned.Count -gt 0 -or $disabled.Count -gt 0) {
        Write-Host ""
        Write-Host "  Profiles to review:" -ForegroundColor Yellow
        @($orphaned + $disabled) | ForEach-Object {
            $color = if ($_.Status -eq "Orphaned") { "Red" } else { "Yellow" }
            Write-Host ("  [{0,-10}] {1}  (last use: {2})" -f $_.Status, $_.ProfilePath, $_.LastUse) -ForegroundColor $color
        }
    }

    if ($report) {
        $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
        Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
    } else {
        Write-Log "No profiles found; no CSV report generated." "Yellow"
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
