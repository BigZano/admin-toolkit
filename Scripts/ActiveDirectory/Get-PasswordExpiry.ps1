# Report on Active Directory user password expiry across the domain

param(
    [Parameter(Mandatory=$false)]
    [string]$DaysUntilExpiry = "30",
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

$days = [int]$DaysUntilExpiry
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "PasswordExpiry_${days}days_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "PasswordExpiry_$timestamp.log"

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

Write-Log "Retrieving domain password policy..." "Cyan"
$domainPolicy = Get-ADDefaultDomainPasswordPolicy
$maxAge = $domainPolicy.MaxPasswordAge

if ($maxAge.TotalDays -eq 0) {
    Write-Log "Domain password policy has no maximum age set (passwords never expire by policy)." "Yellow"
}

Write-Log "Scanning all enabled users..." "Cyan"

try {
    $now = Get-Date
    $warnDate = $now.AddDays($days)

    $report = Get-ADUser -Filter { Enabled -eq $true -and PasswordNeverExpires -eq $false } `
        -Properties DisplayName, EmailAddress, PasswordLastSet, PasswordNeverExpires, Department |
    Where-Object { $_.PasswordLastSet -ne $null } |
    ForEach-Object {
        # Check for Fine-Grained Password Policy first
        $fgpp = Get-ADUserResultantPasswordPolicy $_ -ErrorAction SilentlyContinue
        $effectiveMaxAge = if ($fgpp) { $fgpp.MaxPasswordAge } else { $maxAge }

        if ($effectiveMaxAge.TotalDays -eq 0) { return }

        $expiry = $_.PasswordLastSet + $effectiveMaxAge
        $daysLeft = [int](($expiry - $now).TotalDays)

        if ($expiry -le $warnDate) {
            [PSCustomObject]@{
                SamAccountName  = $_.SamAccountName
                DisplayName     = $_.DisplayName
                Email           = $_.EmailAddress
                Department      = $_.Department
                PasswordLastSet = $_.PasswordLastSet.ToString("yyyy-MM-dd")
                ExpiryDate      = $expiry.ToString("yyyy-MM-dd")
                DaysRemaining   = $daysLeft
                Status          = if ($daysLeft -lt 0) { "EXPIRED" } elseif ($daysLeft -le 7) { "Critical" } else { "Warning" }
            }
        }
    } | Sort-Object DaysRemaining

    $expired  = @($report | Where-Object { $_.Status -eq "EXPIRED" })
    $critical = @($report | Where-Object { $_.Status -eq "Critical" })
    $warning  = @($report | Where-Object { $_.Status -eq "Warning" })

    Write-Log "Expired: $($expired.Count)  |  Critical (<=7d): $($critical.Count)  |  Warning (<=${days}d): $($warning.Count)" "$(if ($expired.Count -gt 0) { 'Red' } elseif ($critical.Count -gt 0) { 'Yellow' } else { 'Green' })"

    if ($report.Count -gt 0) {
        $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
        Write-Log "Report saved to: $outputFile" "Green"

        if ($expired.Count -gt 0) {
            Write-Host ""
            Write-Host "  EXPIRED accounts:" -ForegroundColor Red
            $expired | ForEach-Object {
                Write-Host ("  {0,-25} Expired: {1}  ({2} days ago)" -f $_.SamAccountName, $_.ExpiryDate, [Math]::Abs($_.DaysRemaining)) -ForegroundColor Red
            }
        }
        if ($critical.Count -gt 0) {
            Write-Host ""
            Write-Host "  Expiring within 7 days:" -ForegroundColor Yellow
            $critical | ForEach-Object {
                Write-Host ("  {0,-25} Expires: {1}  ({2} days)" -f $_.SamAccountName, $_.ExpiryDate, $_.DaysRemaining) -ForegroundColor Yellow
            }
        }
    } else {
        Write-Log "No accounts expiring within $days days." "Green"
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"
    exit 1
}
