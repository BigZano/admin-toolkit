# Report disk free space across one or more machines

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerList = "",
    [Parameter(Mandatory=$false)]
    [string]$WarnThresholdPct = "80",
    [Parameter(Mandatory=$false)]
    [string]$CritThresholdPct = "90",
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
$outputFile = Join-Path $OutputDirectory "Get-DiskSpace_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Get-DiskSpace_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$warnPct = 0
$critPct = 0
if (-not [int]::TryParse($WarnThresholdPct, [ref]$warnPct) -or -not [int]::TryParse($CritThresholdPct, [ref]$critPct)) {
    Write-Log "Thresholds must be whole numbers (got warn='$WarnThresholdPct', critical='$CritThresholdPct')." "Red"
    exit 1
}
if ($warnPct -ge $critPct) {
    Write-Log "Warning threshold ($warnPct%) must be lower than critical threshold ($critPct%)." "Red"
    exit 1
}

if ([string]::IsNullOrEmpty($ComputerList)) {
    $computers = @($env:COMPUTERNAME)
} else {
    $computers = $ComputerList -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

Write-Log "Checking disk space on $($computers.Count) machine(s) (warn >= $warnPct%, critical >= $critPct%)..." "Cyan"

$results = @()
$failed  = 0

foreach ($computer in $computers) {
    try {
        if ($computer -eq $env:COMPUTERNAME) {
            $disks = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop)
        } else {
            $disks = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ComputerName $computer -ErrorAction Stop)
        }

        foreach ($disk in $disks) {
            if (-not $disk.Size -or $disk.Size -eq 0) { continue }
            $sizeGB  = [math]::Round($disk.Size / 1GB, 2)
            $freeGB  = [math]::Round($disk.FreeSpace / 1GB, 2)
            $usedPct = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1)

            $status = "OK"
            $color  = "Green"
            if ($usedPct -ge $critPct)     { $status = "CRITICAL"; $color = "Red" }
            elseif ($usedPct -ge $warnPct) { $status = "Warning";  $color = "Yellow" }

            $results += [PSCustomObject]@{
                Machine = $computer
                Drive   = $disk.DeviceID
                Label   = $disk.VolumeName
                SizeGB  = $sizeGB
                FreeGB  = $freeGB
                UsedPct = $usedPct
                Status  = $status
            }
            Write-Log ("  {0,-18} {1,-4} {2,8} GB total, {3,8} GB free, {4,5}% used  [{5}]" -f $computer, $disk.DeviceID, $sizeGB, $freeGB, $usedPct, $status) $color
        }
    } catch {
        $failed++
        Write-Log ("  {0,-18} UNREACHABLE: {1}" -f $computer, $_.Exception.Message) "Red"
        $results += [PSCustomObject]@{
            Machine = $computer
            Drive   = ""
            Label   = ""
            SizeGB  = ""
            FreeGB  = ""
            UsedPct = ""
            Status  = "Unreachable"
        }
    }
}

$results | Export-Csv -Path $outputFile -NoTypeInformation
Write-Host ""
$results | Format-Table -AutoSize

$critical = @($results | Where-Object { $_.Status -eq "CRITICAL" })
$warning  = @($results | Where-Object { $_.Status -eq "Warning" })
Write-Log "Disks: $(@($results | Where-Object { $_.Drive }).Count); critical: $($critical.Count); warning: $($warning.Count); unreachable machines: $failed" $(if ($critical.Count -gt 0) { "Red" } elseif ($warning.Count -gt 0) { "Yellow" } else { "Cyan" })
Write-Log "Report saved: $outputFile" "Green"
