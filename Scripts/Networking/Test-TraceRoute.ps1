# Trace network route to a host with per-hop latency

param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,
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
$outputFile = Join-Path $OutputDirectory "Test-TraceRoute_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Test-TraceRoute_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "Tracing route to $ComputerName (this can take a minute)..." "Cyan"

try {
    $trace = Test-NetConnection -ComputerName $ComputerName -TraceRoute -WarningAction SilentlyContinue -ErrorAction Stop
} catch {
    Write-Log "ERROR: Trace route failed: $($_.Exception.Message)" "Red"
    exit 1
}

if (-not $trace.TraceRoute -or $trace.TraceRoute.Count -eq 0) {
    Write-Log "ERROR: No route information returned for $ComputerName." "Red"
    exit 1
}

$results = @()
$hopNum  = 0

foreach ($hop in $trace.TraceRoute) {
    $hopNum++

    # Per-hop latency
    $latency = "*"
    if ($hop -ne "0.0.0.0") {
        try {
            $ping = Test-Connection -TargetName $hop -Count 1 -TimeoutSeconds 2 -ErrorAction Stop
            if ($ping -and $null -ne $ping.Latency) {
                $latency = "$($ping.Latency) ms"
            }
        } catch {
            $latency = "*"
        }
    }

    # Reverse DNS
    $hostname = "*"
    if ($hop -ne "0.0.0.0") {
        try {
            $hostname = ([System.Net.Dns]::GetHostEntry($hop)).HostName
        } catch {
            $hostname = "*"
        }
    }

    $addr = if ($hop -eq "0.0.0.0") { "*" } else { $hop }
    $results += [PSCustomObject]@{
        Hop      = $hopNum
        Address  = $addr
        Hostname = $hostname
        Latency  = $latency
    }

    $color = if ($addr -eq "*" -or $latency -eq "*") { "Yellow" } else { "White" }
    Write-Log ("  {0,3}  {1,-40} {2,-15} {3}" -f $hopNum, $addr, $latency, $hostname) $color
}

$results | Export-Csv -Path $outputFile -NoTypeInformation

Write-Host ""
$results | Format-Table -AutoSize
Write-Log "Trace complete: $hopNum hop(s) to $ComputerName (ping reachable: $($trace.PingSucceeded))" "Cyan"
Write-Log "Report saved: $outputFile" "Green"
