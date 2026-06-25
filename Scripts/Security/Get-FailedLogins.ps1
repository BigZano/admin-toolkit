# Parse the Security event log for failed login attempts and flag potential brute force

param(
    [Parameter(Mandatory=$false)]
    [string]$HoursBack = "24",
    [Parameter(Mandatory=$false)]
    [string]$BruteForceThreshold = "10",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = if ($IsWindows -or $env:OS -match "Windows") {
        Join-Path $env:USERPROFILE "Documents\AdminToolReports"
    } else { Join-Path $env:HOME "Documents/AdminToolReports" }
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$hours     = [int]$HoursBack
$threshold = [int]$BruteForceThreshold
$since     = (Get-Date).AddHours(-$hours)
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "FailedLogins_${hours}hrs_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "FailedLogins_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

# Logon failure reason codes
$failureCodes = @{
    "0xC000006A" = "Wrong password"
    "0xC0000064" = "Account does not exist"
    "0xC000006D" = "Bad username or auth info"
    "0xC000006E" = "Account restriction"
    "0xC000006F" = "Outside allowed logon hours"
    "0xC0000070" = "Not allowed on this workstation"
    "0xC0000071" = "Password expired"
    "0xC0000072" = "Account disabled"
    "0xC0000193" = "Account expired"
    "0xC0000224" = "Must change password at next logon"
    "0xC0000234" = "Account locked out"
}

Write-Log "Querying Security event log for failed logins in the last $hours hours..." "Cyan"

try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = 4625
        StartTime = $since
    } -ErrorAction Stop

    Write-Log "Found $($events.Count) failed login events." "$(if ($events.Count -gt 0) { 'Yellow' } else { 'Green' })"

    $parsed = $events | ForEach-Object {
        $xml = [xml]$_.ToXml()
        $data = $xml.Event.EventData.Data

        $subStatus = ($data | Where-Object { $_.Name -eq "SubStatus" }).'#text'
        $reason = if ($failureCodes.ContainsKey($subStatus)) { $failureCodes[$subStatus] } else { $subStatus }

        [PSCustomObject]@{
            TimeCreated    = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
            TargetAccount  = ($data | Where-Object { $_.Name -eq "TargetUserName" }).'#text'
            TargetDomain   = ($data | Where-Object { $_.Name -eq "TargetDomainName" }).'#text'
            SourceIP       = ($data | Where-Object { $_.Name -eq "IpAddress" }).'#text'
            SourcePort     = ($data | Where-Object { $_.Name -eq "IpPort" }).'#text'
            LogonType      = ($data | Where-Object { $_.Name -eq "LogonType" }).'#text'
            WorkstationName = ($data | Where-Object { $_.Name -eq "WorkstationName" }).'#text'
            FailureReason  = $reason
        }
    } | Where-Object { $_.TargetAccount -ne "-" -and $_.TargetAccount -ne $null }

    # Brute force detection: accounts or IPs with >= threshold failures
    Write-Host ""
    $byAccount = $parsed | Group-Object TargetAccount | Sort-Object Count -Descending
    $byIP      = $parsed | Where-Object { $_.SourceIP -ne "-" -and $_.SourceIP -ne $null } |
                 Group-Object SourceIP | Sort-Object Count -Descending

    $bruteAccounts = @($byAccount | Where-Object { $_.Count -ge $threshold })
    $bruteIPs      = @($byIP      | Where-Object { $_.Count -ge $threshold })

    if ($bruteAccounts.Count -gt 0) {
        Write-Host "  ALERT - Accounts with >= $threshold failures:" -ForegroundColor Red
        $bruteAccounts | ForEach-Object {
            Write-Host ("  {0,-35} {1} failures" -f $_.Name, $_.Count) -ForegroundColor Red
        }
        Write-Host ""
    }
    if ($bruteIPs.Count -gt 0) {
        Write-Host "  ALERT - Source IPs with >= $threshold failures:" -ForegroundColor Red
        $bruteIPs | ForEach-Object {
            Write-Host ("  {0,-20} {1} failures" -f $_.Name, $_.Count) -ForegroundColor Red
        }
        Write-Host ""
    }

    Write-Host "  Top accounts by failure count:" -ForegroundColor DarkGray
    $byAccount | Select-Object -First 10 | ForEach-Object {
        $color = if ($_.Count -ge $threshold) { "Red" } elseif ($_.Count -ge 5) { "Yellow" } else { "Gray" }
        Write-Host ("  {0,-35} {1}" -f $_.Name, $_.Count) -ForegroundColor $color
    }

    $parsed | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
} catch [System.Exception] {
    if ($_.Exception.Message -match "No events") {
        Write-Log "No failed login events found in the last $hours hours." "Green"
    } else {
        Write-Log "Error: $($_.Exception.Message)" "Red"
        Write-Log "Ensure you are running as Administrator to read the Security log." "Yellow"
        exit 1
    }
}
