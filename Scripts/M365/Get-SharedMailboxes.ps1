# List shared mailboxes with size and full-access delegates

param(
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

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "SharedMailboxes_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "SharedMailboxes_$timestamp.log"

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

Write-Log "Retrieving shared mailboxes..." "Cyan"
try {
    $shared = @(Get-EXOMailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -ErrorAction Stop)
} catch {
    Write-Log "Error retrieving shared mailboxes: $($_.Exception.Message)" "Red"
    exit 1
}

Write-Log "Found $($shared.Count) shared mailboxes. Gathering size and delegate details..." "Cyan"

$results   = @()
$statSkips = 0
$permSkips = 0

foreach ($mailbox in $shared) {
    $sizeDisplay = "Unknown"
    $itemCount   = ""
    $stats = Get-EXOMailboxStatistics -Identity $mailbox.UserPrincipalName -ErrorAction SilentlyContinue
    if ($stats) {
        $sizeDisplay = "$($stats.TotalItemSize)"
        $itemCount   = $stats.ItemCount
    } else {
        $statSkips++
    }

    $delegates = ""
    $perms = Get-EXOMailboxPermission -Identity $mailbox.UserPrincipalName -ErrorAction SilentlyContinue
    if ($perms) {
        $delegates = (@($perms | Where-Object {
            $_.AccessRights -contains "FullAccess" -and
            $_.User -notmatch '^NT AUTHORITY\\SELF$'
        } | ForEach-Object { $_.User }) -join "; ")
    } else {
        $permSkips++
    }

    $results += [PSCustomObject]@{
        DisplayName         = $mailbox.DisplayName
        UserPrincipalName   = $mailbox.UserPrincipalName
        PrimarySmtpAddress  = $mailbox.PrimarySmtpAddress
        TotalItemSize       = $sizeDisplay
        ItemCount           = $itemCount
        FullAccessDelegates = $delegates
    }
}

$results = @($results | Sort-Object DisplayName)

Write-Host ""
if ($results.Count -gt 0) {
    $results | Format-Table DisplayName, PrimarySmtpAddress, TotalItemSize, ItemCount, FullAccessDelegates -AutoSize | Out-String | Write-Host
    Write-Log "Shared mailboxes: $($results.Count)" "Cyan"
    $noDelegates = @($results | Where-Object { -not $_.FullAccessDelegates }).Count
    if ($noDelegates -gt 0) {
        Write-Log "Shared mailboxes with no full-access delegates: $noDelegates" "Yellow"
    }
} else {
    Write-Log "No shared mailboxes found." "Green"
}
if ($statSkips -gt 0) { Write-Log "Mailboxes where statistics could not be read: $statSkips" "Yellow" }
if ($permSkips -gt 0) { Write-Log "Mailboxes where permissions could not be read: $permSkips" "Yellow" }
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Log "Report saved: $outputFile" "Green"
