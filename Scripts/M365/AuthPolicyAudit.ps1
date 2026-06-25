# Audit per-user authentication policies and legacy auth exposure across the tenant

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

# Set output directory
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

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "AuthPolicyAudit_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "AuthPolicyAudit_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$ts] $Message"
    $logMessage | Out-File -FilePath $logFile -Append
    Write-Host $logMessage -ForegroundColor $Color
}

Write-Log "Starting authentication policy audit..." "Cyan"

try {
    Connect-ExchangeOnline -ErrorAction Stop
    Write-Log "Connected to Exchange Online." "Green"
} catch {
    Write-Log "Failed to connect to Exchange Online: $($_.Exception.Message)" "Red"
    exit 1
}

try {
    $orgConfig = Get-OrganizationConfig
    $tenantModernAuthEnabled = $orgConfig.OAuth2ClientProfileEnabled
    Write-Log "Tenant modern auth enabled: $tenantModernAuthEnabled" "Cyan"

    Write-Log "Retrieving authentication policies..." "Yellow"
    $authPolicies = Get-AuthenticationPolicy | ForEach-Object {
        [PSCustomObject]@{
            Name                       = $_.Name
            AllowBasicAuthPop          = $_.AllowBasicAuthPop
            AllowBasicAuthImap         = $_.AllowBasicAuthImap
            AllowBasicAuthSmtp         = $_.AllowBasicAuthSmtp
            AllowBasicAuthActiveSync   = $_.AllowBasicAuthActiveSync
            AllowBasicAuthAutodiscover = $_.AllowBasicAuthAutodiscover
            AllowBasicAuthWebServices  = $_.AllowBasicAuthWebServices
            AllowBasicAuthPowershell   = $_.AllowBasicAuthPowershell
            AllowBasicAuthMAPI         = $_.AllowBasicAuthMAPI
        }
    } | Group-Object -Property Name -AsHashTable -AsString

    Write-Log "Retrieving all users..." "Yellow"
    $users = Get-User -ResultSize Unlimited
    Write-Log "Processing $($users.Count) users..." "Yellow"

    $report = foreach ($user in $users) {
        $policyName = if ([string]::IsNullOrEmpty($user.AuthenticationPolicy)) { "Default" } else { $user.AuthenticationPolicy }
        $policy = $authPolicies[$policyName]

        $legacyAuthAllowed = $false
        if ($policy) {
            $legacyAuthAllowed = (
                $policy.AllowBasicAuthPop          -or
                $policy.AllowBasicAuthImap         -or
                $policy.AllowBasicAuthSmtp         -or
                $policy.AllowBasicAuthActiveSync   -or
                $policy.AllowBasicAuthAutodiscover -or
                $policy.AllowBasicAuthWebServices  -or
                $policy.AllowBasicAuthPowershell   -or
                $policy.AllowBasicAuthMAPI
            )
        }

        [PSCustomObject]@{
            UserPrincipalName       = $user.UserPrincipalName
            DisplayName             = $user.DisplayName
            EffectiveAuthPolicy     = $policyName
            LegacyAuthAllowed       = $legacyAuthAllowed
            TenantModernAuthEnabled = $tenantModernAuthEnabled
        }
    }

    $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Log "Report exported to: $outputFile" "Green"

    $legacyCount = ($report | Where-Object { $_.LegacyAuthAllowed }).Count
    Write-Log "Users with legacy auth allowed: $legacyCount / $($report.Count)" "$(if ($legacyCount -gt 0) { 'Yellow' } else { 'Green' })"

} catch {
    Write-Log "Error during audit: $($_.Exception.Message)" "Red"
} finally {
    Disconnect-ExchangeOnline -Confirm:$false
    Write-Log "Disconnected from Exchange Online." "Cyan"
}
