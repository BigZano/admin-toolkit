# Export a Hyper-V VM to a folder for offline backup or migration

param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    [Parameter(Mandatory=$true)]
    [string]$ExportPath,
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = ""
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "  $(Get-Date -Format 'HH:mm:ss')  $Message" -ForegroundColor $Color
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host "  VM:          $VMName" -ForegroundColor Yellow
Write-Host "  Export path: $ExportPath" -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""

$getParams = @{ Name = $VMName; ErrorAction = "Stop" }
if (-not [string]::IsNullOrEmpty($ComputerName)) { $getParams["ComputerName"] = $ComputerName }

try {
    $vm = Get-VM @getParams
} catch {
    Write-Log "VM '$VMName' not found: $($_.Exception.Message)" "Red"; exit 1
}

if ($vm.State -ne "Off" -and $vm.State -ne "Saved") {
    Write-Log "VM is currently '$($vm.State)'. Export requires the VM to be Off or Saved." "Yellow"
    Write-Log "Tip: Use Stop-VMGroup to shut it down first." "Gray"
    exit 1
}

if (-not (Test-Path $ExportPath)) {
    try {
        New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
        Write-Log "Created export directory: $ExportPath" "Cyan"
    } catch {
        Write-Log "Cannot create export path: $($_.Exception.Message)" "Red"; exit 1
    }
}

Write-Log "Starting export — this may take several minutes..." "Cyan"
$start = Get-Date

try {
    $exportParams = @{ Name = $VMName; Path = $ExportPath; ErrorAction = "Stop" }
    if (-not [string]::IsNullOrEmpty($ComputerName)) { $exportParams["ComputerName"] = $ComputerName }
    Export-VM @exportParams
} catch {
    Write-Log "Export failed: $($_.Exception.Message)" "Red"; exit 1
}

$elapsed  = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
$destDir  = Join-Path $ExportPath $VMName
$sizeGB   = if (Test-Path $destDir) {
    [math]::Round((Get-ChildItem $destDir -Recurse -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum / 1GB, 2)
} else { "?" }

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host "  EXPORT COMPLETE" -ForegroundColor Green
Write-Host ("  {0,-20} {1}" -f "VM:", $VMName) -ForegroundColor White
Write-Host ("  {0,-20} {1}" -f "Destination:", $destDir) -ForegroundColor White
Write-Host ("  {0,-20} {1} GB" -f "Size on disk:", $sizeGB) -ForegroundColor White
Write-Host ("  {0,-20} {1} seconds" -f "Duration:", $elapsed) -ForegroundColor White
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""
