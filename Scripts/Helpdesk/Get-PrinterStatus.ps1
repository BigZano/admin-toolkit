# Show printer status and stuck jobs on local or remote machine

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
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
$outputFile = Join-Path $OutputDirectory "Get-PrinterStatus_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Get-PrinterStatus_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module PrintManagement -ErrorAction Stop
} catch {
    Write-Log "ERROR: The PrintManagement module is not available on this system: $($_.Exception.Message)" "Red"
    exit 1
}

$target = if ([string]::IsNullOrEmpty($ComputerName)) { $env:COMPUTERNAME } else { $ComputerName }
Write-Log "Querying printers on: $target" "Cyan"

try {
    if ([string]::IsNullOrEmpty($ComputerName)) {
        $printers = @(Get-Printer -ErrorAction Stop)
    } else {
        $printers = @(Get-Printer -ComputerName $ComputerName -ErrorAction Stop)
    }
} catch {
    Write-Log "ERROR: Could not enumerate printers on ${target}: $($_.Exception.Message)" "Red"
    exit 1
}

if ($printers.Count -eq 0) {
    Write-Log "No printers found on $target." "Yellow"
    exit 0
}

$results = @()

foreach ($printer in $printers) {
    $jobCount     = 0
    $oldestJobAge = ""
    try {
        if ([string]::IsNullOrEmpty($ComputerName)) {
            $jobs = @(Get-PrintJob -PrinterName $printer.Name -ErrorAction SilentlyContinue)
        } else {
            $jobs = @(Get-PrintJob -PrinterName $printer.Name -ComputerName $ComputerName -ErrorAction SilentlyContinue)
        }
        $jobCount = $jobs.Count
        if ($jobCount -gt 0) {
            $oldest = $jobs | Sort-Object SubmittedTime | Select-Object -First 1
            if ($oldest.SubmittedTime) {
                $age = (Get-Date) - $oldest.SubmittedTime
                $oldestJobAge = "{0:d\d\ h\h\ m\m}" -f $age
            }
        }
    } catch {
        $oldestJobAge = "unknown"
    }

    $status  = "$($printer.PrinterStatus)"
    $problem = $status -match '(?i)offline|error|paperout|paperjam'
    $row = [PSCustomObject]@{
        Machine      = $target
        Printer      = $printer.Name
        Status       = $status
        WorkOffline  = $printer.WorkOffline
        DriverName   = $printer.DriverName
        PortName     = $printer.PortName
        QueuedJobs   = $jobCount
        OldestJobAge = $oldestJobAge
    }
    $results += $row

    $color = "Green"
    if ($problem) { $color = "Red" }
    elseif ($printer.WorkOffline -or $jobCount -gt 0) { $color = "Yellow" }
    Write-Log ("  {0,-35} {1,-12} Jobs: {2,-3} {3}" -f $printer.Name, $status, $jobCount, $(if ($printer.WorkOffline) { "(Work Offline)" } else { "" })) $color
}

$results | Export-Csv -Path $outputFile -NoTypeInformation
Write-Host ""
$results | Format-Table Printer, Status, WorkOffline, QueuedJobs, OldestJobAge -AutoSize

$problems = @($results | Where-Object { $_.Status -match '(?i)offline|error|paperout|paperjam' -or $_.WorkOffline })
Write-Log "Printers: $($results.Count); with problems: $($problems.Count)" $(if ($problems.Count -gt 0) { "Yellow" } else { "Cyan" })
Write-Log "Report saved: $outputFile" "Green"
