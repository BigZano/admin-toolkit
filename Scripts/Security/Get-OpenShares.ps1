# Audit shared folders and their permissions, flagging broad access grants

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
    [Parameter(Mandatory=$false)]
    [string]$IncludeAdminShares = "false",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = if ($IsWindows -or $env:OS -match "Windows") {
        Join-Path $env:USERPROFILE "Documents\AdminToolReports"
    } else { Join-Path $env:HOME "Documents/AdminToolReports" }
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$target     = if ([string]::IsNullOrEmpty($ComputerName)) { $env:COMPUTERNAME } else { $ComputerName }
$showAdmin  = $IncludeAdminShares -eq "true" -or $IncludeAdminShares -eq "1"
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "OpenShares_${target}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "OpenShares_${target}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "Auditing shares on: $target" "Cyan"

try {
    $cimParams = if ($target -ne $env:COMPUTERNAME) { @{ CimSession = $target } } else { @{} }

    $shares = Get-SmbShare @cimParams -ErrorAction Stop

    if (-not $showAdmin) {
        $shares = $shares | Where-Object {
            $_.Name -notmatch '^\w\$$' -and $_.Name -notin @("ADMIN$", "IPC$", "print$")
        }
    }

    Write-Log "Found $($shares.Count) share(s) (admin shares: $showAdmin)." "Cyan"
    Write-Host ""

    $report = foreach ($share in ($shares | Sort-Object Name)) {
        $acl = Get-SmbShareAccess -Name $share.Name @cimParams -ErrorAction SilentlyContinue

        $everyoneAccess  = $acl | Where-Object { $_.AccountName -match "Everyone" -and $_.AccessRight -ne "Deny" }
        $authUsersAccess = $acl | Where-Object { $_.AccountName -match "Authenticated Users" -and $_.AccessRight -ne "Deny" }
        $broadAccess     = $everyoneAccess -or $authUsersAccess

        $color = if ($broadAccess -and ($everyoneAccess.AccessRight -eq "Full" -or $authUsersAccess.AccessRight -eq "Full")) { "Red" }
                 elseif ($broadAccess) { "Yellow" }
                 else { "White" }

        Write-Host ("  \\{0}\{1}" -f $target, $share.Name) -ForegroundColor $color
        Write-Host ("    Path: {0}  |  Type: {1}  |  Description: {2}" -f $share.Path, $share.ShareType, $share.Description) -ForegroundColor DarkGray

        foreach ($ace in $acl) {
            $aceColor = if ($ace.AccountName -match "Everyone" -and $ace.AccessRight -ne "Deny") { "Red" }
                        elseif ($ace.AccountName -match "Authenticated Users") { "Yellow" }
                        else { "Gray" }
            Write-Host ("    {0,-35} {1,-10} [{2}]" -f $ace.AccountName, $ace.AccessRight, $ace.AccessControlType) -ForegroundColor $aceColor
        }
        Write-Host ""

        foreach ($ace in $acl) {
            [PSCustomObject]@{
                ShareName    = $share.Name
                SharePath    = $share.Path
                ShareType    = $share.ShareType
                AccountName  = $ace.AccountName
                AccessRight  = $ace.AccessRight
                AccessType   = $ace.AccessControlType
                BroadAccess  = [bool]$broadAccess
            }
        }
    }

    $broadShares = @($report | Where-Object { $_.BroadAccess } | Select-Object -Unique ShareName)
    Write-Log "Shares with broad access (Everyone/Auth Users): $($broadShares.Count)" `
        "$(if ($broadShares.Count -gt 0) { 'Yellow' } else { 'Green' })"

    $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Log "Report saved to: $outputFile" "Green"
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
