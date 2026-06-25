# Copy all AD group memberships from a source user to a target user

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceUser,
    [Parameter(Mandatory=$true)]
    [string]$TargetUser
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "  $(Get-Date -Format 'HH:mm:ss')  $Message" -ForegroundColor $Color
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Log "ActiveDirectory module not found. Install RSAT." "Red"; exit 1
}

try {
    $source = Get-ADUser -Identity $SourceUser -Properties DisplayName, MemberOf -ErrorAction Stop
    $target = Get-ADUser -Identity $TargetUser -Properties DisplayName, MemberOf -ErrorAction Stop
} catch {
    Write-Log "Lookup failed: $($_.Exception.Message)" "Red"; exit 1
}

Write-Host ""
Write-Host ("  Copying groups from: {0}  [{1}]" -f $source.DisplayName, $source.SamAccountName) -ForegroundColor Cyan
Write-Host ("  To:                  {0}  [{1}]" -f $target.DisplayName, $target.SamAccountName) -ForegroundColor Yellow
Write-Host ""

$sourceGroups = $source.MemberOf
$targetGroups = $target.MemberOf

$toAdd    = $sourceGroups | Where-Object { $_ -notin $targetGroups }
$already  = $sourceGroups | Where-Object { $_ -in $targetGroups }
$skipped  = 0
$added    = 0
$errors   = 0

Write-Log "Source has $($sourceGroups.Count) group(s). Target already has $($already.Count) in common." "Gray"
Write-Host ""

foreach ($groupDN in $toAdd) {
    try {
        $groupName = (Get-ADGroup $groupDN).Name
        if ($groupName -eq "Domain Users") { $skipped++; continue }
        Add-ADGroupMember -Identity $groupDN -Members $TargetUser -ErrorAction Stop
        Write-Log "  Added:   $groupName" "Green"
        $added++
    } catch {
        Write-Log "  Failed:  $groupDN — $($_.Exception.Message)" "Red"
        $errors++
    }
}

if ($already.Count -gt 0) {
    Write-Host ""
    Write-Host "  Already a member of:" -ForegroundColor DarkGray
    $already | ForEach-Object {
        $name = (Get-ADGroup $_).Name
        Write-Host ("  [skip]   {0}" -f $name) -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Log "Added: $added  |  Already member: $($already.Count)  |  Skipped: $skipped  |  Errors: $errors" `
    "$(if ($errors -gt 0) { 'Yellow' } else { 'Green' })"
