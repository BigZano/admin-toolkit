# Report domain password policy and fine-grained policies

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
$outputFile = Join-Path $OutputDirectory "PasswordPolicy_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "PasswordPolicy_$timestamp.log"

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

function Get-PolicyWeaknesses {
    param($Policy)
    $weak = @()
    if ($Policy.MinPasswordLength -lt 12) {
        $weak += "MinPasswordLength $($Policy.MinPasswordLength) < 12"
    }
    if (-not $Policy.ComplexityEnabled) {
        $weak += "Complexity disabled"
    }
    if ($Policy.MaxPasswordAge -and ($Policy.MaxPasswordAge.TotalDays -eq 0 -or $Policy.MaxPasswordAge.TotalDays -gt 365)) {
        $weak += "MaxPasswordAge $([int]$Policy.MaxPasswordAge.TotalDays) days (0 = never expires, >365 = too long)"
    }
    if ($Policy.LockoutThreshold -eq 0) {
        $weak += "LockoutThreshold 0 (no lockout)"
    }
    return $weak
}

$results = @()

# --- Default domain policy ---
Write-Log "Reading default domain password policy..." "Cyan"
try {
    $default = Get-ADDefaultDomainPasswordPolicy -ErrorAction Stop
} catch {
    Write-Log "Error reading default domain password policy: $($_.Exception.Message)" "Red"
    exit 1
}

$defaultWeak = Get-PolicyWeaknesses -Policy $default
$results += [PSCustomObject]@{
    PolicyName          = "Default Domain Policy"
    PolicyType          = "Default"
    AppliesTo           = (Get-ADDomain -ErrorAction SilentlyContinue).DNSRoot
    Precedence          = ""
    MinPasswordLength   = $default.MinPasswordLength
    ComplexityEnabled   = $default.ComplexityEnabled
    MaxPasswordAgeDays  = [int]$default.MaxPasswordAge.TotalDays
    MinPasswordAgeDays  = [int]$default.MinPasswordAge.TotalDays
    PasswordHistory     = $default.PasswordHistoryCount
    LockoutThreshold    = $default.LockoutThreshold
    LockoutDurationMins = [int]$default.LockoutDuration.TotalMinutes
    ReversibleEncryption= $default.ReversibleEncryptionEnabled
    Weaknesses          = ($defaultWeak -join "; ")
}

# --- Fine-grained policies ---
Write-Log "Reading fine-grained password policies (PSOs)..." "Cyan"
$fgppCount = 0
try {
    $fgpps = @(Get-ADFineGrainedPasswordPolicy -Filter * -ErrorAction Stop)
    $fgppCount = $fgpps.Count
    foreach ($fgpp in $fgpps) {
        $weak = Get-PolicyWeaknesses -Policy $fgpp
        $results += [PSCustomObject]@{
            PolicyName          = $fgpp.Name
            PolicyType          = "FineGrained"
            AppliesTo           = (($fgpp.AppliesTo | ForEach-Object { $_ -replace '^CN=([^,]+),.*$', '$1' }) -join "; ")
            Precedence          = $fgpp.Precedence
            MinPasswordLength   = $fgpp.MinPasswordLength
            ComplexityEnabled   = $fgpp.ComplexityEnabled
            MaxPasswordAgeDays  = [int]$fgpp.MaxPasswordAge.TotalDays
            MinPasswordAgeDays  = [int]$fgpp.MinPasswordAge.TotalDays
            PasswordHistory     = $fgpp.PasswordHistoryCount
            LockoutThreshold    = $fgpp.LockoutThreshold
            LockoutDurationMins = [int]$fgpp.LockoutDuration.TotalMinutes
            ReversibleEncryption= $fgpp.ReversibleEncryptionEnabled
            Weaknesses          = ($weak -join "; ")
        }
    }
} catch {
    Write-Log "Could not read fine-grained policies (none defined, or insufficient permissions): $($_.Exception.Message)" "Yellow"
}

# --- Output ---
Write-Host ""
$results | Format-Table PolicyName, PolicyType, MinPasswordLength, ComplexityEnabled, MaxPasswordAgeDays, LockoutThreshold, Precedence -AutoSize | Out-String | Write-Host

$weakPolicies = @($results | Where-Object { $_.Weaknesses })
foreach ($policy in $weakPolicies) {
    Write-Log "WEAK: $($policy.PolicyName) - $($policy.Weaknesses)" "Red"
}
if ($weakPolicies.Count -eq 0) {
    Write-Log "No weak policy settings detected." "Green"
}

$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Log "Policies reported: $($results.Count) (default: 1, fine-grained: $fgppCount, weak: $($weakPolicies.Count))" "Cyan"
Write-Log "Report saved: $outputFile" "Green"
