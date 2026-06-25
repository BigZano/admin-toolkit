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
    $user = Get-ADUser -Identity $Username -Properties * -ErrorAction Stop
} catch {
    Write-Log "User '$Username' not found: $($_.Exception.Message)" "Red"
    exit 1
}

# Resolve password expiry
$maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge
$passwordExpiry = if ($user.PasswordNeverExpires) {
    "Never expires"
} elseif ($user.PasswordLastSet) {
    ($user.PasswordLastSet + $maxPasswordAge).ToString("yyyy-MM-dd HH:mm")
} else {
    "Unknown"
}

# Last logon (use the more recent of LastLogon and LastLogonDate)
$lastLogon = if ($user.LastLogonDate) { $user.LastLogonDate.ToString("yyyy-MM-dd HH:mm") } else { "Never" }

# Group memberships
$groups = (Get-ADPrincipalGroupMembership $user | Select-Object -ExpandProperty Name | Sort-Object) -join ", "

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
    "Manager"           = if ($user.Manager) { (Get-ADUser $user.Manager).Name } else { "None" }
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
