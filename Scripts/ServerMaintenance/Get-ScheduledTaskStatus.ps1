# Report scheduled task status, last run result, and next run time on one or more servers

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerList = "",
    [Parameter(Mandatory=$false)]
    [string]$FilterName = "",
    [Parameter(Mandatory=$false)]
    [string]$FailedOnly = "false",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = Join-Path $env:USERPROFILE "Documents\AdminToolReports"
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "ScheduledTasks_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "ScheduledTasks_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$showFailedOnly = $FailedOnly -eq "true" -or $FailedOnly -eq "1"

$computers = if (-not [string]::IsNullOrEmpty($ComputerList) -and (Test-Path $ComputerList -ErrorAction SilentlyContinue)) {
    Get-Content $ComputerList | Where-Object { $_ -match '\S' }
} elseif (-not [string]::IsNullOrEmpty($ComputerList)) {
    $ComputerList -split ',' | ForEach-Object { $_.Trim() }
} else {
    @($env:COMPUTERNAME)
}

Write-Log "Checking scheduled tasks on $($computers.Count) server(s)..." "Cyan"

$report = @()
foreach ($computer in $computers) {
    Write-Host ""
    Write-Host "  $computer" -ForegroundColor Cyan

    try {
        $tasks = Invoke-Command -ComputerName $computer -ErrorAction Stop -ScriptBlock {
            param($filter, $failedOnly)
            $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
                Where-Object { $_.TaskPath -notmatch "\\Microsoft\\" } |
                Where-Object { -not $filter -or $_.TaskName -match $filter }

            foreach ($t in $allTasks) {
                $info = $t | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
                if ($failedOnly -and ($info.LastTaskResult -eq 0 -or $info.LastTaskResult -eq $null)) { continue }

                [PSCustomObject]@{
                    Computer        = $env:COMPUTERNAME
                    Name            = $t.TaskName
                    Path            = $t.TaskPath
                    State           = $t.State
                    LastRunTime     = $info.LastRunTime
                    LastResult      = $info.LastTaskResult
                    NextRunTime     = $info.NextRunTime
                }
            }
        } -ArgumentList $FilterName, $showFailedOnly

        if (-not $tasks -or @($tasks).Count -eq 0) {
            Write-Host "    No tasks found matching criteria." -ForegroundColor DarkGray
            continue
        }

        Write-Host ("    {0,-35} {1,-10} {2,-22} {3,-10} {4}" -f "Task", "State", "Last Run", "Result", "Next Run") -ForegroundColor DarkGray
        Write-Host ("    " + ("-" * 95)) -ForegroundColor DarkGray

        foreach ($t in $tasks | Sort-Object Name) {
            $lastRun = if ($t.LastRunTime -and $t.LastRunTime.Year -gt 1900) { $t.LastRunTime.ToString("yyyy-MM-dd HH:mm") } else { "Never" }
            $nextRun = if ($t.NextRunTime -and $t.NextRunTime.Year -gt 1900) { $t.NextRunTime.ToString("yyyy-MM-dd HH:mm") } else { "-" }
            $result  = "0x{0:X}" -f $t.LastResult

            $color = if ($t.LastResult -ne 0 -and $t.LastResult -ne $null -and $lastRun -ne "Never") { "Yellow" }
                     elseif ($t.State -eq "Disabled") { "DarkGray" }
                     else { "White" }

            Write-Host ("    {0,-35} {1,-10} {2,-22} {3,-10} {4}" -f `
                ($t.Name.Substring(0, [Math]::Min(33, $t.Name.Length))),
                $t.State, $lastRun, $result, $nextRun) -ForegroundColor $color

            $report += $t
        }
    } catch {
        Write-Log "  Failed to connect to $computer : $($_.Exception.Message)" "Red"
    }
}

Write-Host ""
$failed  = @($report | Where-Object { $_.LastResult -ne 0 -and $_.LastRunTime -and $_.LastRunTime.Year -gt 1900 }).Count
$color   = if ($failed -gt 0) { "Yellow" } else { "Green" }
Write-Log ("Total tasks: $($report.Count)  |  Non-zero last result: $failed") $color

$report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
