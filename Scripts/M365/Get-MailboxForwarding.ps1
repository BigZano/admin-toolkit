# Audit mailboxes with forwarding configured (security check)

param(
    [Parameter(Mandatory=$false)]
    [string]$IncludeInboxRules = "false",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    if ($IsWindows -or $env:OS -match "Windows") {
        $OutputDirectory = Join-Path $env:USERPROFILE "Documents\AdminToolReports"
    } else {
        $OutputDirectory = Join-Path $env:HOME "Documents/AdminToolReports"
    }
}
if (-not (Test-Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$includeRules = $IncludeInboxRules -match '^(?i)(true|yes|1)$'
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "MailboxForwarding_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "MailboxForwarding_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
} catch {
    Write-Log "ExchangeOnlineManagement module not available. Install with: Install-Module ExchangeOnlineManagement -Scope CurrentUser" "Red"
    exit 1
}

$connection = Get-ConnectionInformation -ErrorAction SilentlyContinue
if (-not $connection) {
    Write-Log "Not connected to Exchange Online. Opening sign-in (browser)..." "Cyan"
    try {
        Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    } catch {
        Write-Log "Failed to connect to Exchange Online: $($_.Exception.Message)" "Red"
        exit 1
    }
}

Write-Log "Retrieving mailboxes and checking mailbox-level forwarding..." "Cyan"
try {
    $mailboxes = @(Get-Mailbox -ResultSize Unlimited -ErrorAction Stop)
} catch {
    Write-Log "Error retrieving mailboxes: $($_.Exception.Message)" "Red"
    exit 1
}

$results = @()

$forwarding = @($mailboxes | Where-Object { $_.ForwardingSmtpAddress -or $_.ForwardingAddress -or $_.DeliverToMailboxAndForward })
foreach ($mailbox in $forwarding) {
    $isExternal = [bool]$mailbox.ForwardingSmtpAddress
    $results += [PSCustomObject]@{
        Mailbox              = $mailbox.UserPrincipalName
        DisplayName          = $mailbox.DisplayName
        Source               = "MailboxConfig"
        RuleName             = ""
        ForwardingSmtpAddress= $mailbox.ForwardingSmtpAddress
        ForwardingAddress    = $mailbox.ForwardingAddress
        KeepCopy             = $mailbox.DeliverToMailboxAndForward
        ExternalForwarding   = $isExternal
    }
    if ($isExternal) {
        Write-Log "EXTERNAL FORWARDING: $($mailbox.UserPrincipalName) -> $($mailbox.ForwardingSmtpAddress)" "Red"
    } else {
        Write-Log "Internal forwarding: $($mailbox.UserPrincipalName) -> $($mailbox.ForwardingAddress)" "Yellow"
    }
}

# --- Optional: inbox rules that forward/redirect (slow on large tenants) ---
$ruleSkips = 0
if ($includeRules) {
    Write-Log "Checking inbox rules on $($mailboxes.Count) mailboxes - this can be SLOW on large tenants..." "Yellow"
    $checked = 0
    foreach ($mailbox in $mailboxes) {
        $checked++
        if ($checked % 100 -eq 0) {
            Write-Log "  ...checked $checked of $($mailboxes.Count) mailboxes" "Cyan"
        }
        try {
            $rules = @(Get-InboxRule -Mailbox $mailbox.UserPrincipalName -ErrorAction SilentlyContinue |
                Where-Object { $_.ForwardTo -or $_.RedirectTo -or $_.ForwardAsAttachmentTo })
            foreach ($rule in $rules) {
                $targets = @($rule.ForwardTo) + @($rule.RedirectTo) + @($rule.ForwardAsAttachmentTo) | Where-Object { $_ }
                $results += [PSCustomObject]@{
                    Mailbox              = $mailbox.UserPrincipalName
                    DisplayName          = $mailbox.DisplayName
                    Source               = "InboxRule"
                    RuleName             = $rule.Name
                    ForwardingSmtpAddress= ($targets -join "; ")
                    ForwardingAddress    = ""
                    KeepCopy             = ""
                    ExternalForwarding   = ""
                }
                Write-Log "INBOX RULE: $($mailbox.UserPrincipalName) rule '$($rule.Name)' forwards/redirects mail" "Yellow"
            }
        } catch {
            $ruleSkips++
        }
    }
    if ($ruleSkips -gt 0) {
        Write-Log "Mailboxes skipped during inbox-rule check: $ruleSkips" "Yellow"
    }
}

Write-Host ""
if ($results.Count -gt 0) {
    $results | Format-Table Mailbox, Source, RuleName, ForwardingSmtpAddress, ForwardingAddress, KeepCopy -AutoSize | Out-String | Write-Host
    $externalCount = @($results | Where-Object { $_.ExternalForwarding -eq $true }).Count
    $ruleCount     = @($results | Where-Object { $_.Source -eq 'InboxRule' }).Count
    Write-Log "Forwarding findings: $($results.Count) (external SMTP: $externalCount, inbox rules: $ruleCount) across $($mailboxes.Count) mailboxes" "Yellow"
    if ($externalCount -gt 0) {
        Write-Log "Review external forwarding entries above - possible data exfiltration risk." "Red"
    }
} else {
    Write-Log "No mailbox forwarding found across $($mailboxes.Count) mailboxes." "Green"
}
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Log "Report saved: $outputFile" "Green"
