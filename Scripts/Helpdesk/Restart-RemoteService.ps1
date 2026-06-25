# Restart a Windows service on a remote computer and confirm it comes back up

param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,
    [Parameter(Mandatory=$true)]
    [string]$ServiceName,
    [Parameter(Mandatory=$false)]
    [string]$WaitSeconds = "30"
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "  $(Get-Date -Format 'HH:mm:ss')  $Message" -ForegroundColor $Color
}

$waitSecs = [int]$WaitSeconds

try {
    $svc = Get-Service -ComputerName $ComputerName -Name $ServiceName -ErrorAction Stop
} catch {
    Write-Log "Service '$ServiceName' not found on $ComputerName : $($_.Exception.Message)" "Red"
    Write-Log "Tip: use Get-ServiceStatus script to list available services." "Yellow"
    exit 1
}

Write-Host ""
Write-Host ("  Computer: {0}" -f $ComputerName) -ForegroundColor Cyan
Write-Host ("  Service:  {0}  [{1}]" -f $svc.DisplayName, $svc.Name) -ForegroundColor Yellow
Write-Host ("  Status before: {0}" -f $svc.Status) -ForegroundColor $(if ($svc.Status -eq "Running") { "Green" } else { "Yellow" })
Write-Host ""

# Stop
if ($svc.Status -eq "Running") {
    Write-Log "Stopping service..." "Yellow"
    try {
        $svc.Stop()
        $svc.WaitForStatus("Stopped", [TimeSpan]::FromSeconds($waitSecs))
        Write-Log "Service stopped." "Green"
    } catch {
        Write-Log "Failed to stop: $($_.Exception.Message)" "Red"; exit 1
    }
} else {
    Write-Log "Service was not running — skipping stop." "Yellow"
}

# Start
Write-Log "Starting service..." "Yellow"
try {
    $svc.Start()
    $svc.WaitForStatus("Running", [TimeSpan]::FromSeconds($waitSecs))
    Write-Log "Service started." "Green"
} catch {
    Write-Log "Failed to start: $($_.Exception.Message)" "Red"; exit 1
}

# Confirm
Start-Sleep -Seconds 2
$final = Get-Service -ComputerName $ComputerName -Name $ServiceName
Write-Host ""
Write-Host ("  Status after: {0}" -f $final.Status) -ForegroundColor $(if ($final.Status -eq "Running") { "Green" } else { "Red" })

if ($final.Status -eq "Running") {
    Write-Log "Restart complete — $($svc.DisplayName) is running on $ComputerName." "Green"
} else {
    Write-Log "Service is not running after restart attempt. Check Event Viewer on $ComputerName." "Red"
    exit 1
}
