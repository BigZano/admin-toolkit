# Find enabled computer accounts inactive for X days

param(
    [Parameter(Mandatory=$false)]
    [string]$DaysInactive = "90",
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

$days       = [int]$DaysInactive
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "InactiveComputers_${days}days_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "InactiveComputers_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Log "ActiveDirectory module not available. Install RSAT (Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0)." "Red"
    exit 1
}

$cutoff = (Get-Date).AddDays(-$days)
Write-Log "Searching for enabled computers with no logon since $($cutoff.ToString('yyyy-MM-dd')) ($days days)..." "Cyan"

try {
    $computers = Get-ADComputer -Filter 'Enabled -eq $true' `
        -Properties LastLogonTimeStamp, OperatingSystem, whenCreated, DistinguishedName -ErrorAction Stop
} catch {
    Write-Log "Error querying AD: $($_.Exception.Message)" "Red"
    exit 1
}

$results = foreach ($computer in $computers) {
    $lastLogonDate = $null
    if ($computer.LastLogonTimeStamp -and $computer.LastLogonTimeStamp -gt 0) {
        $lastLogonDate = [DateTime]::FromFileTime($computer.LastLogonTimeStamp)
    }

    # Include: never logged on, or last logon older than cutoff
    if ($null -eq $lastLogonDate -or $lastLogonDate -lt $cutoff) {
        [PSCustomObject]@{
            Name            = $computer.Name
            OperatingSystem = $computer.OperatingSystem
            LastLogon       = if ($lastLogonDate) { $lastLogonDate.ToString("yyyy-MM-dd") } else { "Never" }
            DaysInactive    = if ($lastLogonDate) { [int](((Get-Date) - $lastLogonDate).TotalDays) } else { "N/A" }
            Created         = $computer.whenCreated.ToString("yyyy-MM-dd")
            OU              = ($computer.DistinguishedName -replace '^CN=[^,]+,', '')
            SortKey         = if ($lastLogonDate) { $lastLogonDate } else { [DateTime]::MinValue }
        }
    }
}

$results = @($results | Sort-Object SortKey | Select-Object Name, OperatingSystem, LastLogon, DaysInactive, Created, OU)

Write-Host ""
if ($results.Count -gt 0) {
    $results | Format-Table Name, OperatingSystem, LastLogon, DaysInactive, Created -AutoSize | Out-String | Write-Host
    Write-Log "Inactive computers found (>$days days): $($results.Count) of $($computers.Count) enabled computers" "Yellow"
} else {
    Write-Log "No inactive computers found (checked $($computers.Count) enabled computers)." "Green"
}
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Log "Report saved: $outputFile" "Green"
