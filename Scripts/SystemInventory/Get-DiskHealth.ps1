# Report disk space usage with warning thresholds and SMART health status

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
    [Parameter(Mandatory=$false)]
    [string]$WarnThresholdPct = "80",
    [Parameter(Mandatory=$false)]
    [string]$CritThresholdPct = "90",
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
$warnPct   = [int]$WarnThresholdPct
$critPct   = [int]$CritThresholdPct
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "DiskHealth_${target}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "DiskHealth_${target}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "Checking disk health on: $target  (warn: ${warnPct}%  crit: ${critPct}%)" "Cyan"

try {
    $cimParams = if ($target -ne $env:COMPUTERNAME) { @{ CimSession = New-CimSession -ComputerName $target } } else { @{} }

    $logicalDisks = Get-CimInstance Win32_LogicalDisk @cimParams -Filter "DriveType=3" -ErrorAction Stop
    $physicalDisks = Get-CimInstance Win32_DiskDrive @cimParams -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "  Logical Drives:" -ForegroundColor DarkGray

    $report = foreach ($disk in ($logicalDisks | Sort-Object DeviceID)) {
        $totalGB = [math]::Round($disk.Size / 1GB, 2)
        $freeGB  = [math]::Round($disk.FreeSpace / 1GB, 2)
        $usedGB  = [math]::Round(($disk.Size - $disk.FreeSpace) / 1GB, 2)
        $usedPct = if ($disk.Size -gt 0) { [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1) } else { 0 }

        $color  = if ($usedPct -ge $critPct) { "Red" } elseif ($usedPct -ge $warnPct) { "Yellow" } else { "Green" }
        $status = if ($usedPct -ge $critPct) { "CRITICAL" } elseif ($usedPct -ge $warnPct) { "WARNING" } else { "OK" }

        $barLen  = [math]::Min([int]($usedPct / 2), 50)
        $bar     = ("#" * $barLen).PadRight(50)

        Write-Host ("  {0}  [{1}% used]  {2,7} GB / {3,7} GB  {4}" -f $disk.DeviceID, $usedPct, $usedGB, $totalGB, $status) -ForegroundColor $color
        Write-Host ("    [{0}]" -f $bar) -ForegroundColor $color

        [PSCustomObject]@{
            Computer  = $target
            Drive     = $disk.DeviceID
            Label     = $disk.VolumeName
            TotalGB   = $totalGB
            UsedGB    = $usedGB
            FreeGB    = $freeGB
            UsedPct   = $usedPct
            Status    = $status
            FileSystem = $disk.FileSystem
        }
    }

    if ($physicalDisks) {
        Write-Host ""
        Write-Host "  Physical Disks (SMART status):" -ForegroundColor DarkGray
        $physicalDisks | ForEach-Object {
            $smartColor = if ($_.Status -eq "OK") { "Green" } else { "Red" }
            $sizeGB = [math]::Round($_.Size / 1GB, 0)
            Write-Host ("  {0}  {1,6} GB  {2}  [{3}]" -f $_.Model, $sizeGB, $_.MediaType, $_.Status) -ForegroundColor $smartColor
        }
    }

    $critical = @($report | Where-Object { $_.Status -eq "CRITICAL" })
    $warning  = @($report | Where-Object { $_.Status -eq "WARNING" })
    Write-Host ""
    Write-Log "Critical: $($critical.Count)  |  Warning: $($warning.Count)  |  OK: $($report.Count - $critical.Count - $warning.Count)" `
        "$(if ($critical.Count -gt 0) { 'Red' } elseif ($warning.Count -gt 0) { 'Yellow' } else { 'Green' })"

    $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Log "Report saved to: $outputFile" "Green"

    if ($cimParams.ContainsKey("CimSession")) { Remove-CimSession $cimParams["CimSession"] }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
