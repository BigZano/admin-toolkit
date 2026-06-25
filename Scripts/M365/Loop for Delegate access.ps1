# Audit mailbox delegate permissions and folder access for a specific user

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetUserEmail,
    
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

if (-not (Test-Path -Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

# Set output files with timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "DelegateAccess_${TargetUserEmail}_$timestamp.csv"
$logFile = Join-Path $OutputDirectory "DelegateAccess_${TargetUserEmail}_$timestamp.log"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    $logMessage | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
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

# Initialize array to hold permissions
$permissionsReport = [System.Collections.ArrayList]::new()

Write-Log "" 
Write-Log "Retrieving mailboxes and groups..." "Yellow"

# Get all mailboxes, shared mailboxes, and distribution/Microsoft 365 groups
try {
    $mailboxes = Get-Mailbox -ResultSize Unlimited -ErrorAction Stop
    Write-Log "Found $($mailboxes.Count) user mailboxes" "Cyan"
    
    $sharedMailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -ErrorAction Stop
    Write-Log "Found $($sharedMailboxes.Count) shared mailboxes" "Cyan"
    
    $distributionGroups = Get-DistributionGroup -ResultSize Unlimited -ErrorAction Stop
    Write-Log "Found $($distributionGroups.Count) distribution groups" "Cyan"
    
    # Get Microsoft 365 Groups (Unified Groups)
    $unifiedGroups = Get-UnifiedGroup -ResultSize Unlimited -ErrorAction Stop
    Write-Log "Found $($unifiedGroups.Count) Microsoft 365 groups" "Cyan"
} catch {
    Write-Log "FATAL: Error retrieving mailboxes or groups: $($_.Exception.Message)" "Red"
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 1
}

# Function to process permissions
function Process-Permissions {
    param(
        $Identity,
        [string]$Type,
        [string]$TargetUserEmail,
        [string]$GroupType = ""
    )
    
    $objectName = if ($Identity.PrimarySmtpAddress) { $Identity.PrimarySmtpAddress } else { $Identity.DisplayName }
    
    # Retrieve "Send As" permissions
    try {
        $sendAsPermissions = Get-RecipientPermission -Identity $Identity.Identity -ErrorAction Stop | 
            Where-Object { $_.Trustee -eq $TargetUserEmail -and $_.AccessRights -contains 'SendAs' }
        
        foreach ($permission in $sendAsPermissions) {
            [void]$permissionsReport.Add([PSCustomObject]@{
                ObjectType  = $Type
                GroupType   = $GroupType
                Object      = $objectName
                Trustee     = $TargetUserEmail
                AccessRight = "Send As"
            })
        }
    } catch {
        Write-Host "Warning: Could not check Send As permissions for $objectName : $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Retrieve "Send on Behalf" permissions
    if ($Identity.GrantSendOnBehalfTo) {
        foreach ($delegate in $Identity.GrantSendOnBehalfTo) {
            try {
                $delegateRecipient = Get-Recipient -Identity $delegate -ErrorAction Stop
                if ($delegateRecipient.PrimarySmtpAddress -eq $TargetUserEmail) {
                    [void]$permissionsReport.Add([PSCustomObject]@{
                        ObjectType  = $Type
                        GroupType   = $GroupType
                        Object      = $objectName
                        Trustee     = $TargetUserEmail
                        AccessRight = "Send on Behalf"
                    })
                }
            } catch {
                Write-Host "Warning: Could not resolve delegate: $delegate" -ForegroundColor Yellow
            }
        }
    }

    # Retrieve "Full Access" permissions (mailboxes only, not groups)
    if ($Type -ne "Distribution Group" -and $Type -ne "Microsoft 365 Group") {
        try {
            $fullAccessPermissions = Get-MailboxPermission -Identity $Identity.Identity -ErrorAction Stop | 
                Where-Object { 
                    $_.User -like "*$TargetUserEmail*" -and 
                    $_.IsInherited -eq $false -and 
                    $_.AccessRights -contains 'FullAccess' 
                }
            
            foreach ($permission in $fullAccessPermissions) {
                [void]$permissionsReport.Add([PSCustomObject]@{
                    ObjectType  = $Type
                    GroupType   = $GroupType
                    Object      = $objectName
                    Trustee     = $TargetUserEmail
                    AccessRight = "Full Access"
                })
            }
        } catch {
            Write-Host "Warning: Could not check Full Access permissions for $objectName : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

Write-Host "\nProcessing permissions for: $TargetUserEmail" -ForegroundColor Yellow
Write-Host "=" * 60 -ForegroundColor Yellow

# Process regular mailboxes
Write-Host "\nChecking user mailboxes..." -ForegroundColor Cyan
foreach ($mailbox in $mailboxes) {
    Process-Permissions -Identity $mailbox -Type "User Mailbox" -TargetUserEmail $TargetUserEmail
}

# Process shared mailboxes
Write-Host "Checking shared mailboxes..." -ForegroundColor Cyan
foreach ($sharedMailbox in $sharedMailboxes) {
    Process-Permissions -Identity $sharedMailbox -Type "Shared Mailbox" -TargetUserEmail $TargetUserEmail
}

# Process distribution groups
Write-Host "Checking distribution groups..." -ForegroundColor Cyan
foreach ($distributionGroup in $distributionGroups) {
    $groupType = if ($distributionGroup.RecipientTypeDetails) { $distributionGroup.RecipientTypeDetails } else { "Distribution" }
    Process-Permissions -Identity $distributionGroup -Type "Distribution Group" -TargetUserEmail $TargetUserEmail -GroupType $groupType
}

# Process Microsoft 365 groups
Write-Host "Checking Microsoft 365 groups..." -ForegroundColor Cyan
foreach ($unifiedGroup in $unifiedGroups) {
    Process-Permissions -Identity $unifiedGroup -Type "Microsoft 365 Group" -TargetUserEmail $TargetUserEmail -GroupType "Unified"
}

# Display summary
Write-Host "\n" -NoNewline
Write-Host "=" * 60 -ForegroundColor Yellow
Write-Host "SUMMARY" -ForegroundColor Yellow
Write-Host "=" * 60 -ForegroundColor Yellow
Write-Host "Total permissions found: $($permissionsReport.Count)" -ForegroundColor Cyan

if ($permissionsReport.Count -gt 0) {
    # Display the report
    Write-Host "\nPermissions Report:" -ForegroundColor Cyan
    $permissionsReport | Format-Table -AutoSize
    
    # Export to CSV
    $permissionsReport | Export-Csv -Path $outputFile -NoTypeInformation
    Write-Host "\nReport exported to: $outputFile" -ForegroundColor Green
} else {
    Write-Host "\nNo delegate permissions found for $TargetUserEmail" -ForegroundColor Yellow
    # Create empty CSV with headers
    [PSCustomObject]@{
        ObjectType  = ""
        GroupType   = ""
        Object      = ""
        Trustee     = ""
        AccessRight = ""
    } | Export-Csv -Path $outputFile -NoTypeInformation
    Write-Host "Empty report exported to: $outputFile" -ForegroundColor Green
}

# Disconnect from Exchange Online (force without confirmation)
Write-Host "\nDisconnecting from Exchange Online..." -ForegroundColor Yellow
try {
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction Stop | Out-Null
    Write-Host "Disconnected from Exchange Online" -ForegroundColor Green
} catch {
    Write-Host "Note: Disconnect completed (suppressed prompt)" -ForegroundColor Gray
}

Write-Log "Script completed successfully" "Green"

# Exit with success
exit 0