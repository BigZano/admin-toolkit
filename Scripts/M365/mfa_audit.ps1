# Audit MFA registration status and authentication methods for all users

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

# Set output directory
if ([string]::IsNullOrEmpty($OutputDirectory)) {
    if ($IsWindows -or $env:OS -match "Windows") {
        $OutputDirectory = Join-Path -Path $env:USERPROFILE -ChildPath "Documents\AdminToolReports"
    } else {
        $OutputDirectory = Join-Path -Path $env:HOME -ChildPath "Documents/AdminToolReports"
    }
}

if (-not (Test-Path -Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "MFAAudit_$timestamp.csv"
$logFile = Join-Path $OutputDirectory "MFAAudit_$timestamp.log"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    $logMessage | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

# Import modules
try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.Users -ErrorAction Stop
    Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction Stop
    Write-Log "Successfully imported Microsoft Graph modules" "Green"
} catch {
    Write-Log "FATAL: Failed to import modules: $($_.Exception.Message)" "Red"
    Write-Log "SOLUTION: Install modules with: Install-Module Microsoft.Graph -Scope CurrentUser" "Yellow"
    exit 1
}

# Connect to Microsoft Graph with interactive authentication (supports MFA)
try {
    Write-Log "Connecting to Microsoft Graph with interactive authentication..." "Yellow"
    Write-Log "Please sign in with your admin credentials when prompted (MFA supported)" "Cyan"
    
    Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All", "UserAuthenticationMethod.Read.All" `
                    -ContextScope Process `
                    -NoWelcome `
                    -ErrorAction Stop
    
    $context = Get-MgContext
    Write-Log "Successfully connected to Microsoft Graph" "Green"
    Write-Log "Authenticated as: $($context.Account)" "Green"
    Write-Log "Tenant ID: $($context.TenantId)" "Green"
    Write-Log "Authentication Type: Interactive (MFA Supported)" "Green"
} catch {
    Write-Log "FATAL: Failed to connect to Microsoft Graph: $($_.Exception.Message)" "Red"
    Write-Log "SOLUTION: Verify admin account has proper roles (Global Reader or Security Administrator)" "Yellow"
    exit 1
}

# Get licensed users
Write-Log "Retrieving licensed users..." "Yellow"
try {
    $licensedUsers = Get-MgUser -All `
                                -Filter "accountEnabled eq true" `
                                -Property "Id,DisplayName,UserPrincipalName,AssignedLicenses" `
                                -ErrorAction Stop | 
                     Where-Object { $_.AssignedLicenses.Count -gt 0 }
    
    Write-Log "Found $($licensedUsers.Count) licensed users to audit" "Green"
} catch {
    Write-Log "ERROR: Failed to retrieve users: $($_.Exception.Message)" "Red"
    Write-Log "SOLUTION: Verify User.Read.All permission is granted and consented" "Yellow"
    Disconnect-MgGraph | Out-Null
    exit 1
}

# Check MFA status for each user
$usersWithMfaStatus = [System.Collections.ArrayList]::new()
$total = $licensedUsers.Count
$count = 0
$errors = 0

Write-Log "Checking MFA status for each user..." "Yellow"

foreach ($user in $licensedUsers) {
    $count++
    if ($count % 100 -eq 0) {
        Write-Log "  Processing user $count of $total..." "White"
    }

    $mfaStatus = "Disabled"
    $authMethods = @()
    
    try {
        $methods = Get-MgUserAuthenticationMethod -UserId $user.Id -ErrorAction Stop
        
        if ($methods) {
            $authMethods = $methods | ForEach-Object {
                $_.AdditionalProperties['@odata.type'] -replace '#microsoft.graph.', ''
            }
            
            # Check for strong MFA methods
            if ($methods | Where-Object {
                $_.AdditionalProperties['@odata.type'] -match 'microsoftAuthenticatorAuthenticationMethod|phoneAuthenticationMethod|fido2AuthenticationMethod|softwareOathAuthenticationMethod|windowsHelloForBusinessAuthenticationMethod'
            }) {
                $mfaStatus = "Enabled"
            }
        }
    } catch {
        Write-Log "Warning: Could not check MFA for $($user.UserPrincipalName): $($_.Exception.Message)" "Yellow"
        $authMethods = @("Error retrieving")
        $errors++
    }
    
    [void]$usersWithMfaStatus.Add([PSCustomObject]@{
        DisplayName       = $user.DisplayName
        UserPrincipalName = $user.UserPrincipalName
        MFAStatus         = $mfaStatus
        AuthMethods       = ($authMethods -join ', ')
        LicenseCount      = $user.AssignedLicenses.Count
    })
}

# Sort and export results
$sortedResults = $usersWithMfaStatus | Sort-Object MFAStatus, DisplayName

try {
    $sortedResults | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
    Write-Log "Results exported to: $outputFile" "Green"
    
    # Generate summary statistics
    $enabled = ($sortedResults | Where-Object { $_.MFAStatus -eq "Enabled" }).Count
    $disabled = ($sortedResults | Where-Object { $_.MFAStatus -eq "Disabled" }).Count
    $enabledPercent = if ($total -gt 0) { [math]::Round(($enabled/$total)*100, 2) } else { 0 }
    $disabledPercent = if ($total -gt 0) { [math]::Round(($disabled/$total)*100, 2) } else { 0 }
    
    Write-Log ""
    Write-Log "==========================================" "Cyan"
    Write-Log "          MFA AUDIT SUMMARY" "Cyan"
    Write-Log "==========================================" "Cyan"
    Write-Log "Total Users Audited:    $total" "White"
    Write-Log "MFA Enabled:            $enabled ($enabledPercent%)" "Green"
    Write-Log "MFA Disabled:           $disabled ($disabledPercent%)" "Red"
    Write-Log "Errors Encountered:     $errors" $(if ($errors -gt 0) { "Yellow" } else { "White" })
    Write-Log "==========================================" "Cyan"
    Write-Log ""
    Write-Log "Files Generated:" "Cyan"
    Write-Log "  Report: $outputFile" "White"
    Write-Log "  Log:    $logFile" "White"
    Write-Log "==========================================" "Cyan"
    
} catch {
    Write-Log "FATAL: Failed to export results: $($_.Exception.Message)" "Red"
    Disconnect-MgGraph | Out-Null
    exit 1
}

# Cleanup
Disconnect-MgGraph | Out-Null
Write-Log "Disconnected from Microsoft Graph" "Green"
if ($errors -gt 0) {
    Write-Log "WARNING: MFA status could not be determined for $errors user(s); they are marked 'Error retrieving' in the report" "Yellow"
}
Write-Log "Script completed successfully" "Green"

exit 0
