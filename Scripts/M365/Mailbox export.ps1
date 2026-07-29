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
        $OutputDirectory = Join-Path -Path $env:USERPROFILE -ChildPath "Documents\AdminToolReports"
    } else {
        $OutputDirectory = Join-Path -Path $env:HOME -ChildPath "Documents/AdminToolReports"
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
    Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
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
$graphConnected = $false
$skuLookup = @{}
try {
    Write-Log "Connecting to Microsoft Graph..." "Yellow"
    Connect-MgGraph -Scopes "User.Read.All" -NoWelcome -ErrorAction Stop
    $context = Get-MgContext
    Write-Log "Successfully connected to Microsoft Graph as: $($context.Account)" "Green"
    $graphConnected = $true

    # Cache SKU definitions once (SkuId -> SkuPartNumber) instead of per-mailbox lookups
    try {
        Get-MgSubscribedSku -ErrorAction Stop | ForEach-Object { $skuLookup[[string]$_.SkuId] = $_.SkuPartNumber }
        Write-Log "Cached $($skuLookup.Count) license SKU definitions" "Green"
    } catch {
        Write-Log "Warning: Failed to retrieve subscribed SKUs: $($_.Exception.Message)" "Yellow"
    }
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
    exit 1
}

# Process mailboxes
$mailboxInfo = [System.Collections.ArrayList]::new()
$processedCount = 0
$errors = 0

foreach ($mailbox in $mailboxes) {
    $processedCount++
    if ($processedCount % 100 -eq 0) {
        Write-Log "  Processing mailbox $processedCount of $($mailboxes.Count)..." "White"
    }

    # Get mailbox statistics (a failure here should not drop the whole row)
    $stats = $null
    try {
        $stats = Get-MailboxStatistics $mailbox.UserPrincipalName -ErrorAction Stop
    } catch {
        Write-Log "Warning: Could not get statistics for $($mailbox.UserPrincipalName): $($_.Exception.Message)" "Yellow"
        $errors++
    }

    # Get license information (from cached SKU lookup)
    $licenses = "N/A"
    if ($graphConnected) {
        try {
            $mgUser = Get-MgUser -UserId $mailbox.UserPrincipalName `
                                -Property "AssignedLicenses" `
                                -ErrorAction Stop

            if ($mgUser.AssignedLicenses.Count -gt 0) {
                $licenses = ($mgUser.AssignedLicenses.SkuId | ForEach-Object {
                    $skuId = [string]$_
                    if ($skuLookup.ContainsKey($skuId)) { $skuLookup[$skuId] } else { $skuId }
                }) -join ', '
            } else {
                $licenses = "No licenses"
            }
        } catch {
            $licenses = "Error retrieving"
        }
    }

    # Calculate size in GB from the exact byte count, e.g. "1.5 GB (1,610,612,736 bytes)"
    $sizeInGB = 0
    if ($stats -and $stats.TotalItemSize -match '\(([\d,]+)\s*bytes\)') {
        $sizeInGB = [math]::Round([double]($matches[1] -replace ',', '') / 1GB, 2)
    } elseif ($stats -and $stats.TotalItemSize -match '(\d+\.?\d*)\s*(TB|GB|MB|KB)') {
        $value = [double]$matches[1]
        $sizeInGB = switch ($matches[2]) {
            "TB" { [math]::Round($value * 1024, 2) }
            "GB" { [math]::Round($value, 2) }
            "MB" { [math]::Round($value / 1024, 2) }
            "KB" { [math]::Round($value / 1MB, 2) }
        }
    }

    # Add to report
    [void]$mailboxInfo.Add([PSCustomObject]@{
        UserPrincipalName = $mailbox.UserPrincipalName
        DisplayName       = $mailbox.DisplayName
        MailboxType       = $mailbox.RecipientTypeDetails
        PrimaryEmail      = $mailbox.PrimarySmtpAddress
        ItemCount         = if ($stats) { $stats.ItemCount } else { "N/A" }
        TotalItemSize     = if ($stats) { $stats.TotalItemSize } else { "N/A" }
        SizeInGB          = $sizeInGB
        LastLogonTime     = if ($stats) { $stats.LastLogonTime } else { $null }
        MailboxDatabase   = if ($stats) { $stats.Database } else { "N/A" }
        Licenses          = $licenses
        Created           = $mailbox.WhenCreated
    })
}

# Export results
try {
    $mailboxInfo | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
    Write-Log "Successfully exported mailbox report to: $outputFile" "Green"
    
    # Generate statistics
    $totalSizeGB = ($mailboxInfo | Measure-Object -Property SizeInGB -Sum).Sum
    $avgSizeGB = if ($mailboxInfo.Count -gt 0) { 
        [math]::Round($totalSizeGB / $mailboxInfo.Count, 2) 
    } else { 0 }
    $totalItems = ($mailboxInfo | Where-Object { $_.ItemCount -ne "N/A" } | Measure-Object -Property ItemCount -Sum).Sum
    
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
    exit 1
}

# Cleanup
Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
Write-Log "Disconnected from services" "Green"
Write-Log "Script completed successfully" "Green"

exit 0