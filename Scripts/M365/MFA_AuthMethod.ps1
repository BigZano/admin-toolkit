# Generate comprehensive report of user authentication methods and MFA status

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

# Setup output directory
if ([string]::IsNullOrEmpty($OutputDirectory)) {
    if ($IsWindows -or $env:OS -match "Windows") {
        $OutputDirectory = Join-Path -Path $env:USERPROFILE -ChildPath "Documents\M365Reports"
    } else {
        $OutputDirectory = Join-Path -Path $env:HOME -ChildPath "Documents/M365Reports"
    }
}

if (-not (Test-Path -Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

# Setup output files
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "AuthMethodReport_$timestamp.csv"
$policiesFile = Join-Path $OutputDirectory "AuthPolicies_$timestamp.csv"
$logFile = Join-Path $OutputDirectory "AuthMethodReport_$timestamp.log"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    $logMessage | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "==========================================" "Cyan"
Write-Log "  Authentication Methods Report" "Cyan"
Write-Log "==========================================" "Cyan"
Write-Log ""

# Connect to Exchange Online with interactive authentication (supports MFA)
Write-Log "Connecting to Exchange Online with interactive authentication..." "Yellow"
Write-Log "Please sign in with your admin credentials when prompted (MFA supported)" "Cyan"
try {
    Connect-ExchangeOnline -ShowBanner:$false -WarningAction SilentlyContinue -ErrorAction Stop
    $session = Get-ConnectionInformation
    Write-Log "Successfully connected to Exchange Online as: $($session.UserPrincipalName)" "Green"
    Write-Log "Authentication Type: Interactive (MFA Supported)" "Green"
} catch {
    Write-Log "FATAL: Failed to connect to Exchange Online: $($_.Exception.Message)" "Red"
    Write-Log "SOLUTION: Verify credentials and that Exchange Online PowerShell is installed" "Yellow"
    exit 1
}

Write-Log ""
Write-Log "Retrieving tenant organization configuration..." "Yellow"

# Get tenant-wide organization config
try {
    $orgConfig = Get-OrganizationConfig -ErrorAction Stop
    $tenantModernAuthEnabled = $orgConfig.OAuth2ClientProfileEnabled
    Write-Log "Tenant Modern Auth Enabled: $tenantModernAuthEnabled" "Green"
} catch {
    Write-Log "WARNING: Failed to retrieve organization config: $($_.Exception.Message)" "Yellow"
    $tenantModernAuthEnabled = "Unknown"
}

Write-Log ""
Write-Log "Retrieving authentication policies..." "Yellow"

# Get authentication policies
try {
    $authPoliciesRaw = Get-AuthenticationPolicy -ErrorAction Stop
    Write-Log "Found $($authPoliciesRaw.Count) authentication policies" "Green"
    
    # Export policies to separate CSV
    $policyExportData = $authPoliciesRaw | ForEach-Object {
        [PSCustomObject]@{
            Name = $_.Name
            AllowBasicAuthPop = $_.AllowBasicAuthPop
            AllowBasicAuthImap = $_.AllowBasicAuthImap
            AllowBasicAuthSmtp = $_.AllowBasicAuthSmtp
            AllowBasicAuthActiveSync = $_.AllowBasicAuthActiveSync
            AllowBasicAuthAutodiscover = $_.AllowBasicAuthAutodiscover
            AllowBasicAuthWebServices = $_.AllowBasicAuthWebServices
            AllowBasicAuthPowershell = $_.AllowBasicAuthPowershell
            AllowBasicAuthMAPI = $_.AllowBasicAuthMAPI
        }
    }
    
    $policyExportData | Export-Csv -Path $policiesFile -NoTypeInformation -Encoding UTF8
    Write-Log "Exported policy definitions to: $policiesFile" "Green"
    
    # Create hashtable for lookup
    $authPolicies = $authPoliciesRaw | ForEach-Object {
        [PSCustomObject]@{
            Name = $_.Name
            AllowBasicAuthPop = $_.AllowBasicAuthPop
            AllowBasicAuthImap = $_.AllowBasicAuthImap
            AllowBasicAuthSmtp = $_.AllowBasicAuthSmtp
            AllowBasicAuthActiveSync = $_.AllowBasicAuthActiveSync
            AllowBasicAuthAutodiscover = $_.AllowBasicAuthAutodiscover
            AllowBasicAuthWebServices = $_.AllowBasicAuthWebServices
            AllowBasicAuthPowershell = $_.AllowBasicAuthPowershell
            AllowBasicAuthMAPI = $_.AllowBasicAuthMAPI
        }
    } | Group-Object -Property Name -AsHashTable -AsString
    
} catch {
    Write-Log "WARNING: Failed to retrieve authentication policies: $($_.Exception.Message)" "Yellow"
    $authPolicies = @{}
}

Write-Log ""
Write-Log "Retrieving all users..." "Yellow"

$tenantDefaultPolicyName = "Default"

try {
    $users = Get-User -ResultSize Unlimited -ErrorAction Stop
    Write-Log "Found $($users.Count) users to process" "Green"
} catch {
    Write-Log "FATAL: Failed to retrieve users: $($_.Exception.Message)" "Red"
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 2
}

Write-Log ""
Write-Log "Processing user authentication policies..." "Yellow"

$processedCount = 0
$errorCount = 0
$legacyAuthEnabledCount = 0

$userAuthPolicies = foreach ($user in $users) {
    try {
        $processedCount++
        
        # Progress indicator every 100 users
        if ($processedCount % 100 -eq 0) {
            Write-Log "  Processing user $processedCount of $($users.Count)..." "White"
        }
        
        $policyName = $user.AuthenticationPolicy
        if ([string]::IsNullOrEmpty($policyName)) {
            $policyName = $tenantDefaultPolicyName
        }

        $policySettings = $authPolicies[$policyName]

        $legacyAuthAllowed = $false
        if ($policySettings) {
            $legacyAuthAllowed = (
                $policySettings.AllowBasicAuthPop -or
                $policySettings.AllowBasicAuthImap -or
                $policySettings.AllowBasicAuthSmtp -or
                $policySettings.AllowBasicAuthActiveSync -or
                $policySettings.AllowBasicAuthAutodiscover -or
                $policySettings.AllowBasicAuthWebServices -or
                $policySettings.AllowBasicAuthPowershell -or
                $policySettings.AllowBasicAuthMAPI
            )
        }
        
        if ($legacyAuthAllowed) {
            $legacyAuthEnabledCount++
        }

        [PSCustomObject]@{
            UserPrincipalName       = $user.UserPrincipalName
            DisplayName             = $user.DisplayName
            RecipientType           = $user.RecipientType
            EffectiveAuthPolicy     = $policyName
            LegacyAuthAllowed       = $legacyAuthAllowed
            TenantModernAuthEnabled = $tenantModernAuthEnabled
        }
    } catch {
        $errorCount++
        Write-Log "ERROR processing user $($user.UserPrincipalName): $($_.Exception.Message)" "Red"
        continue
    }
}

Write-Log ""
Write-Log "Exporting user authentication data..." "Yellow"

try {
    $userAuthPolicies | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Log "Successfully exported user data" "Green"
} catch {
    Write-Log "FATAL: Failed to export CSV: $($_.Exception.Message)" "Red"
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 2
}

# Disconnect from Exchange Online
Write-Log ""
Write-Log "Disconnecting from Exchange Online..." "Yellow"
Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
Write-Log "Disconnected successfully" "Green"

# Summary statistics
$legacyAuthDisabledCount = $processedCount - $legacyAuthEnabledCount
$legacyAuthEnabledPct = if ($processedCount -gt 0) { [math]::Round(($legacyAuthEnabledCount / $processedCount) * 100, 2) } else { 0 }
$legacyAuthDisabledPct = if ($processedCount -gt 0) { [math]::Round(($legacyAuthDisabledCount / $processedCount) * 100, 2) } else { 0 }

Write-Log ""
Write-Log "==========================================" "Cyan"
Write-Log "          REPORT SUMMARY" "Cyan"
Write-Log "==========================================" "Cyan"
Write-Log "Total Users Processed:     $processedCount" "White"
Write-Log "Legacy Auth ENABLED:       $legacyAuthEnabledCount ($legacyAuthEnabledPct%)" "Yellow"
Write-Log "Legacy Auth DISABLED:      $legacyAuthDisabledCount ($legacyAuthDisabledPct%)" "Green"
Write-Log "Errors Encountered:        $errorCount" $(if ($errorCount -gt 0) { "Red" } else { "Green" })
Write-Log "==========================================" "Cyan"
Write-Log ""
Write-Log "Files Generated:" "Cyan"
Write-Log "  User Report:   $outputFile" "White"
Write-Log "  Policies:      $policiesFile" "White"
Write-Log "  Log File:      $logFile" "White"
Write-Log "==========================================" "Cyan"
Write-Log ""

if ($errorCount -gt 0) {
    Write-Log "Completed with errors" "Yellow"
    exit 2
} else {
    Write-Log "Report completed successfully!" "Green"
    exit 0
}