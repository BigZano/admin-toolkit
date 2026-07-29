# Audit mailbox delegate permissions and folder access for a specific user

param(
    [Parameter(Mandatory=$false)]
    [string]$TargetUserEmail = "",

    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

# Set output directory (OS agnostic)
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

# Set output files with timestamp
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$safeTarget = $TargetUserEmail -replace '[\\/:*?"<>|]', '_'
$outputFile = Join-Path $OutputDirectory "DelegateAccess_${safeTarget}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "DelegateAccess_${safeTarget}_$timestamp.log"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    $logMessage | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

# Validate required parameter (NonInteractive-safe: no mandatory prompt)
if ([string]::IsNullOrWhiteSpace($TargetUserEmail)) {
    Write-Log "FATAL: TargetUserEmail is required." "Red"
    Write-Log "SOLUTION: Run with -TargetUserEmail user@domain.com" "Yellow"
    exit 1
}

# Import Exchange Online module
try {
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    Write-Log "Successfully imported ExchangeOnlineManagement module" "Green"
} catch {
    Write-Log "FATAL: Failed to import ExchangeOnlineManagement module: $($_.Exception.Message)" "Red"
    Write-Log "SOLUTION: Install module with: Install-Module ExchangeOnlineManagement -Scope CurrentUser" "Yellow"
    exit 1
}

# Connect to Exchange Online with interactive authentication (supports MFA)
Write-Log "Connecting to Exchange Online with interactive authentication..." "Yellow"
Write-Log "Please sign in with your admin credentials when prompted (MFA supported)" "Cyan"

try {
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    $session = Get-ConnectionInformation
    Write-Log "Connected to Exchange Online as: $($session.UserPrincipalName)" "Green"
    Write-Log "Authentication Type: Interactive (MFA Supported)" "Green"
} catch {
    Write-Log "FATAL: Failed to connect to Exchange Online: $($_.Exception.Message)" "Red"
    Write-Log "SOLUTION: Verify your admin credentials and network connectivity" "Yellow"
    exit 1
}

# Resolve the target user once so we can query/compare canonically.
# EXO permission entries may reference the trustee as alias, name, DN, or SMTP.
try {
    $target     = Get-Recipient -Identity $TargetUserEmail -ErrorAction Stop
    $targetDN   = [string]$target.DistinguishedName
    $targetSmtp = [string]$target.PrimarySmtpAddress
    Write-Log "Resolved target recipient: $($target.DisplayName) <$targetSmtp>" "Green"
} catch {
    Write-Log "FATAL: Could not resolve '$TargetUserEmail' as a recipient: $($_.Exception.Message)" "Red"
    Write-Log "SOLUTION: Verify the email address exists in this tenant" "Yellow"
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 1
}

# Map RecipientTypeDetails to a friendly object type label
function Get-ObjectTypeLabel {
    param($RecipientTypeDetails)
    switch -Regex ([string]$RecipientTypeDetails) {
        '^SharedMailbox$'                                 { "Shared Mailbox"; break }
        '^(UserMailbox|LinkedMailbox|RemoteUserMailbox)$' { "User Mailbox"; break }
        '^(RoomMailbox|EquipmentMailbox)$'                { "Resource Mailbox"; break }
        '^GroupMailbox$'                                  { "Microsoft 365 Group"; break }
        'DistributionGroup|MailUniversalSecurityGroup'    { "Distribution Group"; break }
        default                                           { [string]$RecipientTypeDetails }
    }
}

$permissionsReport = [System.Collections.ArrayList]::new()

Write-Log ""
Write-Log ("=" * 60) "Yellow"
Write-Log "Processing permissions for: $targetSmtp" "Yellow"
Write-Log ("=" * 60) "Yellow"

# 1) "Send As" permissions - single server-side query by trustee
Write-Log "Checking Send As permissions (server-side query)..." "Cyan"
try {
    $sendAsPermissions = Get-RecipientPermission -Trustee $targetSmtp -ResultSize Unlimited -ErrorAction Stop |
        Where-Object { $_.AccessRights -contains 'SendAs' }

    foreach ($permission in $sendAsPermissions) {
        $obj = $null
        try {
            $obj = Get-Recipient -Identity ([string]$permission.Identity) -ErrorAction Stop
        } catch {
            Write-Log "Warning: Could not resolve object '$($permission.Identity)': $($_.Exception.Message)" "Yellow"
        }
        $isGroup = $obj -and ([string]$obj.RecipientTypeDetails -match 'Group')
        [void]$permissionsReport.Add([PSCustomObject]@{
            ObjectType  = if ($obj) { Get-ObjectTypeLabel $obj.RecipientTypeDetails } else { "Unknown" }
            GroupType   = if ($isGroup) { [string]$obj.RecipientTypeDetails } else { "" }
            Object      = if ($obj -and $obj.PrimarySmtpAddress) { [string]$obj.PrimarySmtpAddress } else { [string]$permission.Identity }
            Trustee     = $targetSmtp
            AccessRight = "Send As"
        })
    }
} catch {
    Write-Log "Warning: Send As permission query failed: $($_.Exception.Message)" "Yellow"
}

# 2) "Send on Behalf" permissions - server-side filter on GrantSendOnBehalfTo
Write-Log "Checking Send on Behalf permissions (server-side query)..." "Cyan"
$sobFilter = "GrantSendOnBehalfTo -eq '$($targetDN -replace "'", "''")'"
$sobSources = @(
    @{ Cmd = 'Get-Mailbox';           Label = $null },
    @{ Cmd = 'Get-DistributionGroup'; Label = 'Distribution Group' },
    @{ Cmd = 'Get-UnifiedGroup';      Label = 'Microsoft 365 Group' }
)
foreach ($src in $sobSources) {
    try {
        $results = & $src.Cmd -Filter $sobFilter -ResultSize Unlimited -ErrorAction Stop
        foreach ($obj in $results) {
            [void]$permissionsReport.Add([PSCustomObject]@{
                ObjectType  = if ($src.Label) { $src.Label } else { Get-ObjectTypeLabel $obj.RecipientTypeDetails }
                GroupType   = if ($src.Label) { [string]$obj.RecipientTypeDetails } else { "" }
                Object      = [string]$obj.PrimarySmtpAddress
                Trustee     = $targetSmtp
                AccessRight = "Send on Behalf"
            })
        }
    } catch {
        Write-Log "Warning: $($src.Cmd) Send on Behalf query failed: $($_.Exception.Message)" "Yellow"
    }
}

# 3) "Full Access" permissions - enumerate mailboxes once, filter by user server-side
Write-Log "Checking Full Access permissions (this can take a while on large tenants)..." "Cyan"
try {
    $mailboxes = Get-Mailbox -ResultSize Unlimited -ErrorAction Stop
    Write-Log "Scanning $($mailboxes.Count) mailboxes for Full Access grants..." "Cyan"

    $count = 0
    foreach ($mailbox in $mailboxes) {
        $count++
        if ($count % 200 -eq 0) {
            Write-Log "  Checked $count of $($mailboxes.Count) mailboxes..." "White"
        }
        try {
            $fullAccessPermissions = Get-MailboxPermission -Identity $mailbox.Identity -User $targetSmtp -ErrorAction Stop |
                Where-Object { $_.IsInherited -eq $false -and $_.AccessRights -contains 'FullAccess' }

            foreach ($permission in $fullAccessPermissions) {
                [void]$permissionsReport.Add([PSCustomObject]@{
                    ObjectType  = Get-ObjectTypeLabel $mailbox.RecipientTypeDetails
                    GroupType   = ""
                    Object      = [string]$mailbox.PrimarySmtpAddress
                    Trustee     = $targetSmtp
                    AccessRight = "Full Access"
                })
            }
        } catch {
            Write-Log "Warning: Could not check Full Access on $($mailbox.PrimarySmtpAddress): $($_.Exception.Message)" "Yellow"
        }
    }
} catch {
    Write-Log "FATAL: Could not enumerate mailboxes: $($_.Exception.Message)" "Red"
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 1
}

# Display summary
Write-Log ""
Write-Log ("=" * 60) "Yellow"
Write-Log "SUMMARY" "Yellow"
Write-Log ("=" * 60) "Yellow"
Write-Log "Total permissions found: $($permissionsReport.Count)" "Cyan"

if ($permissionsReport.Count -gt 0) {
    Write-Log ""
    Write-Log "Permissions Report:" "Cyan"
    foreach ($entry in $permissionsReport) {
        Write-Log ("  {0,-20} {1,-45} {2}" -f $entry.ObjectType, $entry.Object, $entry.AccessRight) "White"
    }

    # Export to CSV
    $permissionsReport | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Log ""
    Write-Log "Report exported to: $outputFile" "Green"
} else {
    Write-Log ""
    Write-Log "No delegate permissions found for $targetSmtp" "Yellow"
    # Create CSV with headers only (no blank data row)
    '"ObjectType","GroupType","Object","Trustee","AccessRight"' | Out-File -FilePath $outputFile -Encoding utf8
    Write-Log "Empty report (headers only) exported to: $outputFile" "Green"
}

# Disconnect from Exchange Online (force without confirmation)
Write-Log ""
Write-Log "Disconnecting from Exchange Online..." "Yellow"
Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
Write-Log "Disconnected from Exchange Online" "Green"

Write-Log "Script completed successfully" "Green"

# Exit with success
exit 0
