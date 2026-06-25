# Report pending Windows updates and last update installation date

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
$outputFile = Join-Path $OutputDirectory "WindowsUpdates_${target}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "WindowsUpdates_${target}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "Checking Windows Update status on: $target" "Cyan"
Write-Log "This may take a moment..." "Yellow"

try {
    $result = Invoke-Command -ComputerName $target -ErrorAction Stop -ScriptBlock {
        # Last installed update
        $lastInstalled = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1

        # Pending updates via WUA COM
        $session  = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $search   = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")

        $pending = $search.Updates | ForEach-Object {
            [PSCustomObject]@{
                Title       = $_.Title
                KB          = (($_.KBArticleIDs | ForEach-Object { "KB$_" }) -join ", ")
                Severity    = $_.MsrcSeverity
                Categories  = ($_.Categories | ForEach-Object { $_.Name }) -join ", "
                Size        = [math]::Round($_.MaxDownloadSize / 1MB, 1)
                RebootRequired = $_.InstallationBehavior.RebootBehavior -ne 0
                ReleaseDate = if ($_.LastDeploymentChangeTime) { $_.LastDeploymentChangeTime.ToString("yyyy-MM-dd") } else { "" }
            }
        }

        # Check pending reboot
        $pendingReboot = $false
        $rebootKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
            "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        )
        if (Test-Path $rebootKeys[0]) { $pendingReboot = $true }
        $smKey = Get-ItemProperty $rebootKeys[1] -ErrorAction SilentlyContinue
        if ($smKey.PendingFileRenameOperations) { $pendingReboot = $true }

        [PSCustomObject]@{
            PendingUpdates  = $pending
            LastHotFix      = $lastInstalled.HotFixID
            LastInstallDate = if ($lastInstalled.InstalledOn) { $lastInstalled.InstalledOn.ToString("yyyy-MM-dd") } else { "Unknown" }
            PendingReboot   = $pendingReboot
            PendingCount    = $pending.Count
        }
    }

    $pending = $result.PendingUpdates
    $critical = @($pending | Where-Object { $_.Severity -eq "Critical" })
    $important = @($pending | Where-Object { $_.Severity -eq "Important" })

    Write-Host ""
    Write-Host ("  Last installed update: {0}  ({1})" -f $result.LastHotFix, $result.LastInstallDate) -ForegroundColor Gray
    Write-Host ("  Pending reboot:        {0}" -f $result.PendingReboot) -ForegroundColor $(if ($result.PendingReboot) { "Yellow" } else { "Green" })
    Write-Host ("  Pending updates:       {0}  (Critical: {1}  Important: {2})" -f $result.PendingCount, $critical.Count, $important.Count) `
        -ForegroundColor $(if ($critical.Count -gt 0) { "Red" } elseif ($important.Count -gt 0) { "Yellow" } else { "Green" })
    Write-Host ""

    if ($pending.Count -gt 0) {
        $pending | Sort-Object Severity, Title | ForEach-Object {
            $color = switch ($_.Severity) {
                "Critical"  { "Red" }
                "Important" { "Yellow" }
                default     { "Gray" }
            }
            $rebootStr = if ($_.RebootRequired) { "  [REBOOT]" } else { "" }
            Write-Host ("  [{0,-10}] {1}{2}" -f $_.Severity, $_.Title, $rebootStr) -ForegroundColor $color
            if ($_.KB) { Write-Host ("  {0,-13} {1}" -f "", $_.KB) -ForegroundColor DarkGray }
        }

        $pending | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
        Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
    } else {
        Write-Log "System is fully up to date." "Green"
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"
    Write-Log "Ensure the Windows Update service is running and you have admin rights." "Yellow"
    exit 1
}
