# Check DFS Replication group health, backlog, and member connection status

param(
    [Parameter(Mandatory=$false)]
    [string]$DFSGroupName = "",
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = Join-Path $env:USERPROFILE "Documents\AdminToolReports"
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "DFSReplication_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "DFSReplication_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module DFSR -ErrorAction Stop
} catch {
    Write-Log "DFSR module not found — DFS-R tools required (RSAT or server role)." "Red"; exit 1
}

$groupFilter = if (-not [string]::IsNullOrEmpty($DFSGroupName)) { $DFSGroupName } else { "*" }

Write-Log "Retrieving DFS-R replication groups..." "Cyan"

try {
    $groups = Get-DfsReplicationGroup -GroupName $groupFilter -ErrorAction Stop
} catch {
    Write-Log "Failed to retrieve replication groups: $($_.Exception.Message)" "Red"; exit 1
}

if (-not $groups -or @($groups).Count -eq 0) {
    Write-Log "No DFS-R groups found." "Yellow"; exit 0
}

$report = @()
foreach ($group in $groups | Sort-Object GroupName) {
    Write-Host ""
    Write-Host "  Group: $($group.GroupName)" -ForegroundColor Cyan

    try {
        $members = Get-DfsrMember -GroupName $group.GroupName -ErrorAction Stop
        $connections = Get-DfsrConnection -GroupName $group.GroupName -ErrorAction SilentlyContinue
        $folders = @(Get-DfsrReplicatedFolder -GroupName $group.GroupName -ErrorAction SilentlyContinue)

        foreach ($member in $members | Sort-Object ComputerName) {
            $inbound  = @($connections | Where-Object { $_.ReceivingMember -eq $member.ComputerName })
            $outbound = @($connections | Where-Object { $_.SendingMember   -eq $member.ComputerName })

            # Get-DfsrBacklog needs a concrete source/destination pair and folder — no wildcards —
            # and returns one record per backlogged file (capped at 100 per query).
            $backlog = 0
            foreach ($dest in ($members | Where-Object { $_.ComputerName -ne $member.ComputerName })) {
                foreach ($folder in $folders) {
                    try {
                        $bl = Get-DfsrBacklog -GroupName $group.GroupName -FolderName $folder.FolderName `
                            -SourceComputerName $member.ComputerName -DestinationComputerName $dest.ComputerName `
                            -ErrorAction Stop
                        $backlog += @($bl).Count
                    } catch {
                        Write-Log "    Backlog query failed ($($member.ComputerName) -> $($dest.ComputerName), folder '$($folder.FolderName)'): $($_.Exception.Message)" "Yellow"
                    }
                }
            }

            $color = if ($backlog -gt 100) { "Red" } elseif ($backlog -gt 0) { "Yellow" } else { "Green" }

            Write-Host ("    {0,-28} In: {1,-4} Out: {2,-4} Backlog: {3}" -f `
                $member.ComputerName, $inbound.Count, $outbound.Count, $backlog) -ForegroundColor $color

            $report += [PSCustomObject]@{
                Group       = $group.GroupName
                Member      = $member.ComputerName
                InboundCxns = $inbound.Count
                OutboundCxns = $outbound.Count
                BacklogCount = $backlog
                Description = $member.Description
            }
        }
    } catch {
        Write-Log "  Error querying group '$($group.GroupName)': $($_.Exception.Message)" "Yellow"
    }
}

Write-Host ""
$totalBacklog = ($report | Measure-Object -Property BacklogCount -Sum).Sum
$color = if ($totalBacklog -gt 100) { "Red" } elseif ($totalBacklog -gt 0) { "Yellow" } else { "Green" }
Write-Log ("Groups: $($groups.Count)  |  Members: $($report.Count)  |  Total backlog: $totalBacklog files") $color

$report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
