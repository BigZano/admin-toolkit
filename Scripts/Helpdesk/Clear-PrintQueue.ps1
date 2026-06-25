# Clear stuck print jobs from a print queue on a local or remote computer

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
    [Parameter(Mandatory=$false)]
    [string]$PrinterName = ""
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "  $(Get-Date -Format 'HH:mm:ss')  $Message" -ForegroundColor $Color
}

$target = if ([string]::IsNullOrEmpty($ComputerName)) { $env:COMPUTERNAME } else { $ComputerName }
$isLocal = $target -eq $env:COMPUTERNAME

Write-Host ""
Write-Host ("  Target: {0}" -f $target) -ForegroundColor Cyan
if ($PrinterName) {
    Write-Host ("  Printer: {0}" -f $PrinterName) -ForegroundColor Gray
} else {
    Write-Host "  Printer: All queues" -ForegroundColor Gray
}
Write-Host ""

try {
    # Get current jobs before clearing
    $jobFilter = if ($PrinterName) { "Name='$PrinterName'" } else { $null }
    $cimParams = if (-not $isLocal) { @{ CimSession = New-CimSession -ComputerName $target } } else { @{} }

    $printers = if ($PrinterName) {
        Get-Printer -ComputerName $target -Name $PrinterName -ErrorAction Stop
    } else {
        Get-Printer -ComputerName $target -ErrorAction Stop
    }

    $totalJobsBefore = 0
    $printers | ForEach-Object {
        $jobs = Get-PrintJob -PrinterName $_.Name -ComputerName $target -ErrorAction SilentlyContinue
        if ($jobs.Count -gt 0) {
            Write-Host ("  Queue: {0}  —  {1} job(s)" -f $_.Name, $jobs.Count) -ForegroundColor Yellow
            $jobs | ForEach-Object {
                Write-Host ("    Job {0}: {1}  [{2}]" -f $_.ID, $_.DocumentName, $_.JobStatus) -ForegroundColor DarkGray
            }
            $totalJobsBefore += $jobs.Count
        }
    }

    if ($totalJobsBefore -eq 0) {
        Write-Log "No stuck jobs found. Print queues are clear." "Green"
        exit 0
    }

    Write-Host ""
    Write-Log "Stopping Print Spooler on $target..." "Yellow"

    Invoke-Command -ComputerName $target -ScriptBlock {
        param($printer)
        Stop-Service -Name Spooler -Force -ErrorAction Stop

        # Delete all spool files
        $spoolPath = "$env:SystemRoot\System32\spool\PRINTERS"
        $files = Get-ChildItem -Path $spoolPath -File -ErrorAction SilentlyContinue
        $files | Remove-Item -Force -ErrorAction SilentlyContinue
        $deleted = $files.Count

        Start-Service -Name Spooler -ErrorAction Stop
        return $deleted
    } -ArgumentList $PrinterName -ErrorAction Stop | ForEach-Object {
        Write-Log "Deleted $_ spool file(s). Spooler restarted." "Green"
    }

    # Verify queues are clear
    Start-Sleep -Seconds 2
    $remaining = 0
    $printers | ForEach-Object {
        $jobs = Get-PrintJob -PrinterName $_.Name -ComputerName $target -ErrorAction SilentlyContinue
        $remaining += $jobs.Count
    }

    if ($remaining -eq 0) {
        Write-Log "All print queues cleared." "Green"
    } else {
        Write-Log "$remaining job(s) still remain. A reboot of the print server may be needed." "Yellow"
    }

    if ($cimParams.ContainsKey("CimSession")) { Remove-CimSession $cimParams["CimSession"] }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"
    Write-Log "Ensure you have admin rights on $target and the Print Spooler is accessible." "Yellow"
    exit 1
}
