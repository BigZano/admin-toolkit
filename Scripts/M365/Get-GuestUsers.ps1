# List all guest users in Entra ID with invite state

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
$outputFile = Join-Path $OutputDirectory "GuestUsers_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "GuestUsers_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module Microsoft.Graph.Users -ErrorAction Stop
} catch {
    Write-Log "Microsoft.Graph.Users module not available. Install with: Install-Module Microsoft.Graph -Scope CurrentUser" "Red"
    exit 1
}

if (-not (Get-MgContext)) {
    Write-Log "Not connected to Microsoft Graph. Opening sign-in (browser)..." "Cyan"
    try {
        Connect-MgGraph -Scopes "User.Read.All" -NoWelcome -ErrorAction Stop
    } catch {
        Write-Log "Failed to connect to Microsoft Graph: $($_.Exception.Message)" "Red"
        exit 1
    }
}

Write-Log "Retrieving guest users..." "Cyan"
try {
    $guests = @(Get-MgUser -Filter "userType eq 'Guest'" -All `
        -Property Id, DisplayName, Mail, UserPrincipalName, CreatedDateTime, AccountEnabled, ExternalUserState, ExternalUserStateChangeDateTime `
        -ErrorAction Stop)
} catch {
    Write-Log "Error retrieving guest users: $($_.Exception.Message)" "Red"
    exit 1
}

$results = @()
foreach ($guest in $guests) {
    try {
        $results += [PSCustomObject]@{
            DisplayName       = $guest.DisplayName
            Mail              = $guest.Mail
            UserPrincipalName = $guest.UserPrincipalName
            AccountEnabled    = $guest.AccountEnabled
            InviteState       = $guest.ExternalUserState
            InviteStateChanged= if ($guest.ExternalUserStateChangeDateTime) { $guest.ExternalUserStateChangeDateTime.ToString("yyyy-MM-dd") } else { "" }
            Created           = if ($guest.CreatedDateTime) { $guest.CreatedDateTime.ToString("yyyy-MM-dd") } else { "" }
            Id                = $guest.Id
        }
    } catch {
        Write-Log "Skipped guest $($guest.UserPrincipalName): $($_.Exception.Message)" "Yellow"
    }
}

$results = @($results | Sort-Object Created -Descending)

Write-Host ""
if ($results.Count -gt 0) {
    $results | Format-Table DisplayName, Mail, InviteState, AccountEnabled, Created -AutoSize | Out-String | Write-Host

    $pending = @($results | Where-Object { $_.InviteState -eq "PendingAcceptance" })
    foreach ($guest in $pending) {
        Write-Log "PENDING: $($guest.DisplayName) ($($guest.Mail)) - invite not yet accepted (sent/created $($guest.Created))" "Yellow"
    }
    Write-Log "Guest users found: $($results.Count) (pending acceptance: $($pending.Count))" "Cyan"
} else {
    Write-Log "No guest users found in this tenant." "Green"
}
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Log "Report saved: $outputFile" "Green"
