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

try {
    Import-Module PrintManagement -ErrorAction Stop
} catch {
    Write-Log "PrintManagement module not found. Install the Print Management feature/RSAT." "Red"
    exit 1
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
    if ($PrinterName) {
        # Targeted clear: remove jobs from the named queue only — do NOT purge the
        # spooler directory, which would kill jobs on every other printer.
        Write-Log "Removing jobs from queue '$PrinterName' on $target..." "Yellow"
        $removeErrors = 0
        Get-PrintJob -PrinterName $PrinterName -ComputerName $target -ErrorAction Stop | ForEach-Object {
            try {
                Remove-PrintJob -InputObject $_ -ErrorAction Stop
                Write-Log "  Removed job $($_.ID): $($_.DocumentName)" "Green"
            } catch {
                Write-Log "  Could not remove job $($_.ID): $($_.Exception.Message)" "Yellow"
                $removeErrors++
            }
        }
        if ($removeErrors -gt 0) {
            Write-Log "$removeErrors job(s) resisted removal. Re-run without -PrinterName to restart the spooler and purge all queues." "Yellow"
        }
    } else {
        # Clear-all: stop the spooler, purge spool files, restart.
        Write-Log "Stopping Print Spooler on $target..." "Yellow"

        $purgeBlock = {
            Stop-Service -Name Spooler -Force -ErrorAction Stop

            # Delete all spool files
            $spoolPath = "$env:SystemRoot\System32\spool\PRINTERS"
            $files = @(Get-ChildItem -Path $spoolPath -File -ErrorAction SilentlyContinue)
            $files | Remove-Item -Force -ErrorAction SilentlyContinue
            $deleted = $files.Count

            Start-Service -Name Spooler -ErrorAction Stop
            return $deleted
        }

        $deleted = if ($isLocal) {
            & $purgeBlock
        } else {
            Invoke-Command -ComputerName $target -ScriptBlock $purgeBlock -ErrorAction Stop
        }
        Write-Log "Deleted $deleted spool file(s). Spooler restarted." "Green"
    }

    # Verify queues are clear
    Start-Sleep -Seconds 2
    $remaining = 0
    $printers | ForEach-Object {
        $jobs = Get-PrintJob -PrinterName $_.Name -ComputerName $target -ErrorAction SilentlyContinue
        $remaining += $jobs.Count
    }

    if ($remaining -eq 0) {
        Write-Log "All targeted print queues cleared." "Green"
    } else {
        Write-Log "$remaining job(s) still remain. A reboot of the print server may be needed." "Yellow"
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"
    Write-Log "Ensure you have admin rights on $target and the Print Spooler is accessible." "Yellow"
    exit 1
}
