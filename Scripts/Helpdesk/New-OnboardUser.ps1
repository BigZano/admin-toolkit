# Create a new AD user for onboarding, with optional group template copy from an existing user

param(
    [Parameter(Mandatory=$true)]
    [string]$FirstName,
    [Parameter(Mandatory=$true)]
    [string]$LastName,
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$false)]
    [string]$Password = "",
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
    $existing = Get-ADUser -Identity $Username -ErrorAction Stop
    if ($existing) {
        Write-Log "Username '$Username' already exists in AD." "Red"; exit 1
    }
} catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    # Username is free — proceed.
} catch {
    Write-Log "Could not verify username availability: $($_.Exception.Message)" "Red"; exit 1
}

try {
    $domain = Get-ADDomain -ErrorAction Stop
} catch {
    Write-Log "Could not contact the domain: $($_.Exception.Message)" "Red"; exit 1
}

$displayName = "$FirstName $LastName"
$upnSuffix   = $domain.DNSRoot
$upn         = "$Username@$upnSuffix"

# Resolve OU — fall back to default Users container
$ou = if (-not [string]::IsNullOrEmpty($TargetOU)) {
    $TargetOU
} else {
    $domain.UsersContainer
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ("  ONBOARDING: {0}  [{1}]" -f $displayName, $Username) -ForegroundColor Yellow
Write-Host ("  UPN: {0}  |  OU: {1}" -f $upn, $ou) -ForegroundColor Gray
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""

if (-not $Password -and [Console]::IsInputRedirected) {
    $secure = New-Object System.Security.SecureString
    # Read via an explicit UTF-8 reader rather than [Console]::In — the latter decodes using the inherited console code page, which silently corrupts non-ASCII passwords under a non-UTF-8 console.
    $reader = New-Object System.IO.StreamReader(
        [Console]::OpenStandardInput(),
        (New-Object System.Text.UTF8Encoding($false)))
    while (($ch = $reader.Read()) -notin -1, 13, 10) { $secure.AppendChar([char]$ch) }
    $secure.MakeReadOnly()
} elseif ($Password) {
    $secure = ConvertTo-SecureString $Password -AsPlainText -Force
} else {
    Write-Log "No password supplied (use -Password, or pipe one via stdin)." "Red"
    exit 1
}

if ($secure.Length -eq 0) {
    Write-Log "No password supplied (use -Password, or pipe one via stdin)." "Red"
    exit 1
}

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
        AccountPassword       = $secure
        Enabled               = $true
        ChangePasswordAtLogon = $true
        Path                  = $ou
    }
    if ($Title)      { $params["Title"]      = $Title }
    if ($Department) { $params["Department"] = $Department }

    New-ADUser @params -ErrorAction Stop
    Write-Log "Account created: $Username  ($upn)" "Green"
} catch {
    Write-Log "Failed to create account: $($_.Exception.Message)" "Red"
    # A failed New-ADUser (e.g. password complexity) can leave a partial, disabled account behind.
    try {
        $partial = Get-ADUser -Identity $Username -Properties Enabled -ErrorAction Stop
        Write-Log "WARNING: a partial account '$Username' now exists (Enabled=$($partial.Enabled)). Fix or remove it before retrying." "Yellow"
    } catch {
        Write-Log "No partial account was left behind." "Yellow"
    }
    exit 1
}

# ── Copy groups from template user ────────────────────────────────────────────
if (-not [string]::IsNullOrEmpty($TemplateUser)) {
    Write-Log "Copying groups from template user: $TemplateUser" "Cyan"
    try {
        $template = Get-ADUser -Identity $TemplateUser -Properties MemberOf -ErrorAction Stop
        $copied = 0
        foreach ($groupDN in $template.MemberOf) {
            try {
                $groupName = (Get-ADGroup $groupDN -ErrorAction Stop).Name
                # New user is already in Domain Users via primary group — adding again would error.
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
try {
    $created = Get-ADUser -Identity $Username -Properties DisplayName, Enabled, MemberOf, DistinguishedName -ErrorAction Stop
} catch {
    Write-Log "Account was created but final verification lookup failed: $($_.Exception.Message)" "Yellow"
    exit 0
}
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
