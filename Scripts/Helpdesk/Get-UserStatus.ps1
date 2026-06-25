# Quick account health dashboard — locked, disabled, password state, last logon, groups

param(
    [Parameter(Mandatory=$true)]
    [string]$Username
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Log "ActiveDirectory module not found. Install RSAT." "Red"; exit 1
}

try {
    $user = Get-ADUser -Identity $Username -Properties `
        DisplayName, EmailAddress, Title, Department, Manager, Enabled, LockedOut,
        PasswordLastSet, PasswordNeverExpires, PasswordExpired, PasswordNotRequired,
        LastLogonDate, Created, DistinguishedName, MemberOf -ErrorAction Stop
} catch {
    Write-Log "User '$Username' not found: $($_.Exception.Message)" "Red"; exit 1
}

# Password expiry
$domainPolicy = Get-ADDefaultDomainPasswordPolicy
$maxAge = $domainPolicy.MaxPasswordAge
$pwExpiryStr = "N/A"
$daysUntilExpiry = $null
if (-not $user.PasswordNeverExpires -and $user.PasswordLastSet -and $maxAge.TotalDays -gt 0) {
    $expiry = $user.PasswordLastSet + $maxAge
    $daysUntilExpiry = [int](($expiry - (Get-Date)).TotalDays)
    $pwExpiryStr = "{0}  ({1} days)" -f $expiry.ToString("yyyy-MM-dd"), $daysUntilExpiry
} elseif ($user.PasswordNeverExpires) {
    $pwExpiryStr = "Never expires"
}

# Manager name
$managerName = if ($user.Manager) {
    try { (Get-ADUser $user.Manager).Name } catch { $user.Manager }
} else { "None" }

# Group count (excluding Domain Users)
$groupCount = ($user.MemberOf | Measure-Object).Count

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ("  {0}  [{1}]" -f $user.DisplayName, $user.SamAccountName) -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""

# Identity block
Write-Host ("  {0,-22} {1}" -f "Email:",      $user.EmailAddress)  -ForegroundColor Gray
Write-Host ("  {0,-22} {1}" -f "Title:",      $user.Title)         -ForegroundColor Gray
Write-Host ("  {0,-22} {1}" -f "Department:", $user.Department)    -ForegroundColor Gray
Write-Host ("  {0,-22} {1}" -f "Manager:",    $managerName)        -ForegroundColor Gray
Write-Host ("  {0,-22} {1}" -f "Created:",    $user.Created.ToString("yyyy-MM-dd")) -ForegroundColor Gray
Write-Host ""

# Status block — color coded for quick triage
$enabledColor = if ($user.Enabled)   { "Green" } else { "Red" }
$lockedColor  = if ($user.LockedOut) { "Red" }   else { "Green" }

Write-Host ("  {0,-22} {1}" -f "Enabled:",    $user.Enabled)   -ForegroundColor $enabledColor
Write-Host ("  {0,-22} {1}" -f "Locked Out:", $user.LockedOut) -ForegroundColor $lockedColor

$pwSetColor = if (-not $user.PasswordLastSet) { "Red" } else { "White" }
Write-Host ("  {0,-22} {1}" -f "Password Set:", $(if ($user.PasswordLastSet) { $user.PasswordLastSet.ToString("yyyy-MM-dd HH:mm") } else { "NEVER SET" })) -ForegroundColor $pwSetColor

$pwExpiryColor = if ($user.PasswordExpired) { "Red" }
                 elseif ($daysUntilExpiry -ne $null -and $daysUntilExpiry -le 7) { "Red" }
                 elseif ($daysUntilExpiry -ne $null -and $daysUntilExpiry -le 30) { "Yellow" }
                 else { "White" }
Write-Host ("  {0,-22} {1}" -f "Password Expiry:", $pwExpiryStr) -ForegroundColor $pwExpiryColor

if ($user.PasswordExpired) {
    Write-Host "  !! Password is EXPIRED" -ForegroundColor Red
}

$logonColor = if (-not $user.LastLogonDate) { "Yellow" }
              elseif ((Get-Date) - $user.LastLogonDate -gt [TimeSpan]::FromDays(90)) { "Yellow" }
              else { "White" }
Write-Host ("  {0,-22} {1}" -f "Last Logon:", $(if ($user.LastLogonDate) { $user.LastLogonDate.ToString("yyyy-MM-dd HH:mm") } else { "Never" })) -ForegroundColor $logonColor
Write-Host ("  {0,-22} {1} groups" -f "Group Memberships:", $groupCount) -ForegroundColor White
Write-Host ""

# Summary line
$issues = @()
if (-not $user.Enabled)         { $issues += "DISABLED" }
if ($user.LockedOut)            { $issues += "LOCKED" }
if ($user.PasswordExpired)      { $issues += "PASSWORD EXPIRED" }
if (-not $user.PasswordLastSet) { $issues += "PASSWORD NEVER SET" }
if ($daysUntilExpiry -ne $null -and $daysUntilExpiry -le 0) { $issues += "PASSWORD EXPIRED" }

if ($issues.Count -gt 0) {
    Write-Host ("  STATUS: {0}" -f ($issues -join "  |  ")) -ForegroundColor Red
} else {
    Write-Host "  STATUS: OK" -ForegroundColor Green
}
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""
