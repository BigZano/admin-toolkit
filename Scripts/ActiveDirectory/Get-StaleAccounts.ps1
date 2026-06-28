# Find Active Directory accounts with no logon activity in the specified number of days

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

$days = [int]$DaysInactive
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "StaleAccounts_${days}days_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "StaleAccounts_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Log "ActiveDirectory module not found. Install RSAT." "Red"
    exit 1
}

$cutoff = (Get-Date).AddDays(-$days)
Write-Log "Searching for accounts inactive since: $($cutoff.ToString('yyyy-MM-dd'))" "Cyan"

try {
    $stale = Get-ADUser -Filter { Enabled -eq $true } `
        -Properties DisplayName, EmailAddress, LastLogonDate, PasswordLastSet, Department, Title, DistinguishedName |
    Where-Object { $_.LastLogonDate -ne $null -and $_.LastLogonDate -lt $cutoff } |
    Sort-Object LastLogonDate |
    ForEach-Object {
        [PSCustomObject]@{
            SamAccountName = $_.SamAccountName
            DisplayName    = $_.DisplayName
            Email          = $_.EmailAddress
            Department     = $_.Department
            Title          = $_.Title
            LastLogon      = if ($_.LastLogonDate) { $_.LastLogonDate.ToString("yyyy-MM-dd") } else { "Never" }
            DaysInactive   = if ($_.LastLogonDate) { [int](((Get-Date) - $_.LastLogonDate).TotalDays) } else { 999 }
            OU             = ($_.DistinguishedName -replace '^CN=[^,]+,', '')
        }
    }

    Write-Log "Found $($stale.Count) stale accounts (inactive >$days days)." "$(if ($stale.Count -gt 0) { 'Yellow' } else { 'Green' })"

    if ($stale.Count -gt 0) {
        $stale | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
        Write-Log "Report saved to: $outputFile" "Green"

        Write-Host ""
        Write-Host "  Top 10 most stale:" -ForegroundColor DarkGray
        $stale | Select-Object -Last 10 | ForEach-Object {
            Write-Host ("  {0,-25} Last logon: {1}  ({2} days)" -f $_.SamAccountName, $_.LastLogon, $_.DaysInactive) -ForegroundColor Yellow
        }
    }
} catch {
    Write-Log "Error querying AD: $($_.Exception.Message)" "Red"
    exit 1
}
