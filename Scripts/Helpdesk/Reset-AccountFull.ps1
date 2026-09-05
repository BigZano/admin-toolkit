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
    if (-not $script:domainMaxAgeChecked) {
        $script:domainMaxAgeChecked = $true
        try {
            $script:domainMaxAge = (Get-ADDefaultDomainPasswordPolicy -ErrorAction Stop).MaxPasswordAge
        } catch {
            Write-Log "Could not read domain password policy: $($_.Exception.Message)" "Yellow"
            $script:domainMaxAge = $null
        }
    }
    if (-not $User.PasswordNeverExpires -and $User.PasswordLastSet -and
        $script:domainMaxAge -and $script:domainMaxAge.TotalDays -gt 0) {
        $expiry = $User.PasswordLastSet + $script:domainMaxAge
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
$hadError = $false

# Unlock if locked
if ($user.LockedOut) {
    try {
        Unlock-ADAccount -Identity $Username -ErrorAction Stop
        Write-Log "Account unlocked." "Green"
        $actions.Add("Unlocked")
    } catch {
        Write-Log "Failed to unlock: $($_.Exception.Message)" "Red"
        $hadError = $true
    }
}

# Enable if disabled
if (-not $user.Enabled) {
    Write-Log "Account is DISABLED. Unlock will not restore access." "Yellow"
    Write-Log "To re-enable: Enable-ADAccount -Identity $Username" "Yellow"
}

# Build the secure password up front — from -NewPassword if given, or piped
# via stdin by the TUI (so a full plaintext copy never exists in this
# process). A direct/interactive run with neither yields an empty
# SecureString, treated the same as "not provided" below — password reset
# is an optional step in this script (unlock/status-check can run without it).
if (-not $NewPassword -and [Console]::IsInputRedirected) {
    $secure = New-Object System.Security.SecureString
    # Read via an explicit UTF-8 reader rather than [Console]::In — the latter decodes using the inherited console code page, which silently corrupts non-ASCII passwords under a non-UTF-8 console.
    $reader = New-Object System.IO.StreamReader(
        [Console]::OpenStandardInput(),
        (New-Object System.Text.UTF8Encoding($false)))
    while (($ch = $reader.Read()) -notin -1, 13, 10) { $secure.AppendChar([char]$ch) }
    $secure.MakeReadOnly()
} elseif ($NewPassword) {
    $secure = ConvertTo-SecureString $NewPassword -AsPlainText -Force
} else {
    $secure = New-Object System.Security.SecureString
}

# Reset password if provided
if ($secure.Length -gt 0) {
    $pwReset = $false
    try {
        Set-ADAccountPassword -Identity $Username -NewPassword $secure -Reset -ErrorAction Stop
        $pwReset = $true
    } catch {
        Write-Log "Failed to reset password: $($_.Exception.Message)" "Red"
        $hadError = $true
    }

    if ($pwReset) {
        $mustChange = $ForceChangeAtLogon -eq "true" -or $ForceChangeAtLogon -eq "1"
        if ($mustChange) {
            try {
                Set-ADUser -Identity $Username -ChangePasswordAtLogon $true -ErrorAction Stop
                Write-Log "Password reset. User must change at next logon." "Green"
                $actions.Add("Password reset (force change)")
            } catch {
                Write-Log "Password was reset, but failed to set change-at-logon flag: $($_.Exception.Message)" "Red"
                $actions.Add("Password reset (change-at-logon flag FAILED)")
                $hadError = $true
            }
        } else {
            Write-Log "Password reset." "Green"
            $actions.Add("Password reset")
        }
    }
} else {
    Write-Log "No new password provided — password not changed." "Yellow"
}

# Show after state
try {
    $updated = Get-ADUser -Identity $Username -Properties `
        DisplayName, Enabled, LockedOut, PasswordLastSet, PasswordNeverExpires, LastLogonDate, PasswordExpired -ErrorAction Stop

    Write-Host ("=" * 55) -ForegroundColor DarkGray
    Write-Host "  AFTER" -ForegroundColor DarkGray
    Write-Host ("=" * 55) -ForegroundColor DarkGray
    Show-AccountStatus $updated
} catch {
    Write-Log "Could not retrieve updated account state: $($_.Exception.Message)" "Yellow"
}

if ($actions.Count -gt 0) {
    Write-Log "Actions taken: $($actions -join ' | ')" "Cyan"
} else {
    Write-Log "No changes made." "Yellow"
}

if ($hadError) {
    Write-Log "One or more recovery steps FAILED — review the messages above." "Red"
    exit 1
}
