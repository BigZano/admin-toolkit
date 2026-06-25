# Full account recovery: show status, unlock, reset password, and force change at next logon

param(
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$false)]
    [string]$NewPassword = "",
    [Parameter(Mandatory=$false)]
    [string]$ForceChangeAtLogon = "true"
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "$(Get-Date -Format 'HH:mm:ss')  $Message" -ForegroundColor $Color
}

function Show-AccountStatus {
    param($User)
    $pwExpiry = "N/A"
    if (-not $User.PasswordNeverExpires -and $User.PasswordLastSet) {
        $maxAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge
        $expiry = $User.PasswordLastSet + $maxAge
        $daysLeft = [int](($expiry - (Get-Date)).TotalDays)
        $pwExpiry = "$($expiry.ToString('yyyy-MM-dd'))  ($daysLeft days)"
    } elseif ($User.PasswordNeverExpires) {
        $pwExpiry = "Never expires"
    }

    Write-Host ""
    Write-Host ("  {0,-22} {1}" -f "Display Name:", $User.DisplayName) -ForegroundColor Yellow
    Write-Host ("  {0,-22} {1}" -f "SAM Account:", $User.SamAccountName) -ForegroundColor Gray

    $enabledColor = if ($User.Enabled) { "Green" } else { "Red" }
    $lockedColor  = if ($User.LockedOut) { "Red" } else { "Green" }
    $pwSetColor   = if ($User.PasswordLastSet) { "White" } else { "Red" }

    Write-Host ("  {0,-22} {1}" -f "Enabled:", $User.Enabled) -ForegroundColor $enabledColor
    Write-Host ("  {0,-22} {1}" -f "Locked Out:", $User.LockedOut) -ForegroundColor $lockedColor
    Write-Host ("  {0,-22} {1}" -f "Password Last Set:", $(if ($User.PasswordLastSet) { $User.PasswordLastSet.ToString("yyyy-MM-dd HH:mm") } else { "Never" })) -ForegroundColor $pwSetColor
    Write-Host ("  {0,-22} {1}" -f "Password Expiry:", $pwExpiry) -ForegroundColor White
    Write-Host ("  {0,-22} {1}" -f "Last Logon:", $(if ($User.LastLogonDate) { $User.LastLogonDate.ToString("yyyy-MM-dd HH:mm") } else { "Never" })) -ForegroundColor White
    Write-Host ""
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Log "ActiveDirectory module not found. Install RSAT." "Red"; exit 1
}

try {
    $user = Get-ADUser -Identity $Username -Properties `
        DisplayName, Enabled, LockedOut, PasswordLastSet, PasswordNeverExpires,
        LastLogonDate, PasswordExpired -ErrorAction Stop
} catch {
    Write-Log "User '$Username' not found: $($_.Exception.Message)" "Red"; exit 1
}

Write-Host ""
Write-Host ("=" * 55) -ForegroundColor DarkGray
Write-Host "  BEFORE" -ForegroundColor DarkGray
Write-Host ("=" * 55) -ForegroundColor DarkGray
Show-AccountStatus $user

$actions = [System.Collections.Generic.List[string]]::new()

# Unlock if locked
if ($user.LockedOut) {
    try {
        Unlock-ADAccount -Identity $Username -ErrorAction Stop
        Write-Log "Account unlocked." "Green"
        $actions.Add("Unlocked")
    } catch {
        Write-Log "Failed to unlock: $($_.Exception.Message)" "Red"
    }
}

# Enable if disabled
if (-not $user.Enabled) {
    Write-Log "Account is DISABLED. Unlock will not restore access." "Yellow"
    Write-Log "To re-enable: Enable-ADAccount -Identity $Username" "Yellow"
}

# Reset password if provided
if (-not [string]::IsNullOrEmpty($NewPassword)) {
    try {
        $secure = ConvertTo-SecureString $NewPassword -AsPlainText -Force
        Set-ADAccountPassword -Identity $Username -NewPassword $secure -Reset -ErrorAction Stop

        $mustChange = $ForceChangeAtLogon -eq "true" -or $ForceChangeAtLogon -eq "1"
        if ($mustChange) {
            Set-ADUser -Identity $Username -ChangePasswordAtLogon $true -ErrorAction Stop
            Write-Log "Password reset. User must change at next logon." "Green"
            $actions.Add("Password reset (force change)")
        } else {
            Write-Log "Password reset." "Green"
            $actions.Add("Password reset")
        }
    } catch {
        Write-Log "Failed to reset password: $($_.Exception.Message)" "Red"
    }
} else {
    Write-Log "No new password provided — password not changed." "Yellow"
}

# Show after state
$updated = Get-ADUser -Identity $Username -Properties `
    DisplayName, Enabled, LockedOut, PasswordLastSet, PasswordNeverExpires, LastLogonDate, PasswordExpired

Write-Host ("=" * 55) -ForegroundColor DarkGray
Write-Host "  AFTER" -ForegroundColor DarkGray
Write-Host ("=" * 55) -ForegroundColor DarkGray
Show-AccountStatus $updated

if ($actions.Count -gt 0) {
    Write-Log "Actions taken: $($actions -join ' | ')" "Cyan"
} else {
    Write-Log "No changes made." "Yellow"
}
