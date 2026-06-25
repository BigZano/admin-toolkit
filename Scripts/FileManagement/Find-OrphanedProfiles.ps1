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
    $profilesKey = "\\$target\root\cimv2"
    $profiles = if ($target -eq $env:COMPUTERNAME) {
        Get-WmiObject -Class Win32_UserProfile -ErrorAction Stop |
            Where-Object { -not $_.Special }
    } else {
        Get-WmiObject -Class Win32_UserProfile -ComputerName $target -ErrorAction Stop |
            Where-Object { -not $_.Special }
    }

    Write-Log "Found $($profiles.Count) non-system profiles." "Cyan"

    $report = foreach ($profile in $profiles) {
        $sid = $profile.SID
        $localPath = $profile.LocalPath
        $lastUse   = if ($profile.LastUseTime) {
            [System.Management.ManagementDateTimeConverter]::ToDateTime($profile.LastUseTime).ToString("yyyy-MM-dd")
        } else { "Unknown" }

        # Try to find matching AD account by SID
        $adUser = $null
        $status = "Unknown"
        try {
            $adUser = Get-ADUser -Filter { SID -eq $sid } -Properties DisplayName, Enabled -ErrorAction SilentlyContinue
            $status = if ($adUser) {
                if ($adUser.Enabled) { "Active" } else { "Disabled" }
            } else { "Orphaned" }
        } catch { $status = "ADLookupFailed" }

        [PSCustomObject]@{
            ProfilePath = $localPath
            SID         = $sid
            LastUse     = $lastUse
            ADAccount   = if ($adUser) { $adUser.SamAccountName } else { "Not found" }
            DisplayName = if ($adUser) { $adUser.DisplayName } else { "" }
            Status      = $status
        }
    }

    $orphaned = @($report | Where-Object { $_.Status -eq "Orphaned" })
    $disabled = @($report | Where-Object { $_.Status -eq "Disabled" })
    $active   = @($report | Where-Object { $_.Status -eq "Active" })

    Write-Log "Active: $($active.Count)  |  Disabled AD account: $($disabled.Count)  |  Orphaned (no AD match): $($orphaned.Count)" `
        "$(if ($orphaned.Count -gt 0) { 'Yellow' } else { 'Green' })"

    if ($orphaned.Count -gt 0 -or $disabled.Count -gt 0) {
        Write-Host ""
        Write-Host "  Profiles to review:" -ForegroundColor Yellow
        @($orphaned + $disabled) | ForEach-Object {
            $color = if ($_.Status -eq "Orphaned") { "Red" } else { "Yellow" }
            Write-Host ("  [{0,-10}] {1}  (last use: {2})" -f $_.Status, $_.ProfilePath, $_.LastUse) -ForegroundColor $color
        }
    }

    $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
