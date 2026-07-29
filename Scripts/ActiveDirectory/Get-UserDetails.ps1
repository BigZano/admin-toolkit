# Get detailed information for an Active Directory user account

param(
    [Parameter(Mandatory=$true)]
    [string]$Username,
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

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $OutputDirectory "GetUserDetails_${Username}_$timestamp.log"

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

Write-Log "Looking up user: $Username" "Cyan"

try {
    $user = Get-ADUser -Identity $Username -Properties DisplayName, UserPrincipalName, EmailAddress, `
        Title, Department, Manager, Enabled, LockedOut, PasswordLastSet, PasswordNeverExpires, `
        LastLogonDate, Created, DistinguishedName -ErrorAction Stop
} catch {
    Write-Log "User '$Username' not found: $($_.Exception.Message)" "Red"
    exit 1
}

# Resolve password expiry (prefer Fine-Grained Password Policy if one applies)
$maxPasswordAge = $null
try {
    $fgpp = Get-ADUserResultantPasswordPolicy $user -ErrorAction Stop
    $maxPasswordAge = $fgpp.MaxPasswordAge
} catch {
    try {
        $maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy -ErrorAction Stop).MaxPasswordAge
    } catch {
        Write-Log "Could not read password policy: $($_.Exception.Message)" "Yellow"
    }
}
$passwordExpiry = if ($user.PasswordNeverExpires) {
    "Never expires"
} elseif (-not $maxPasswordAge -or $maxPasswordAge.TotalDays -le 0) {
    "No expiry policy"
} elseif ($user.PasswordLastSet) {
    ($user.PasswordLastSet + $maxPasswordAge).ToString("yyyy-MM-dd HH:mm")
} else {
    "Unknown"
}

# Last logon (LastLogonDate = replicated lastLogonTimestamp; may lag up to ~14 days)
$lastLogon = if ($user.LastLogonDate) { $user.LastLogonDate.ToString("yyyy-MM-dd HH:mm") } else { "Never" }

# Group memberships
try {
    $groups = (Get-ADPrincipalGroupMembership $user -ErrorAction Stop |
        Select-Object -ExpandProperty Name | Sort-Object) -join ", "
} catch {
    Write-Log "Could not retrieve group memberships: $($_.Exception.Message)" "Yellow"
    $groups = "<lookup failed>"
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host "  User: $($user.DisplayName) [$($user.SamAccountName)]" -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor DarkGray

$fields = [ordered]@{
    "Display Name"      = $user.DisplayName
    "UPN"               = $user.UserPrincipalName
    "SAM Account"       = $user.SamAccountName
    "Email"             = $user.EmailAddress
    "Title"             = $user.Title
    "Department"        = $user.Department
    "Manager"           = if ($user.Manager) { try { (Get-ADUser $user.Manager -ErrorAction Stop).Name } catch { $user.Manager } } else { "None" }
    "OU Path"           = ($user.DistinguishedName -replace '^CN=[^,]+,', '')
    "Account Enabled"   = $user.Enabled
    "Locked Out"        = $user.LockedOut
    "Password Last Set" = if ($user.PasswordLastSet) { $user.PasswordLastSet.ToString("yyyy-MM-dd HH:mm") } else { "Never" }
    "Password Expiry"   = $passwordExpiry
    "Pwd Never Expires" = $user.PasswordNeverExpires
    "Last Logon"        = $lastLogon
    "Created"           = $user.Created.ToString("yyyy-MM-dd")
    "Groups"            = $groups
}

foreach ($field in $fields.GetEnumerator()) {
    $color = switch ($field.Key) {
        "Account Enabled" { if ($field.Value) { "Green" } else { "Red" } }
        "Locked Out"      { if ($field.Value) { "Red" } else { "Green" } }
        default           { "Cyan" }
    }
    Write-Host ("  {0,-20} {1}" -f "$($field.Key):", $field.Value) -ForegroundColor $color
}

Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Log "User details retrieved successfully." "Green"
