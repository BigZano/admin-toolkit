# Remove a user from an Active Directory group

param(
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$true)]
    [string]$GroupName
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "  $(Get-Date -Format 'HH:mm:ss')  $Message" -ForegroundColor $Color
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Log "ActiveDirectory module not found. Install RSAT." "Red"; exit 1
}

try {
    $user  = Get-ADUser  -Identity $Username  -Properties DisplayName -ErrorAction Stop
    $group = Get-ADGroup -Identity $GroupName -Properties Description  -ErrorAction Stop
} catch {
    Write-Log "Lookup failed: $($_.Exception.Message)" "Red"; exit 1
}

Write-Host ""
Write-Host ("  User:  {0}  [{1}]" -f $user.DisplayName, $user.SamAccountName) -ForegroundColor Yellow
Write-Host ("  Group: {0}" -f $group.Name) -ForegroundColor Cyan
if ($group.Description) {
    Write-Host ("  Desc:  {0}" -f $group.Description) -ForegroundColor Gray
}
Write-Host ""

# Block removal from Domain Users — primary group, can't be removed
if ($group.Name -eq "Domain Users") {
    Write-Log "Cannot remove from 'Domain Users' — it is the primary group." "Red"; exit 1
}

# Check membership
$isMember = Get-ADGroupMember -Identity $GroupName |
    Where-Object { $_.SamAccountName -eq $Username }

if (-not $isMember) {
    Write-Log "$($user.SamAccountName) is not a direct member of '$($group.Name)'." "Yellow"
    exit 0
}

try {
    Remove-ADGroupMember -Identity $GroupName -Members $Username -Confirm:$false -ErrorAction Stop
    Write-Log "Removed '$($user.SamAccountName)' from '$($group.Name)'." "Green"
} catch {
    Write-Log "Failed to remove from group: $($_.Exception.Message)" "Red"; exit 1
}
