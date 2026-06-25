# Unlock a locked Active Directory user account

param(
    [Parameter(Mandatory=$true)]
    [string]$Username
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

Write-Log "Checking account status for: $Username" "Cyan"

try {
    $user = Get-ADUser -Identity $Username -Properties LockedOut, DisplayName, Enabled -ErrorAction Stop
} catch {
    Write-Log "User '$Username' not found: $($_.Exception.Message)" "Red"
    exit 1
}

Write-Host ""
Write-Host "  User:    $($user.DisplayName) [$($user.SamAccountName)]" -ForegroundColor Yellow
Write-Host "  Enabled: $($user.Enabled)" -ForegroundColor $(if ($user.Enabled) { "Green" } else { "Red" })
Write-Host "  Locked:  $($user.LockedOut)" -ForegroundColor $(if ($user.LockedOut) { "Red" } else { "Green" })
Write-Host ""

if (-not $user.LockedOut) {
    Write-Log "Account is not locked. No action taken." "Yellow"
    exit 0
}

if (-not $user.Enabled) {
    Write-Log "Account is disabled. Unlock may not resolve login issues." "Yellow"
}

try {
    Unlock-ADAccount -Identity $Username -ErrorAction Stop
    $verify = Get-ADUser -Identity $Username -Properties LockedOut
    if (-not $verify.LockedOut) {
        Write-Log "Account unlocked successfully." "Green"
    } else {
        Write-Log "Unlock command ran but account still appears locked." "Yellow"
    }
} catch {
    Write-Log "Failed to unlock account: $($_.Exception.Message)" "Red"
    exit 1
}
