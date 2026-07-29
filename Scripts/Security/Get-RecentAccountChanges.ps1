# Find AD accounts created or modified in the last X days

param(
    [Parameter(Mandatory=$false)]
    [string]$DaysBack = "7",
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

$days       = [int]$DaysBack
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "RecentAccountChanges_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "RecentAccountChanges_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Log "ActiveDirectory module not available. Install RSAT (Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0)." "Red"
    exit 1
}

$cutoff = (Get-Date).AddDays(-$days)
Write-Log "Searching for accounts created or modified since $($cutoff.ToString('yyyy-MM-dd HH:mm')) ($days days)..." "Cyan"
Write-Log "NOTE: whenChanged also moves on replication-driven updates (e.g. lastLogonTimestamp sync), not only admin edits." "Yellow"

# whenCreated / whenChanged are real server-side attributes - safe to filter on
try {
    $created = @(Get-ADUser -Filter 'whenCreated -ge $cutoff' `
        -Properties whenCreated, whenChanged, Enabled, DisplayName, DistinguishedName -ErrorAction Stop)
} catch {
    Write-Log "Error querying created accounts: $($_.Exception.Message)" "Red"
    exit 1
}

try {
    $modified = @(Get-ADUser -Filter 'whenChanged -ge $cutoff' `
        -Properties whenCreated, whenChanged, Enabled, DisplayName, DistinguishedName -ErrorAction Stop)
} catch {
    Write-Log "Error querying modified accounts: $($_.Exception.Message)" "Red"
    exit 1
}

$createdSams = @($created | ForEach-Object { $_.SamAccountName })

$results = @()
foreach ($user in $created) {
    $results += [PSCustomObject]@{
        SamAccountName = $user.SamAccountName
        DisplayName    = $user.DisplayName
        ChangeType     = "Created"
        Enabled        = $user.Enabled
        WhenCreated    = $user.whenCreated.ToString("yyyy-MM-dd HH:mm")
        WhenChanged    = $user.whenChanged.ToString("yyyy-MM-dd HH:mm")
        OU             = ($user.DistinguishedName -replace '^CN=[^,]+,', '')
    }
}
foreach ($user in $modified) {
    if ($createdSams -contains $user.SamAccountName) { continue }  # already listed as Created
    $results += [PSCustomObject]@{
        SamAccountName = $user.SamAccountName
        DisplayName    = $user.DisplayName
        ChangeType     = "Modified"
        Enabled        = $user.Enabled
        WhenCreated    = $user.whenCreated.ToString("yyyy-MM-dd HH:mm")
        WhenChanged    = $user.whenChanged.ToString("yyyy-MM-dd HH:mm")
        OU             = ($user.DistinguishedName -replace '^CN=[^,]+,', '')
    }
}

$results = @($results | Sort-Object WhenChanged -Descending)

Write-Host ""
if ($results.Count -gt 0) {
    $results | Format-Table SamAccountName, DisplayName, ChangeType, Enabled, WhenCreated, WhenChanged -AutoSize | Out-String | Write-Host
    $createdCount  = @($results | Where-Object { $_.ChangeType -eq 'Created' }).Count
    $modifiedCount = @($results | Where-Object { $_.ChangeType -eq 'Modified' }).Count
    Write-Log "Accounts changed in last $days days: $($results.Count) (created: $createdCount, modified: $modifiedCount)" "Yellow"
} else {
    Write-Log "No accounts created or modified in the last $days days." "Green"
}
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Log "Report saved: $outputFile" "Green"
