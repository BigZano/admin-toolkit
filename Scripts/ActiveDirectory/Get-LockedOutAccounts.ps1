# Find all currently locked-out AD user accounts

param(
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
$outputFile = Join-Path $OutputDirectory "LockedOutAccounts_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "LockedOutAccounts_$timestamp.log"

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

Write-Log "Searching for currently locked-out user accounts..." "Cyan"

try {
    $lockedOut = Search-ADAccount -LockedOut -UsersOnly -ErrorAction Stop
} catch {
    Write-Log "Error searching AD for locked-out accounts: $($_.Exception.Message)" "Red"
    exit 1
}

$results   = @()
$skipCount = 0

foreach ($account in $lockedOut) {
    try {
        $user = Get-ADUser -Identity $account.SamAccountName `
            -Properties DisplayName, EmailAddress, Enabled, lockoutTime, LastLogonTimeStamp, DistinguishedName -ErrorAction Stop

        $lockoutTime = if ($user.lockoutTime -and $user.lockoutTime -gt 0) {
            [DateTime]::FromFileTime($user.lockoutTime).ToString("yyyy-MM-dd HH:mm:ss")
        } else { "Unknown" }

        $lastLogon = if ($user.LastLogonTimeStamp -and $user.LastLogonTimeStamp -gt 0) {
            [DateTime]::FromFileTime($user.LastLogonTimeStamp).ToString("yyyy-MM-dd HH:mm:ss")
        } else { "Never" }

        $results += [PSCustomObject]@{
            SamAccountName = $user.SamAccountName
            DisplayName    = $user.DisplayName
            Email          = $user.EmailAddress
            Enabled        = $user.Enabled
            LockoutTime    = $lockoutTime
            LastLogon      = $lastLogon
            OU             = ($user.DistinguishedName -replace '^CN=[^,]+,', '')
        }
    } catch {
        $skipCount++
        Write-Log "Skipped $($account.SamAccountName): $($_.Exception.Message)" "Yellow"
    }
}

Write-Host ""
if ($results.Count -gt 0) {
    $results | Sort-Object LockoutTime -Descending | Format-Table SamAccountName, DisplayName, Enabled, LockoutTime, LastLogon -AutoSize | Out-String | Write-Host
    $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Log "Locked-out accounts found: $($results.Count)" "Yellow"
} else {
    Write-Log "No locked-out accounts found." "Green"
    $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
}
if ($skipCount -gt 0) {
    Write-Log "Accounts skipped due to lookup errors: $skipCount" "Yellow"
}
Write-Log "Report saved: $outputFile" "Green"
