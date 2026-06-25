# Reset an Active Directory user password with optional force-change at next logon

param(
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$true)]
    [string]$NewPassword,
    [Parameter(Mandatory=$false)]
    [string]$ForceChangeAtLogon = "true"
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "$(Get-Date -Format 'HH:mm:ss') $Message" -ForegroundColor $Color
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Log "ActiveDirectory module not found. Install RSAT." "Red"
    exit 1
}

Write-Log "Looking up user: $Username" "Cyan"

try {
    $user = Get-ADUser -Identity $Username -Properties DisplayName, Enabled, PasswordLastSet -ErrorAction Stop
} catch {
    Write-Log "User '$Username' not found: $($_.Exception.Message)" "Red"
    exit 1
}

Write-Host ""
Write-Host "  User:    $($user.DisplayName) [$($user.SamAccountName)]" -ForegroundColor Yellow
Write-Host "  Enabled: $($user.Enabled)" -ForegroundColor $(if ($user.Enabled) { "Green" } else { "Red" })
Write-Host ""

$mustChange = $ForceChangeAtLogon -eq "true" -or $ForceChangeAtLogon -eq "1"

try {
    $securePassword = ConvertTo-SecureString $NewPassword -AsPlainText -Force
    Set-ADAccountPassword -Identity $Username -NewPassword $securePassword -Reset -ErrorAction Stop

    if ($mustChange) {
        Set-ADUser -Identity $Username -ChangePasswordAtLogon $true -ErrorAction Stop
        Write-Log "Password reset. User must change at next logon." "Green"
    } else {
        Write-Log "Password reset. No forced change at logon." "Green"
    }
} catch {
    Write-Log "Failed to reset password: $($_.Exception.Message)" "Red"
    exit 1
}
