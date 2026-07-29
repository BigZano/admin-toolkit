# List all members of an Active Directory group with optional recursive expansion

param(
    [Parameter(Mandatory=$true)]
    [string]$GroupName,
    [Parameter(Mandatory=$false)]
    [string]$Recursive = "false",
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
$safeName   = $GroupName -replace '[\\/:*?"<>|]', '_'
$outputFile = Join-Path $OutputDirectory "GroupMembers_${safeName}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "GroupMembers_${safeName}_$timestamp.log"

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

Write-Log "Looking up group: $GroupName" "Cyan"

try {
    $group = Get-ADGroup -Identity $GroupName -Properties Description, GroupCategory, GroupScope -ErrorAction Stop
} catch {
    Write-Log "Group '$GroupName' not found: $($_.Exception.Message)" "Red"
    exit 1
}

Write-Host ""
Write-Host "  Group:    $($group.Name)" -ForegroundColor Yellow
Write-Host "  Category: $($group.GroupCategory)  |  Scope: $($group.GroupScope)" -ForegroundColor Gray
if ($group.Description) { Write-Host "  Desc:     $($group.Description)" -ForegroundColor Gray }
Write-Host ""

$isRecursive = $Recursive -eq "true" -or $Recursive -eq "1"
$expandMode = if ($isRecursive) { "Recursive" } else { "Direct members only" }
Write-Log "Retrieving members ($expandMode)..." "Cyan"

try {
    try {
        $members = if ($isRecursive) {
            Get-ADGroupMember -Identity $GroupName -Recursive -ErrorAction Stop
        } else {
            Get-ADGroupMember -Identity $GroupName -ErrorAction Stop
        }
    } catch {
        # Get-ADGroupMember fails on very large groups (ADWS limit) and on groups
        # containing foreign security principals — fall back to LDAP enumeration.
        Write-Log "Get-ADGroupMember failed ($($_.Exception.Message)). Falling back to LDAP enumeration." "Yellow"
        $members = if ($isRecursive) {
            Get-ADObject -LDAPFilter "(memberOf:1.2.840.113556.1.4.1941:=$($group.DistinguishedName))" `
                -Properties objectClass, SamAccountName -ErrorAction Stop
        } else {
            (Get-ADGroup -Identity $GroupName -Properties Members -ErrorAction Stop).Members |
                ForEach-Object { Get-ADObject $_ -Properties objectClass, SamAccountName -ErrorAction Stop }
        }
    }

    $report = $members | ForEach-Object {
        $member = $_
        if ($_.objectClass -eq "user") {
            try {
                $u = Get-ADUser $member.distinguishedName -Properties DisplayName, EmailAddress, Enabled, Department, Title -ErrorAction Stop
                [PSCustomObject]@{
                    Type           = "User"
                    SamAccountName = $u.SamAccountName
                    DisplayName    = $u.DisplayName
                    Email          = $u.EmailAddress
                    Department     = $u.Department
                    Title          = $u.Title
                    Enabled        = $u.Enabled
                }
            } catch {
                Write-Log "  Could not resolve member '$($member.SamAccountName)': $($_.Exception.Message)" "Yellow"
                [PSCustomObject]@{
                    Type           = "User"
                    SamAccountName = $member.SamAccountName
                    DisplayName    = "<lookup failed>"
                    Email          = ""
                    Department     = ""
                    Title          = ""
                    Enabled        = "?"
                }
            }
        } elseif ($_.objectClass -eq "group") {
            [PSCustomObject]@{
                Type           = "Group"
                SamAccountName = $_.SamAccountName
                DisplayName    = $_.Name
                Email          = ""
                Department     = ""
                Title          = ""
                Enabled        = "N/A"
            }
        } else {
            [PSCustomObject]@{
                Type           = $_.objectClass
                SamAccountName = $_.SamAccountName
                DisplayName    = $_.Name
                Email          = ""
                Department     = ""
                Title          = ""
                Enabled        = "N/A"
            }
        }
    } | Sort-Object Type, DisplayName

    $users     = @($report | Where-Object { $_.Type -eq "User" })
    $nested    = @($report | Where-Object { $_.Type -eq "Group" })
    $computers = @($report | Where-Object { $_.Type -eq "computer" })

    Write-Host "  Users: $($users.Count)  |  Nested Groups: $($nested.Count)  |  Computers: $($computers.Count)" -ForegroundColor Cyan
    Write-Host ""

    $report | ForEach-Object {
        $color = switch ($_.Type) {
            "User"     { if ($_.Enabled -eq $false) { "DarkGray" } else { "White" } }
            "Group"    { "DarkYellow" }
            "computer" { "Blue" }
            default    { "Gray" }
        }
        $status = if ($_.Type -eq "User" -and $_.Enabled -eq $false) { " [DISABLED]" } else { "" }
        Write-Host ("  [{0,-8}] {1,-30} {2}{3}" -f $_.Type, $_.SamAccountName, $_.DisplayName, $status) -ForegroundColor $color
    }

    $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Write-Log "Report saved to: $outputFile" "Green"
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"
    exit 1
}
