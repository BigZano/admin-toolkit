# Check Microsoft Defender antivirus health and signature status

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
$outputFile = Join-Path $OutputDirectory "DefenderStatus_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "DefenderStatus_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "Checking Microsoft Defender status on $env:COMPUTERNAME..." "Cyan"

try {
    $status = Get-MpComputerStatus -ErrorAction Stop
} catch {
    Write-Log "Could not query Microsoft Defender (Get-MpComputerStatus failed)." "Red"
    Write-Log "Defender may not be installed (Server without the feature) or a third-party AV may be active." "Red"
    Write-Log "Detail: $($_.Exception.Message)" "Red"
    exit 1
}

# --- Core health ---
Write-Host ""
Write-Log "=== Defender Health ===" "Cyan"

$rtpColor = if ($status.RealTimeProtectionEnabled) { "Green" } else { "Red" }
Write-Log "Real-Time Protection:   $($status.RealTimeProtectionEnabled)" $rtpColor
Write-Log "Antivirus Enabled:      $($status.AntivirusEnabled)" $(if ($status.AntivirusEnabled) { "Green" } else { "Red" })
Write-Log "Antispyware Enabled:    $($status.AntispywareEnabled)" $(if ($status.AntispywareEnabled) { "Green" } else { "Red" })
Write-Log "Behavior Monitoring:    $($status.BehaviorMonitorEnabled)" $(if ($status.BehaviorMonitorEnabled) { "Green" } else { "Yellow" })
Write-Log "IOAV Protection:        $($status.IoavProtectionEnabled)"
Write-Log "NIS (Network) Enabled:  $($status.NISEnabled)"
Write-Log "Tamper Protection:      $($status.IsTamperProtected)"
Write-Log "AM Engine Version:      $($status.AMEngineVersion)"
Write-Log "AM Product Version:     $($status.AMProductVersion)"

# --- Signatures ---
Write-Host ""
Write-Log "=== Signatures ===" "Cyan"
$sigAgeDays = $null
if ($status.AntivirusSignatureLastUpdated) {
    $sigAgeDays = [int]((Get-Date) - $status.AntivirusSignatureLastUpdated).TotalDays
}
$sigColor = if ($null -ne $sigAgeDays -and $sigAgeDays -gt 3) { "Yellow" } else { "Green" }
Write-Log "AV Signature Version:   $($status.AntivirusSignatureVersion)"
Write-Log "AV Signature Updated:   $($status.AntivirusSignatureLastUpdated) (age: $(if ($null -ne $sigAgeDays) { "$sigAgeDays days" } else { 'unknown' }))" $sigColor
if ($null -ne $sigAgeDays -and $sigAgeDays -gt 3) {
    Write-Log "WARNING: Signatures are more than 3 days old." "Yellow"
}
Write-Log "Last Quick Scan:        $($status.QuickScanEndTime)"
Write-Log "Last Full Scan:         $($status.FullScanEndTime)"

# --- Preferences / exclusions ---
$exclPaths = ""; $exclExts = ""; $exclProcs = ""
$exclusionNote = ""
try {
    $pref = Get-MpPreference -ErrorAction Stop
    Write-Host ""
    Write-Log "=== Exclusions ===" "Cyan"
    $exclPaths = ($pref.ExclusionPath      | Where-Object { $_ }) -join "; "
    $exclExts  = ($pref.ExclusionExtension | Where-Object { $_ }) -join "; "
    $exclProcs = ($pref.ExclusionProcess   | Where-Object { $_ }) -join "; "

    if ($exclPaths -or $exclExts -or $exclProcs) {
        if ($exclPaths) { Write-Log "Excluded Paths:      $exclPaths" "Yellow" }
        if ($exclExts)  { Write-Log "Excluded Extensions: $exclExts" "Yellow" }
        if ($exclProcs) { Write-Log "Excluded Processes:  $exclProcs" "Yellow" }
    } else {
        Write-Log "No exclusions configured (or exclusion list hidden without elevation)." "Green"
        $exclusionNote = "None visible - newer builds require elevation to view exclusions"
    }
} catch {
    $exclusionNote = "Blocked: $($_.Exception.Message)"
    Write-Log "Could not read Defender preferences/exclusions (elevation may be required on newer builds): $($_.Exception.Message)" "Yellow"
}

# --- Export ---
$row = [PSCustomObject]@{
    ComputerName               = $env:COMPUTERNAME
    RealTimeProtectionEnabled  = $status.RealTimeProtectionEnabled
    AntivirusEnabled           = $status.AntivirusEnabled
    AntispywareEnabled         = $status.AntispywareEnabled
    BehaviorMonitorEnabled     = $status.BehaviorMonitorEnabled
    IoavProtectionEnabled      = $status.IoavProtectionEnabled
    NISEnabled                 = $status.NISEnabled
    IsTamperProtected          = $status.IsTamperProtected
    AMEngineVersion            = $status.AMEngineVersion
    AMProductVersion           = $status.AMProductVersion
    AntivirusSignatureVersion  = $status.AntivirusSignatureVersion
    AntivirusSignatureUpdated  = $status.AntivirusSignatureLastUpdated
    SignatureAgeDays           = $sigAgeDays
    LastQuickScan              = $status.QuickScanEndTime
    LastFullScan               = $status.FullScanEndTime
    ExcludedPaths              = $exclPaths
    ExcludedExtensions         = $exclExts
    ExcludedProcesses          = $exclProcs
    ExclusionNote              = $exclusionNote
}
@($row) | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host ""
if (-not $status.RealTimeProtectionEnabled) {
    Write-Log "ALERT: Real-time protection is DISABLED." "Red"
}
Write-Log "Report saved: $outputFile" "Green"
