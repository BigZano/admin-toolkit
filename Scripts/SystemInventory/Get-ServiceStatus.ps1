# Audit Windows services — flags auto-start services that are stopped

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
    [Parameter(Mandatory=$false)]
    [string]$FilterStatus = "",
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
$outputFile = Join-Path $OutputDirectory "Services_${target}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Services_${target}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

# Services that are expected to be stopped even with Auto start
$knownAutoStopped = @(
    "RemoteRegistry", "WerSvc", "diagnosticshub.standardcollector.service",
    "AJRouter", "ALG", "AppReadiness", "AppVClient", "CscService"
)

Write-Log "Retrieving services from: $target" "Cyan"

try {
    $services = Get-Service -ComputerName $target -ErrorAction Stop |
        Sort-Object StartType, Status, DisplayName

    if (-not [string]::IsNullOrEmpty($FilterStatus)) {
        $services = $services | Where-Object { $_.Status -eq $FilterStatus }
        Write-Log "Filter: Status = $FilterStatus" "Yellow"
    }

    $cimParams = if ($target -ne $env:COMPUTERNAME) { @{ CimSession = New-CimSession -ComputerName $target } } else { @{} }
    $cimServices = Get-CimInstance Win32_Service @cimParams -ErrorAction SilentlyContinue

    $report = $services | ForEach-Object {
        $svc = $_
        $cimSvc = $cimServices | Where-Object { $_.Name -eq $svc.Name } | Select-Object -First 1

        $isAutoStopped = $svc.StartType -eq "Automatic" -and $svc.Status -eq "Stopped" `
            -and $svc.Name -notin $knownAutoStopped

        [PSCustomObject]@{
            Name        = $svc.Name
            DisplayName = $svc.DisplayName
            Status      = $svc.Status
            StartType   = $svc.StartType
            Account     = $cimSvc.StartName
            PID         = $cimSvc.ProcessId
            Description = $cimSvc.Description
            NeedsReview = $isAutoStopped
        }
    }

    $autoStopped = @($report | Where-Object { $_.NeedsReview })
    $running     = @($report | Where-Object { $_.Status -eq "Running" })
    $stopped     = @($report | Where-Object { $_.Status -eq "Stopped" })
    $disabled    = @($report | Where-Object { $_.StartType -eq "Disabled" })

    Write-Log "Total: $($report.Count)  Running: $($running.Count)  Stopped: $($stopped.Count)  Disabled: $($disabled.Count)  Auto+Stopped (review): $($autoStopped.Count)" `
        "$(if ($autoStopped.Count -gt 0) { 'Yellow' } else { 'Green' })"
    Write-Host ""

    if ($autoStopped.Count -gt 0) {
        Write-Host "  Auto-start services that are STOPPED (may need attention):" -ForegroundColor Yellow
        $autoStopped | ForEach-Object {
            Write-Host ("  {0,-40} {1}" -f $_.DisplayName, $_.Name) -ForegroundColor Yellow
        }
        Write-Host ""
    }

    # Show running services grouped by start type
    $report | Where-Object { $_.Status -eq "Running" } | ForEach-Object {
        Write-Host ("  [Running ] {0,-40} {1}" -f $_.DisplayName, $_.Account) -ForegroundColor Green
    }
    $report | Where-Object { $_.Status -ne "Running" -and $_.StartType -ne "Disabled" } | ForEach-Object {
        $color = if ($_.NeedsReview) { "Yellow" } else { "DarkGray" }
        Write-Host ("  [{0,-8}] {1,-40} [{2}]" -f $_.Status, $_.DisplayName, $_.StartType) -ForegroundColor $color
    }

    $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"

    if ($cimParams.ContainsKey("CimSession")) { Remove-CimSession $cimParams["CimSession"] }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
