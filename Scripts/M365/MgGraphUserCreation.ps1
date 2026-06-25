# Create new Microsoft 365 user with optional license assignment via Microsoft Graph

param(
    [Parameter(Mandatory=$false)]
    [string]$DisplayName,
    [Parameter(Mandatory=$false)]
    [string]$UserPrincipalName,
    [Parameter(Mandatory=$false)]
    [string]$UsageLocation,
    [Parameter(Mandatory=$false)]
    [string]$Password,
    [Parameter(Mandatory=$false)]
    [string]$LicenseSKU = "",
    [Parameter(Mandatory=$false)]
    [int]$LicenseIndex = -1,
    [Parameter(Mandatory=$false)]
    [switch]$ListLicenses,
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

# Set output directory (OS agnostic)
if ([string]::IsNullOrEmpty($OutputDirectory)) {
    if ($IsWindows -or $env:OS -match "Windows") {
        $OutputDirectory = Join-Path -Path $env:USERPROFILE -ChildPath "Documents\M365Reports"
    } else {
        $OutputDirectory = Join-Path -Path $env:HOME -ChildPath "Documents/M365Reports"
    }
}

# Create output directory if it doesn't exist
if (-not (Test-Path -Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

# Setup log file
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $OutputDirectory "UserCreation_$($UserPrincipalName.Split('@')[0])_$timestamp.log"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    $logMessage | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "==========================================" "Cyan"
Write-Log "       Microsoft 365 User Creation" "Cyan"
Write-Log "==========================================" "Cyan"
Write-Log ""

# Validate license selection exclusivity
if (-not $ListLicenses -and $LicenseSKU -ne "" -and $LicenseIndex -ge 0) {
    Write-Log "FATAL: Specify either LicenseSKU OR LicenseIndex, not both." "Red"
    Write-Log "SOLUTION: Use -LicenseSKU <SkuPartNumber> OR -LicenseIndex <Number> after listing." "Yellow"
    exit 2
}

# If not listing licenses, ensure required user creation params are present
if (-not $ListLicenses) {
    $missing = @()
    if (-not $DisplayName) { $missing += 'DisplayName' }
    if (-not $UserPrincipalName) { $missing += 'UserPrincipalName' }
    if (-not $UsageLocation) { $missing += 'UsageLocation' }
    if (-not $Password) { $missing += 'Password' }
    if ($missing.Count -gt 0) {
        Write-Log "FATAL: Missing required parameters: $($missing -join ', ')" "Red"
        Write-Log "SOLUTION: Provide all mandatory fields for user creation or use -ListLicenses mode." "Yellow"
        exit 2
    }
}

# Validate UsageLocation format (should be 2-letter ISO code)
if (-not $ListLicenses -and $UsageLocation.Length -ne 2) {
    Write-Log "FATAL: UsageLocation must be a 2-letter ISO country code (e.g., 'US', 'GB', 'CA')" "Red"
    Write-Log "SOLUTION: Provide a valid ISO 3166-1 alpha-2 country code" "Yellow"
    exit 2
}
if (-not $ListLicenses) { $UsageLocation = $UsageLocation.ToUpper() }

# Convert user password to SecureString (no admin password needed with OAuth)
if (-not $ListLicenses) {
    Write-Log "Converting user password to secure format..." "Yellow"
    $secureUserPassword = ConvertTo-SecureString $Password -AsPlainText -Force
    # Clear plain text password from memory
    $Password = $null
    [System.GC]::Collect()
}

Write-Log ""
Write-Log "Connecting to Microsoft Graph with interactive authentication..." "Yellow"

# Import required module
try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.Users -ErrorAction Stop
} catch {
    Write-Log "FATAL: Failed to import Microsoft Graph modules: $($_.Exception.Message)" "Red"
    Write-Log "SOLUTION: Install modules with: Install-Module Microsoft.Graph -Scope CurrentUser" "Yellow"
    exit 1
}

# Connect to Microsoft Graph with interactive OAuth2 (supports MFA)
try {
    Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All", "Organization.Read.All" -NoWelcome -ErrorAction Stop
    $context = Get-MgContext
    Write-Log "Successfully connected to Microsoft Graph" "Green"
    Write-Log "Authenticated as: $($context.Account)" "Green"
    Write-Log "Authentication Type: Interactive (MFA Supported)" "Green"
} catch {
    Write-Log "FATAL: Failed to connect to Microsoft Graph: $($_.Exception.Message)" "Red"
    Write-Log "SOLUTION: Verify you have User.ReadWrite.All and Directory.ReadWrite.All permissions" "Yellow"
    exit 1
}

Write-Log ""
if (-not $ListLicenses) {
    Write-Log "User Details to Create:" "Cyan"
    Write-Log "  Display Name:        $DisplayName" "White"
    Write-Log "  User Principal Name: $UserPrincipalName" "White"
    Write-Log "  Usage Location:      $UsageLocation" "White"
    Write-Log "  Mail Nickname:       $($UserPrincipalName.Split('@')[0])" "White"
    Write-Log ""
}

# Check if user already exists
Write-Log "Checking if user already exists..." "Yellow"
try {
    $existingUser = Get-MgUser -Filter "userPrincipalName eq '$UserPrincipalName'" -ErrorAction SilentlyContinue
    if ($existingUser) {
        Write-Log "FATAL: User '$UserPrincipalName' already exists!" "Red"
        Write-Log "SOLUTION: Use a different UserPrincipalName or delete the existing user first" "Yellow"
        Disconnect-MgGraph | Out-Null
        exit 2
    }
    Write-Log "User does not exist - proceeding with creation" "Green"
} catch {
    Write-Log "WARNING: Could not verify user existence: $($_.Exception.Message)" "Yellow"
}

# Get available licenses
Write-Log ""
Write-Log "Retrieving available licenses in tenant..." "Yellow"
$availableLicenses = $null
$selectedLicense = $null

try {
    $availableLicenses = Get-MgSubscribedSku -ErrorAction Stop
    Write-Log "Found $($availableLicenses.Count) license SKUs in tenant" "Green"
    
    # License listing mode or selection
    $indexedLicenses = @()
    for ($i=0; $i -lt $availableLicenses.Count; $i++) {
        $lic = $availableLicenses[$i]
        $available = $lic.PrepaidUnits.Enabled - $lic.ConsumedUnits
        $indexedLicenses += [PSCustomObject]@{ Index = $i+1; SkuPartNumber = $lic.SkuPartNumber; Available = $available; TotalEnabled=$lic.PrepaidUnits.Enabled }
    }

    if ($ListLicenses) {
        Write-Log "Listing licenses only (no user will be created)." "Yellow"
        Write-Log "Format: LICENSE|Index|SkuPartNumber|Available|TotalEnabled" "Cyan"
        foreach ($l in $indexedLicenses) {
            # Raw line designed for TUI parsing
            "LICENSE|$($l.Index)|$($l.SkuPartNumber)|$($l.Available)|$($l.TotalEnabled)" | Out-File -FilePath $logFile -Append
            Write-Host "LICENSE|$($l.Index)|$($l.SkuPartNumber)|$($l.Available)|$($l.TotalEnabled)" -ForegroundColor White
        }
        Write-Log "License listing complete." "Green"
        Disconnect-MgGraph | Out-Null
        Write-Log "Disconnected successfully" "Green"
        Write-Log "==========================================" "Cyan"
        Write-Log "          LICENSE LIST MODE" "Cyan"
        Write-Log "==========================================" "Cyan"
        Write-Log "Total SKUs: $($indexedLicenses.Count)" "White"
        Write-Log "Log File: $logFile" "White"
        Write-Log "==========================================" "Cyan"
        exit 0
    }

    # If a license SKU was specified, find it
    if (-not $ListLicenses -and $LicenseSKU -ne "") {
        $selectedLicense = $availableLicenses | Where-Object { $_.SkuPartNumber -eq $LicenseSKU }
        if ($null -eq $selectedLicense) {
            Write-Log "WARNING: License SKU '$LicenseSKU' not found in tenant" "Yellow"
        } else {
            $availableCount = $selectedLicense.PrepaidUnits.Enabled - $selectedLicense.ConsumedUnits
            if ($availableCount -le 0) {
                Write-Log "WARNING: No available licenses for SKU '$LicenseSKU' (Available: $availableCount)" "Yellow"
                $selectedLicense = $null
            } else {
                Write-Log "License '$LicenseSKU' selected (Available: $availableCount)" "Green"
            }
        }
    } elseif (-not $ListLicenses -and $LicenseIndex -ge 0) {
        if ($LicenseIndex -ge 1 -and $LicenseIndex -le $availableLicenses.Count) {
            $selectedLicense = $availableLicenses[$LicenseIndex - 1]
            $avail = $selectedLicense.PrepaidUnits.Enabled - $selectedLicense.ConsumedUnits
            if ($avail -le 0) {
                Write-Log "WARNING: Selected license index $LicenseIndex has no availability" "Yellow"
                $selectedLicense = $null
            } else {
                Write-Log "License index $LicenseIndex selected: $($selectedLicense.SkuPartNumber) (Available: $avail)" "Green"
            }
        } else {
            Write-Log "WARNING: LicenseIndex $LicenseIndex is out of range (1-$($availableLicenses.Count))" "Yellow"
        }
    }
} catch {
    Write-Log "WARNING: Failed to retrieve licenses: $($_.Exception.Message)" "Yellow"
}

# Create the user
Write-Log ""
Write-Log "Creating user account..." "Yellow"

# Securely convert password for API call
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureUserPassword)
$plainPassword = $null

try {
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    
    # Create user object
    $userParams = @{
        AccountEnabled    = $true
        DisplayName       = $DisplayName
        UserPrincipalName = $UserPrincipalName
        UsageLocation     = $UsageLocation
        MailNickname      = $UserPrincipalName.Split('@')[0]
        PasswordProfile   = @{
            Password                      = $plainPassword
            ForceChangePasswordNextSignIn = $false
        }
    }

    # Create the user
    $newUser = New-MgUser -BodyParameter $userParams -ErrorAction Stop
    Write-Log "SUCCESS: User '$DisplayName' created successfully!" "Green"
    Write-Log "  User ID: $($newUser.Id)" "White"
    
} catch {
    Write-Log "FATAL: Failed to create user: $($_.Exception.Message)" "Red"
    
    if ($_.Exception.Message -like "*already exists*") {
        Write-Log "SOLUTION: User already exists. Choose a different UserPrincipalName" "Yellow"
    } elseif ($_.Exception.Message -like "*domain*") {
        Write-Log "SOLUTION: Verify the domain in the UserPrincipalName is valid and verified in your tenant" "Yellow"
    } elseif ($_.Exception.Message -like "*password*") {
        Write-Log "SOLUTION: Ensure password meets complexity requirements (8+ chars, uppercase, lowercase, number, symbol)" "Yellow"
    } else {
        Write-Log "SOLUTION: Check that you have User.ReadWrite.All permissions and all parameters are valid" "Yellow"
    }
    
    Disconnect-MgGraph | Out-Null
    exit 2
} finally {
    # Securely clear password from memory
    if ($BSTR -ne [IntPtr]::Zero) {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }
    if ($plainPassword) {
        $plainPassword = $null
        [System.GC]::Collect()
    }
}

# Assign license if specified and available
if ($selectedLicense) {
    Write-Log ""
    Write-Log "Assigning license '$($selectedLicense.SkuPartNumber)' to user..." "Yellow"
    
    try {
        $licenseParams = @{
            AddLicenses = @(
                @{
                    SkuId = $selectedLicense.SkuId
                    DisabledPlans = @()
                }
            )
            RemoveLicenses = @()
        }
        
        Set-MgUserLicense -UserId $newUser.Id -BodyParameter $licenseParams -ErrorAction Stop
        Write-Log "SUCCESS: License '$($selectedLicense.SkuPartNumber)' assigned successfully!" "Green"
        
    } catch {
        Write-Log "ERROR: Failed to assign license: $($_.Exception.Message)" "Red"
        
        if ($_.Exception.Message -like "*UsageLocation*") {
            Write-Log "SOLUTION: Ensure UsageLocation is set correctly on the user" "Yellow"
        } elseif ($_.Exception.Message -like "*available*") {
            Write-Log "SOLUTION: No licenses available. Purchase more licenses or remove from another user" "Yellow"
        } else {
            Write-Log "SOLUTION: Verify you have Directory.ReadWrite.All permissions" "Yellow"
        }
    }
} elseif (-not [string]::IsNullOrEmpty($LicenseSKU)) {
    Write-Log "WARNING: License was requested but could not be assigned" "Yellow"
} else {
    Write-Log "No license specified - user created without license" "White"
}

# Disconnect from Microsoft Graph
Write-Log ""
Write-Log "Disconnecting from Microsoft Graph..." "Yellow"
Disconnect-MgGraph | Out-Null
Write-Log "Disconnected successfully" "Green"

# Summary
Write-Log ""
Write-Log "==========================================" "Cyan"
Write-Log "          CREATION SUMMARY" "Cyan"
Write-Log "==========================================" "Cyan"
Write-Log "User Created:          Yes" "Green"
Write-Log "Display Name:          $DisplayName" "White"
Write-Log "User Principal Name:   $UserPrincipalName" "White"
Write-Log "Usage Location:        $UsageLocation" "White"
Write-Log "License Assigned:      $(if ($selectedLicense) { $selectedLicense.SkuPartNumber } else { 'None' })" $(if ($selectedLicense) { "Green" } else { "Yellow" })
Write-Log "==========================================" "Cyan"
Write-Log ""
Write-Log "Log File: $logFile" "White"
Write-Log "==========================================" "Cyan"
Write-Log ""
Write-Log "User creation completed successfully!" "Green"

exit 0