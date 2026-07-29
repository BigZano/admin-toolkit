# Find AD groups with no members

param(
    [Parameter(Mandatory=$false)]
    [string]$ExcludeBuiltin = "true",
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

$excludeBuiltinFlag = $ExcludeBuiltin -match '^(?i)(true|yes|1)$'
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "EmptyGroups_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "EmptyGroups_$timestamp.log"

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

Write-Log "Searching for groups with no members (ExcludeBuiltin=$excludeBuiltinFlag)..." "Cyan"

try {
    $groups = Get-ADGroup -Filter * `
        -Properties Members, whenCreated, Description, GroupCategory, IsCriticalSystemObject, DistinguishedName -ErrorAction Stop
} catch {
    Write-Log "Error querying AD: $($_.Exception.Message)" "Red"
    exit 1
}

$empty = foreach ($group in $groups) {
    if ($group.Members.Count -gt 0) { continue }

    if ($excludeBuiltinFlag) {
        if ($group.DistinguishedName -match ',CN=Builtin,') { continue }
        if ($group.IsCriticalSystemObject) { continue }
    }

    [PSCustomObject]@{
        Name          = $group.Name
        GroupCategory = $group.GroupCategory
        GroupScope    = $group.GroupScope
        Description   = $group.Description
        Created       = $group.whenCreated.ToString("yyyy-MM-dd")
        OU            = ($group.DistinguishedName -replace '^CN=[^,]+,', '')
    }
}

$empty = @($empty | Sort-Object Name)

Write-Host ""
if ($empty.Count -gt 0) {
    $empty | Format-Table Name, GroupCategory, GroupScope, Created, Description -AutoSize | Out-String | Write-Host
    Write-Log "Empty groups found: $($empty.Count) of $($groups.Count) total groups" "Yellow"
} else {
    Write-Log "No empty groups found (checked $($groups.Count) groups)." "Green"
}
$empty | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Log "Report saved: $outputFile" "Green"
