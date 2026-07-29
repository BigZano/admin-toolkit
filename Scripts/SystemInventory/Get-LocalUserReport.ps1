# Report local user accounts with status and group membership

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
$outputFile = Join-Path $OutputDirectory "Get-LocalUserReport_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Get-LocalUserReport_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "Collecting local user accounts..." "Cyan"

try {
    $users = @(Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True" -ErrorAction Stop)
} catch {
    Write-Log "ERROR: Failed to enumerate local accounts: $($_.Exception.Message)" "Red"
    exit 1
}

# Enumerate members of the local Administrators group.
# Primary: ADSI WinNT provider; fallback: parse net localgroup output.
$adminMembers = @()
$adminSource  = ""
try {
    $group = [ADSI]"WinNT://./Administrators,group"
    $members = @($group.psbase.Invoke("Members"))
    foreach ($member in $members) {
        try {
            $name = $member.GetType().InvokeMember("Name", 'GetProperty', $null, $member, $null)
            $adminMembers += "$name"
        } catch { }
    }
    $adminSource = "ADSI"
} catch {
    Write-Log "ADSI enumeration of Administrators failed, falling back to net.exe: $($_.Exception.Message)" "Yellow"
    try {
        $raw = net localgroup Administrators 2>&1 | Out-String
        $lines = $raw -split "`r?`n"
        $inList = $false
        foreach ($line in $lines) {
            if ($line -match '^-{5,}') { $inList = $true; continue }
            if ($inList) {
                if ($line -match '(?i)The command completed') { break }
                $trimmed = $line.Trim()
                if ($trimmed) { $adminMembers += ($trimmed -replace '^.*\\', '') }
            }
        }
        $adminSource = "net.exe"
    } catch {
        Write-Log "Could not enumerate Administrators group members: $($_.Exception.Message)" "Yellow"
    }
}

if ($adminSource) {
    Write-Log "Administrators group members ($adminSource): $($adminMembers -join ', ')"
}

$results = @()
foreach ($user in $users) {
    $isAdminMember = $adminMembers -contains $user.Name
    $results += [PSCustomObject]@{
        Name            = $user.Name
        Disabled        = $user.Disabled
        LockedOut       = $user.Lockout
        PasswordExpires = $user.PasswordExpires
        IsAdmin         = $isAdminMember
        SID             = $user.SID
        Description     = $user.Description
    }
}

$results = @($results | Sort-Object Name)
$results | Export-Csv -Path $outputFile -NoTypeInformation
$results | Format-Table Name, Disabled, LockedOut, PasswordExpires, IsAdmin -AutoSize

$enabled = @($results | Where-Object { -not $_.Disabled })
$admins  = @($results | Where-Object { $_.IsAdmin })
Write-Log "Total local accounts: $($results.Count); enabled: $($enabled.Count); local admins: $($admins.Count)" "Cyan"
if ($admins.Count -gt 0) {
    Write-Log "Admin accounts: $(($admins.Name) -join ', ')" "Yellow"
}
Write-Log "Report saved: $outputFile" "Green"
