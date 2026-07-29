# Show uptime and last boot time for one or more machines

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerList = "",
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
$outputFile = Join-Path $OutputDirectory "Get-ComputerUptime_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Get-ComputerUptime_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

if ([string]::IsNullOrEmpty($ComputerList)) {
    $computers = @($env:COMPUTERNAME)
} else {
    $computers = $ComputerList -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

Write-Log "Checking uptime on $($computers.Count) machine(s)..." "Cyan"

$results = @()
$failed  = 0

foreach ($computer in $computers) {
    try {
        if ($computer -eq $env:COMPUTERNAME) {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        } else {
            $os = Get-CimInstance Win32_OperatingSystem -ComputerName $computer -ErrorAction Stop
        }

        $boot   = $os.LastBootUpTime
        $uptime = (Get-Date) - $boot
        $upText = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
        $stale  = $uptime.Days -gt 30

        $results += [PSCustomObject]@{
            Machine      = $computer
            LastBootTime = $boot.ToString("yyyy-MM-dd HH:mm:ss")
            Uptime       = $upText
            UptimeDays   = $uptime.Days
            Status       = if ($stale) { "Over30Days" } else { "OK" }
        }

        if ($stale) {
            Write-Log ("  {0,-20} up {1}  (needs patching reboot?)" -f $computer, $upText) "Yellow"
        } else {
            Write-Log ("  {0,-20} up {1}" -f $computer, $upText) "Green"
        }
    } catch {
        $failed++
        Write-Log ("  {0,-20} UNREACHABLE: {1}" -f $computer, $_.Exception.Message) "Red"
        $results += [PSCustomObject]@{
            Machine      = $computer
            LastBootTime = ""
            Uptime       = ""
            UptimeDays   = ""
            Status       = "Unreachable"
        }
    }
}

$results | Export-Csv -Path $outputFile -NoTypeInformation
Write-Host ""
$results | Format-Table -AutoSize

$stale = @($results | Where-Object { $_.Status -eq "Over30Days" })
Write-Log "Machines: $($computers.Count); unreachable: $failed; uptime > 30 days: $($stale.Count)" "Cyan"
Write-Log "Report saved: $outputFile" "Green"
