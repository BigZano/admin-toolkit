# Reset an Active Directory user password with optional force-change at next logon

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
if (-not $mustChange -and $ForceChangeAtLogon -notin @("false", "0")) {
    Write-Log "Unrecognized ForceChangeAtLogon value '$ForceChangeAtLogon' — treating as false." "Yellow"
}

if (-not $NewPassword -and [Console]::IsInputRedirected) {
    # Piped by the TUI: build the SecureString directly from stdin so a
    # full plaintext copy of the password never exists in this process.
    $securePassword = New-Object System.Security.SecureString
    # Read via an explicit UTF-8 reader rather than [Console]::In — the latter decodes using the inherited console code page, which silently corrupts non-ASCII passwords under a non-UTF-8 console.
    $reader = New-Object System.IO.StreamReader(
        [Console]::OpenStandardInput(),
        (New-Object System.Text.UTF8Encoding($false)))
    while (($ch = $reader.Read()) -notin -1, 13, 10) { $securePassword.AppendChar([char]$ch) }
    $securePassword.MakeReadOnly()
} elseif ($NewPassword) {
    $securePassword = ConvertTo-SecureString $NewPassword -AsPlainText -Force
} else {
    Write-Log "No new password supplied (use -NewPassword, or pipe one via stdin)." "Red"
    exit 1
}

if ($securePassword.Length -eq 0) {
    Write-Log "No new password supplied (use -NewPassword, or pipe one via stdin)." "Red"
    exit 1
}

try {
    Set-ADAccountPassword -Identity $Username -NewPassword $securePassword -Reset -ErrorAction Stop
} catch {
    Write-Log "Failed to reset password: $($_.Exception.Message)" "Red"
    exit 1
}

if ($mustChange) {
    try {
        Set-ADUser -Identity $Username -ChangePasswordAtLogon $true -ErrorAction Stop
        Write-Log "Password reset. User must change at next logon." "Green"
    } catch {
        Write-Log "Password was reset, but failed to set change-at-logon flag: $($_.Exception.Message)" "Red"
        exit 1
    }
} else {
    Write-Log "Password reset. No forced change at logon." "Green"
}
