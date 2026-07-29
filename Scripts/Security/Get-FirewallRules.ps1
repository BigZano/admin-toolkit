# Export Windows Firewall rules and flag risky inbound allow rules

param(
    [Parameter(Mandatory=$false)]
    [string]$Direction = "Inbound",
    [Parameter(Mandatory=$false)]
    [string]$EnabledOnly = "true",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = if ($IsWindows -or $env:OS -match "Windows") {
        Join-Path $env:USERPROFILE "Documents\AdminToolReports"
    } else { Join-Path $env:HOME "Documents/AdminToolReports" }
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "FirewallRules_${Direction}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "FirewallRules_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$filterEnabled = $EnabledOnly -eq "true" -or $EnabledOnly -eq "1"
$dir = switch ($Direction.ToLower()) {
    "inbound"  { "Inbound" }
    "outbound" { "Outbound" }
    default    { "Inbound" }
}

try {
    Import-Module NetSecurity -ErrorAction Stop
} catch {
    Write-Log "NetSecurity module not available: $($_.Exception.Message)" "Red"; exit 1
}

Write-Log "Retrieving $dir firewall rules (enabled only: $filterEnabled)..." "Cyan"

try {
    $ruleFilter = @{ Direction = $dir; Action = "Allow" }
    if ($filterEnabled) { $ruleFilter["Enabled"] = "True" }

    $rules = Get-NetFirewallRule @ruleFilter -ErrorAction Stop

    # Fetch all filters once and index by rule InstanceID (3 CIM queries total instead
    # of 3 per rule, which takes minutes on a default rule set)
    Write-Log "Loading filter details for $($rules.Count) rule(s)..." "Cyan"
    $portIdx = @{}; $addrIdx = @{}; $appIdx = @{}
    foreach ($f in @(Get-NetFirewallPortFilter -All -ErrorAction SilentlyContinue))        { $portIdx[$f.InstanceID] = $f }
    foreach ($f in @(Get-NetFirewallAddressFilter -All -ErrorAction SilentlyContinue))     { $addrIdx[$f.InstanceID] = $f }
    foreach ($f in @(Get-NetFirewallApplicationFilter -All -ErrorAction SilentlyContinue)) { $appIdx[$f.InstanceID] = $f }

    $report = foreach ($rule in ($rules | Sort-Object DisplayName)) {
        $portFilter    = $portIdx[$rule.InstanceID]
        $addressFilter = $addrIdx[$rule.InstanceID]
        $appFilter     = $appIdx[$rule.InstanceID]

        $remoteAddr = @($addressFilter.RemoteAddress) -join ", "
        $program    = if ($appFilter.Program -and $appFilter.Program -ne "Any") { $appFilter.Program } else { "Any" }

        # Flag risky rules: allow any remote address, no program restriction, enabled
        $isRisky = ($remoteAddr -eq "Any" -or $remoteAddr -eq "") -and $program -eq "Any" -and $rule.Enabled -eq "True"

        [PSCustomObject]@{
            Name         = $rule.DisplayName
            Profile      = "$($rule.Profile)"
            Protocol     = $portFilter.Protocol
            LocalPort    = (@($portFilter.LocalPort) -join ", ")
            RemotePort   = (@($portFilter.RemotePort) -join ", ")
            RemoteAddr   = $remoteAddr
            Program      = $program
            Enabled      = $rule.Enabled
            Group        = $rule.Group
            Description  = $rule.Description
            IsRisky      = $isRisky
        }
    }

    $risky = @($report | Where-Object { $_.IsRisky })
    Write-Log "Total rules: $($report.Count)  |  Risky (any-to-any, no app filter): $($risky.Count)" `
        "$(if ($risky.Count -gt 0) { 'Yellow' } else { 'Green' })"
    Write-Host ""

    if ($risky.Count -gt 0) {
        Write-Host "  Risky rules (open to Any with no program restriction):" -ForegroundColor Yellow
        $risky | ForEach-Object {
            Write-Host ("  {0,-50} [{1}]  Profile: {2}" -f $_.Name, $_.Protocol, $_.Profile) -ForegroundColor Yellow
        }
        Write-Host ""
    }

    Write-Host "  All $dir allow rules:" -ForegroundColor DarkGray
    $report | ForEach-Object {
        $color = if ($_.IsRisky) { "Yellow" } else { "Gray" }
        $portStr = if ($_.LocalPort -and $_.LocalPort -ne "Any") { "  port: $($_.LocalPort)" } else { "" }
        Write-Host ("  {0,-50} proto: {1,-6}{2}" -f $_.Name, $_.Protocol, $portStr) -ForegroundColor $color
    }

    if ($report) {
        $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
        Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
    } else {
        Write-Log "No rules matched; no CSV report generated." "Yellow"
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
