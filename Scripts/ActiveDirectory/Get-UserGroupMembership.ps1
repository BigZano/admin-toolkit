# List all Active Directory group memberships for a specific user

param(
    [Parameter(Mandatory=$true)]
    [string]$Username,
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

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "GroupMembership_${Username}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "GroupMembership_${Username}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Log "ActiveDirectory module not found. Install RSAT." "Red"
    exit 1
}

Write-Log "Looking up user: $Username" "Cyan"

try {
    $user = Get-ADUser -Identity $Username -Properties DisplayName, EmailAddress -ErrorAction Stop
} catch {
    Write-Log "User '$Username' not found: $($_.Exception.Message)" "Red"
    exit 1
}

Write-Log "Retrieving group memberships for $($user.DisplayName)..." "Cyan"

try {
    $groups = Get-ADPrincipalGroupMembership -Identity $Username |
        Get-ADGroup -Properties Description, GroupCategory, GroupScope |
        Sort-Object Name |
        ForEach-Object {
            [PSCustomObject]@{
                GroupName    = $_.Name
                Category     = $_.GroupCategory
                Scope        = $_.GroupScope
                Description  = $_.Description
                DistinguishedName = $_.DistinguishedName
            }
        }

    Write-Log "Member of $($groups.Count) groups." "Green"
    Write-Host ""

    $groups | ForEach-Object {
        $color = switch ($_.Category) {
            "Security"     { "Cyan" }
            "Distribution" { "DarkYellow" }
            default        { "White" }
        }
        Write-Host ("  {0,-45} [{1} / {2}]" -f $_.GroupName, $_.Category, $_.Scope) -ForegroundColor $color
        if ($_.Description) {
            Write-Host ("  {0,-45} {1}" -f "", $_.Description) -ForegroundColor DarkGray
        }
    }

    $groups | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Write-Log "Report saved to: $outputFile" "Green"
} catch {
    Write-Log "Error retrieving groups: $($_.Exception.Message)" "Red"
    exit 1
}
