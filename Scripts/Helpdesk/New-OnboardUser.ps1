# Create a new AD user for onboarding, with optional group template copy from an existing user

param(
    [Parameter(Mandatory=$true)]
    [string]$FirstName,
    [Parameter(Mandatory=$true)]
    [string]$LastName,
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$true)]
    [string]$Password,
    [Parameter(Mandatory=$false)]
    [string]$Title = "",
    [Parameter(Mandatory=$false)]
    [string]$Department = "",
    [Parameter(Mandatory=$false)]
    [string]$TargetOU = "",
    [Parameter(Mandatory=$false)]
    [string]$TemplateUser = ""
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

# Check username not already taken
try {
    $existing = Get-ADUser -Identity $Username -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Log "Username '$Username' already exists in AD." "Red"; exit 1
    }
} catch { }

$displayName = "$FirstName $LastName"
$upnSuffix   = (Get-ADDomain).DNSRoot
$upn         = "$Username@$upnSuffix"

# Resolve OU — fall back to default Users container
$ou = if (-not [string]::IsNullOrEmpty($TargetOU)) {
    $TargetOU
} else {
    (Get-ADDomain).UsersContainer
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ("  ONBOARDING: {0}  [{1}]" -f $displayName, $Username) -ForegroundColor Yellow
Write-Host ("  UPN: {0}  |  OU: {1}" -f $upn, $ou) -ForegroundColor Gray
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""

# ── Create the account ────────────────────────────────────────────────────────
Write-Log "Creating AD account..." "Cyan"
try {
    $params = @{
        SamAccountName        = $Username
        UserPrincipalName     = $upn
        Name                  = $displayName
        GivenName             = $FirstName
        Surname               = $LastName
        DisplayName           = $displayName
        AccountPassword       = (ConvertTo-SecureString $Password -AsPlainText -Force)
        Enabled               = $true
        ChangePasswordAtLogon = $true
        Path                  = $ou
    }
    if ($Title)      { $params["Title"]      = $Title }
    if ($Department) { $params["Department"] = $Department }

    New-ADUser @params -ErrorAction Stop
    Write-Log "Account created: $Username  ($upn)" "Green"
} catch {
    Write-Log "Failed to create account: $($_.Exception.Message)" "Red"; exit 1
}

# ── Copy groups from template user ────────────────────────────────────────────
if (-not [string]::IsNullOrEmpty($TemplateUser)) {
    Write-Log "Copying groups from template user: $TemplateUser" "Cyan"
    try {
        $template = Get-ADUser -Identity $TemplateUser -Properties MemberOf -ErrorAction Stop
        $copied = 0
        foreach ($groupDN in $template.MemberOf) {
            try {
                $groupName = (Get-ADGroup $groupDN).Name
                if ($groupName -eq "Domain Users") { continue }
                Add-ADGroupMember -Identity $groupDN -Members $Username -ErrorAction Stop
                Write-Log "  Added to: $groupName" "Green"
                $copied++
            } catch {
                Write-Log "  Could not add to $groupDN : $($_.Exception.Message)" "Yellow"
            }
        }
        Write-Log "Copied $copied group(s) from $TemplateUser." "Green"
    } catch {
        Write-Log "Template user '$TemplateUser' not found: $($_.Exception.Message)" "Yellow"
    }
}

# ── Confirm final state ───────────────────────────────────────────────────────
$created = Get-ADUser -Identity $Username -Properties DisplayName, Enabled, MemberOf, DistinguishedName
$groupCount = ($created.MemberOf | Measure-Object).Count

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host "  ACCOUNT CREATED" -ForegroundColor Green
Write-Host ("  {0,-20} {1}" -f "Username:", $created.SamAccountName) -ForegroundColor White
Write-Host ("  {0,-20} {1}" -f "UPN:", $upn) -ForegroundColor White
Write-Host ("  {0,-20} {1}" -f "Display Name:", $created.DisplayName) -ForegroundColor White
Write-Host ("  {0,-20} {1}" -f "Enabled:", $created.Enabled) -ForegroundColor Green
Write-Host ("  {0,-20} {1} group(s)" -f "Group Memberships:", $groupCount) -ForegroundColor White
Write-Host ("  {0,-20} {1}" -f "OU:", ($created.DistinguishedName -replace '^CN=[^,]+,', '')) -ForegroundColor Gray
Write-Host ("  {0,-20} Must change at first logon" -f "Password:") -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""
