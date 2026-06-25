# Ping test one or more hosts; accepts a hostname, IP, comma-separated list, or path to a .txt file

param(
    [Parameter(Mandatory=$true)]
    [string]$Targets,
    [Parameter(Mandatory=$false)]
    [string]$Count = "4",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = if ($IsWindows -or $env:OS -match "Windows") {
        Join-Path $env:USERPROFILE "Documents\AdminToolReports"
    } else { Join-Path $env:HOME "Documents/AdminToolReports" }
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$pingCount = [int]$Count
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "Connectivity_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Connectivity_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

# Resolve target list
$hostList = if (Test-Path $Targets -ErrorAction SilentlyContinue) {
    Get-Content $Targets | Where-Object { $_ -match '\S' }
} else {
    $Targets -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

Write-Log "Testing connectivity to $($hostList.Count) target(s)..." "Cyan"
Write-Host ""

$report = foreach ($host in $hostList) {
    $result = Test-Connection -ComputerName $host -Count $pingCount -ErrorAction SilentlyContinue

    if ($result) {
        $avg = [math]::Round(($result | Measure-Object -Property ResponseTime -Average).Average, 1)
        $min = ($result | Measure-Object -Property ResponseTime -Minimum).Minimum
        $max = ($result | Measure-Object -Property ResponseTime -Maximum).Maximum
        $pct = [math]::Round(($result.Count / $pingCount) * 100, 0)

        $color = if ($pct -lt 50) { "Yellow" } else { "Green" }
        Write-Host ("  {0,-35} {1,3}% success  avg {2,5} ms  [{3}-{4} ms]" -f $host, $pct, $avg, $min, $max) -ForegroundColor $color

        [PSCustomObject]@{
            Host        = $host
            Reachable   = $true
            SuccessPct  = $pct
            AvgMs       = $avg
            MinMs       = $min
            MaxMs       = $max
            Replies     = $result.Count
            ResolvedIP  = $result[0].IPV4Address
        }
    } else {
        Write-Host ("  {0,-35} UNREACHABLE" -f $host) -ForegroundColor Red
        [PSCustomObject]@{
            Host        = $host
            Reachable   = $false
            SuccessPct  = 0
            AvgMs       = $null
            MinMs       = $null
            MaxMs       = $null
            Replies     = 0
            ResolvedIP  = $null
        }
    }
}

$up   = @($report | Where-Object { $_.Reachable })
$down = @($report | Where-Object { -not $_.Reachable })

Write-Host ""
Write-Log "Up: $($up.Count)  |  Down/unreachable: $($down.Count)" "$(if ($down.Count -gt 0) { 'Yellow' } else { 'Green' })"

$report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Log "Report saved to: $outputFile" "Green"
