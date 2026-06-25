# Full user offboarding: disable account, strip groups, hide from GAL, set OOO, move to disabled OU

param(
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$false)]
    [string]$DisabledOU = "",
    [Parameter(Mandatory=$false)]
    [string]$OOOMessage = "",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = if ($IsWindows -or $env:OS -match "Windows") {
        Join-Path $env:USERPROFILE "Documents\AdminToolReports"
    } else { Join-Path $env:HOME "Documents/AdminToolReports" }
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile    = Join-Path $OutputDirectory "Offboard_${Username}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White", [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    "[$ts] [$Level] $Message" | Out-File $logFile -Append
    Write-Host "  $ts  $Message" -ForegroundColor $Color
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Log "ActiveDirectory module not found. Install RSAT." "Red" "ERROR"; exit 1
}

try {
    $user = Get-ADUser -Identity $Username -Properties `
        DisplayName, Enabled, MemberOf, EmailAddress, DistinguishedName -ErrorAction Stop
} catch {
    Write-Log "User '$Username' not found: $($_.Exception.Message)" "Red" "ERROR"; exit 1
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ("  OFFBOARDING: {0}  [{1}]" -f $user.DisplayName, $user.SamAccountName) -ForegroundColor Yellow
Write-Host ("  Email: {0}" -f $user.EmailAddress) -ForegroundColor Gray
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""

$completed = [System.Collections.Generic.List[string]]::new()
$failed    = [System.Collections.Generic.List[string]]::new()

# ── 1. Disable account ────────────────────────────────────────────────────────
Write-Host "  [1/5] Disabling account..." -ForegroundColor Cyan
if (-not $user.Enabled) {
    Write-Log "Account already disabled." "Yellow"
    $completed.Add("Disable: already disabled")
} else {
    try {
        Disable-ADAccount -Identity $Username -ErrorAction Stop
        Write-Log "Account disabled." "Green" "OK"
        $completed.Add("Account disabled")
    } catch {
        Write-Log "Failed to disable: $($_.Exception.Message)" "Red" "ERROR"
        $failed.Add("Disable account")
    }
}

# ── 2. Strip group memberships ────────────────────────────────────────────────
Write-Host "  [2/5] Removing group memberships..." -ForegroundColor Cyan
$groups = $user.MemberOf
$removedGroups = [System.Collections.Generic.List[string]]::new()

foreach ($groupDN in $groups) {
    try {
        $groupName = (Get-ADGroup $groupDN).Name
        # Never remove from Domain Users — it's the primary group and can't be removed this way
        if ($groupName -eq "Domain Users") { continue }
        Remove-ADGroupMember -Identity $groupDN -Members $Username -Confirm:$false -ErrorAction Stop
        Write-Log "  Removed from: $groupName" "Green" "OK"
        $removedGroups.Add($groupName)
    } catch {
        Write-Log "  Failed to remove from $groupDN : $($_.Exception.Message)" "Yellow" "WARN"
    }
}
Write-Log "Removed from $($removedGroups.Count) group(s)." "Green" "OK"
$completed.Add("Removed from $($removedGroups.Count) groups")

# ── 3. Set Out of Office (Exchange Online) ───────────────────────────────────
Write-Host "  [3/5] Setting Out of Office reply..." -ForegroundColor Cyan
if (-not [string]::IsNullOrEmpty($OOOMessage) -and -not [string]::IsNullOrEmpty($user.EmailAddress)) {
    try {
        $exchCheck = Get-Command Set-MailboxAutoReplyConfiguration -ErrorAction SilentlyContinue
        if ($exchCheck) {
            Set-MailboxAutoReplyConfiguration -Identity $user.EmailAddress `
                -AutoReplyState Enabled `
                -InternalMessage $OOOMessage `
                -ExternalMessage $OOOMessage -ErrorAction Stop
            Write-Log "Out of Office set." "Green" "OK"
            $completed.Add("OOO set")
        } else {
            Write-Log "Exchange cmdlets not available. Connect to Exchange Online first." "Yellow" "WARN"
            $failed.Add("OOO (no Exchange connection)")
        }
    } catch {
        Write-Log "Failed to set OOO: $($_.Exception.Message)" "Yellow" "WARN"
        $failed.Add("OOO: $($_.Exception.Message)")
    }
} else {
    Write-Log "Skipped — no OOO message provided or no email address on account." "Yellow"
}

# ── 4. Hide from Global Address List ─────────────────────────────────────────
Write-Host "  [4/5] Hiding from Global Address List..." -ForegroundColor Cyan
try {
    $exchCheck = Get-Command Set-Mailbox -ErrorAction SilentlyContinue
    if ($exchCheck -and -not [string]::IsNullOrEmpty($user.EmailAddress)) {
        Set-Mailbox -Identity $user.EmailAddress -HiddenFromAddressListsEnabled $true -ErrorAction Stop
        Write-Log "Hidden from GAL." "Green" "OK"
        $completed.Add("Hidden from GAL")
    } else {
        Write-Log "Skipped — Exchange cmdlets not available or no mailbox." "Yellow"
    }
} catch {
    Write-Log "Failed to hide from GAL: $($_.Exception.Message)" "Yellow" "WARN"
    $failed.Add("Hide from GAL")
}

# ── 5. Move to disabled OU ────────────────────────────────────────────────────
Write-Host "  [5/5] Moving to disabled OU..." -ForegroundColor Cyan
if (-not [string]::IsNullOrEmpty($DisabledOU)) {
    try {
        Move-ADObject -Identity $user.DistinguishedName -TargetPath $DisabledOU -ErrorAction Stop
        Write-Log "Moved to: $DisabledOU" "Green" "OK"
        $completed.Add("Moved to disabled OU")
    } catch {
        Write-Log "Failed to move: $($_.Exception.Message)" "Red" "ERROR"
        $failed.Add("Move to OU")
    }
} else {
    Write-Log "Skipped — no target OU provided." "Yellow"
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host "  OFFBOARDING COMPLETE" -ForegroundColor $(if ($failed.Count -eq 0) { "Green" } else { "Yellow" })
Write-Host ""
$completed | ForEach-Object { Write-Host "  [DONE]   $_" -ForegroundColor Green }
$failed    | ForEach-Object { Write-Host "  [FAILED] $_" -ForegroundColor Red }
Write-Host ""
Write-Log "Log saved to: $logFile" "Cyan"
Write-Host ("=" * 60) -ForegroundColor DarkGray
Write-Host ""

# Save removed groups list for record
$record = [PSCustomObject]@{
    Username       = $user.SamAccountName
    DisplayName    = $user.DisplayName
    Email          = $user.EmailAddress
    OffboardDate   = Get-Date -Format "yyyy-MM-dd HH:mm"
    GroupsRemoved  = $removedGroups -join "; "
    Completed      = $completed -join "; "
    Failed         = $failed -join "; "
}
$csvFile = Join-Path $OutputDirectory "Offboard_${Username}_$timestamp.csv"
$record | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
