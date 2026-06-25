# Disable an Active Directory user account for offboarding

param(
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$false)]
    [string]$DisabledUsersOU = ""
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
    $user = Get-ADUser -Identity $Username -Properties DisplayName, Enabled, DistinguishedName -ErrorAction Stop
} catch {
    Write-Log "User '$Username' not found: $($_.Exception.Message)" "Red"
    exit 1
}

Write-Host ""
Write-Host "  User:    $($user.DisplayName) [$($user.SamAccountName)]" -ForegroundColor Yellow
Write-Host "  Enabled: $($user.Enabled)" -ForegroundColor $(if ($user.Enabled) { "Green" } else { "Yellow" })
Write-Host "  DN:      $($user.DistinguishedName)" -ForegroundColor Gray
Write-Host ""

if (-not $user.Enabled) {
    Write-Log "Account is already disabled." "Yellow"
} else {
    try {
        Disable-ADAccount -Identity $Username -ErrorAction Stop
        Write-Log "Account disabled." "Green"
    } catch {
        Write-Log "Failed to disable account: $($_.Exception.Message)" "Red"
        exit 1
    }
}

if (-not [string]::IsNullOrEmpty($DisabledUsersOU)) {
    try {
        Move-ADObject -Identity $user.DistinguishedName -TargetPath $DisabledUsersOU -ErrorAction Stop
        Write-Log "Account moved to: $DisabledUsersOU" "Green"
    } catch {
        Write-Log "Failed to move account to OU: $($_.Exception.Message)" "Red"
    }
}

Write-Log "Offboarding complete for $($user.DisplayName)." "Cyan"
