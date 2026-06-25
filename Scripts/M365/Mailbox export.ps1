# Export detailed mailbox information to CSV with filtering by mailbox type

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("All", "UserMailbox", "SharedMailbox", "RoomMailbox", "EquipmentMailbox")]
    [string]$MailboxType = "All",
    
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
$outputFile = Join-Path $OutputDirectory "MailboxReport_${MailboxType}_$timestamp.csv"
$logFile = Join-Path $OutputDirectory "MailboxReport_${MailboxType}_$timestamp.log"

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
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.Users -ErrorAction Stop
    Write-Log "Successfully imported required modules" "Green"
} catch {
    Write-Log "FATAL: Failed to import modules: $($_.Exception.Message)" "Red"
    Write-Log "SOLUTION: Install modules with:" "Yellow"
    Write-Log "  Install-Module ExchangeOnlineManagement -Scope CurrentUser" "Yellow"
    Write-Log "  Install-Module Microsoft.Graph -Scope CurrentUser" "Yellow"
    exit 1
}

# Connect to Exchange Online with interactive authentication (supports MFA)
try {
    Write-Log "Connecting to Exchange Online with interactive authentication..." "Yellow"
    Write-Log "Please sign in with your admin credentials when prompted (MFA supported)" "Cyan"
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    $session = Get-ConnectionInformation
    Write-Log "Successfully connected to Exchange Online as: $($session.UserPrincipalName)" "Green"
    Write-Log "Authentication Type: Interactive (MFA Supported)" "Green"
} catch {
    Write-Log "FATAL: Failed to connect to Exchange Online: $($_.Exception.Message)" "Red"
    Write-Log "SOLUTION: Verify account has Exchange Administrator role" "Yellow"
    exit 1
}

# Connect to Microsoft Graph with interactive authentication
try {
    Write-Log "Connecting to Microsoft Graph..." "Yellow"
    Connect-MgGraph -Scopes "User.Read.All" -NoWelcome -ErrorAction Stop
    $context = Get-MgContext
    Write-Log "Successfully connected to Microsoft Graph as: $($context.Account)" "Green"
} catch {
    Write-Log "Warning: Failed to connect to Microsoft Graph: $($_.Exception.Message)" "Yellow"
    Write-Log "Note: License information will not be available" "Yellow"
}

# Get mailboxes based on type
Write-Log "Retrieving mailboxes (Type: $MailboxType)..." "Yellow"
try {
    if ($MailboxType -eq "All") {
        $mailboxes = Get-Mailbox -ResultSize Unlimited -ErrorAction Stop
    } else {
        $mailboxes = Get-Mailbox -RecipientTypeDetails $MailboxType -ResultSize Unlimited -ErrorAction Stop
    }
    Write-Log "Found $($mailboxes.Count) mailboxes to process" "Green"
} catch {
    Write-Log "FATAL: Failed to retrieve mailboxes: $($_.Exception.Message)" "Red"
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    exit 2
}

# Process mailboxes
$mailboxInfo = [System.Collections.ArrayList]::new()
$processedCount = 0
$errors = 0

foreach ($mailbox in $mailboxes) {
    $processedCount++
    Write-Progress -Activity "Processing Mailboxes" `
                   -Status "$processedCount of $($mailboxes.Count) - $($mailbox.UserPrincipalName)" `
                   -PercentComplete (($processedCount / $mailboxes.Count) * 100)
    
    try {
        # Get mailbox statistics
        $stats = Get-MailboxStatistics $mailbox.UserPrincipalName -ErrorAction Stop
        
        # Get license information
        $licenses = "N/A"
        try {
            $mgUser = Get-MgUser -UserId $mailbox.UserPrincipalName `
                                -Property "AssignedLicenses" `
                                -ErrorAction Stop
            
            if ($mgUser.AssignedLicenses.Count -gt 0) {
                $skuIds = $mgUser.AssignedLicenses.SkuId
                $subscribedSkus = Get-MgSubscribedSku
                $licenses = ($skuIds | ForEach-Object {
                    $skuId = $_
                    ($subscribedSkus | Where-Object { $_.SkuId -eq $skuId }).SkuPartNumber
                }) -join ', '
            } else {
                $licenses = "No licenses"
            }
        } catch {
            $licenses = "Error retrieving"
        }
        
        # Calculate size in GB for readability
        $sizeInGB = 0
        if ($stats.TotalItemSize -match '(\d+\.?\d*)\s*(GB|MB)') {
            if ($matches[2] -eq "GB") {
                $sizeInGB = [math]::Round([double]$matches[1], 2)
            } else {
                $sizeInGB = [math]::Round([double]$matches[1] / 1024, 2)
            }
        }
        
        # Add to report
        [void]$mailboxInfo.Add([PSCustomObject]@{
            UserPrincipalName = $mailbox.UserPrincipalName
            DisplayName       = $mailbox.DisplayName
            MailboxType       = $mailbox.RecipientTypeDetails
            PrimaryEmail      = $mailbox.PrimarySmtpAddress
            ItemCount         = $stats.ItemCount
            TotalItemSize     = $stats.TotalItemSize
            SizeInGB          = $sizeInGB
            LastLogonTime     = $stats.LastLogonTime
            MailboxDatabase   = $stats.Database
            Licenses          = $licenses
            Created           = $mailbox.WhenCreated
        })
        
    } catch {
        Write-Log "Warning: Error processing $($mailbox.UserPrincipalName): $($_.Exception.Message)" "Yellow"
        $errors++
    }
}

Write-Progress -Activity "Processing Mailboxes" -Completed

# Export results
try {
    $mailboxInfo | Export-Csv -Path $outputFile -NoTypeInformation -ErrorAction Stop
    Write-Log "Successfully exported mailbox report to: $outputFile" "Green"
    
    # Generate statistics
    $totalSizeGB = ($mailboxInfo | Measure-Object -Property SizeInGB -Sum).Sum
    $avgSizeGB = if ($mailboxInfo.Count -gt 0) { 
        [math]::Round($totalSizeGB / $mailboxInfo.Count, 2) 
    } else { 0 }
    $totalItems = ($mailboxInfo | Measure-Object -Property ItemCount -Sum).Sum
    
    Write-Log ""
    Write-Log "==========================================" "Cyan"
    Write-Log "      MAILBOX REPORT SUMMARY" "Cyan"
    Write-Log "==========================================" "Cyan"
    Write-Log "Mailbox Type:           $MailboxType" "White"
    Write-Log "Total Mailboxes:        $($mailboxInfo.Count)" "White"
    Write-Log "Total Size:             $totalSizeGB GB" "White"
    Write-Log "Average Size:           $avgSizeGB GB" "White"
    Write-Log "Total Items:            $totalItems" "White"
    Write-Log "Errors Encountered:     $errors" $(if ($errors -gt 0) { "Yellow" } else { "White" })
    Write-Log "==========================================" "Cyan"
    Write-Log ""
    Write-Log "Files Generated:" "Cyan"
    Write-Log "  Report: $outputFile" "White"
    Write-Log "  Log:    $logFile" "White"
    Write-Log "==========================================" "Cyan"
    
} catch {
    Write-Log "FATAL: Failed to export CSV: $($_.Exception.Message)" "Red"
    exit 2
}

# Cleanup
Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
Write-Log "Disconnected from services" "Green"
Write-Log "Script completed successfully" "Green"

exit 0