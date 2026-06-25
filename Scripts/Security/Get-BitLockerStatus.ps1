# Report BitLocker encryption status and key protectors for all drives

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = if ($IsWindows -or $env:OS -match "Windows") {
        Join-Path $env:USERPROFILE "Documents\AdminToolReports"
    } else { Join-Path $env:HOME "Documents/AdminToolReports" }
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$target    = if ([string]::IsNullOrEmpty($ComputerName)) { $env:COMPUTERNAME } else { $ComputerName }
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "BitLocker_${target}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "BitLocker_${target}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "Checking BitLocker status on: $target" "Cyan"

try {
    $volumes = if ($target -ne $env:COMPUTERNAME) {
        Invoke-Command -ComputerName $target -ScriptBlock { Get-BitLockerVolume -ErrorAction Stop } -ErrorAction Stop
    } else {
        Get-BitLockerVolume -ErrorAction Stop
    }

    Write-Host ""
    $report = foreach ($vol in ($volumes | Sort-Object MountPoint)) {
        $protectionStatus  = $vol.ProtectionStatus
        $encryptionStatus  = $vol.VolumeStatus
        $encryptionPct     = $vol.EncryptionPercentage
        $protectors        = ($vol.KeyProtector | ForEach-Object { $_.KeyProtectorType }) -join ", "

        $color = switch ($protectionStatus) {
            "On"  { "Green" }
            "Off" { if ($encryptionStatus -eq "FullyEncrypted") { "Yellow" } else { "Red" } }
            default { "Yellow" }
        }

        $flag = if ($protectionStatus -eq "Off" -and $encryptionStatus -ne "FullyEncrypted") { "  !! NOT ENCRYPTED" }
                elseif ($protectionStatus -eq "Off") { "  !! PROTECTION SUSPENDED" }
                else { "" }

        Write-Host ("  {0}  [{1}]  {2} ({3}%)  Protectors: {4}{5}" -f
            $vol.MountPoint, $protectionStatus, $encryptionStatus, $encryptionPct, $protectors, $flag) -ForegroundColor $color

        # Check for TPM protector
        $hasTpm      = $vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq "Tpm" }
        $hasRecovery = $vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }

        if (-not $hasRecovery -and $protectionStatus -eq "On") {
            Write-Host ("    WARNING: No Recovery Password protector found on {0}" -f $vol.MountPoint) -ForegroundColor Yellow
        }

        [PSCustomObject]@{
            Computer            = $target
            MountPoint          = $vol.MountPoint
            ProtectionStatus    = $protectionStatus
            EncryptionStatus    = $encryptionStatus
            EncryptionPct       = $encryptionPct
            KeyProtectors       = $protectors
            HasTPM              = [bool]$hasTpm
            HasRecoveryPassword = [bool]$hasRecovery
            EncryptionMethod    = $vol.EncryptionMethod
        }
    }

    $unprotected = @($report | Where-Object { $_.ProtectionStatus -ne "On" -or $_.EncryptionStatus -ne "FullyEncrypted" })
    Write-Log "Volumes: $($report.Count)  |  Unprotected/incomplete: $($unprotected.Count)" `
        "$(if ($unprotected.Count -gt 0) { 'Red' } else { 'Green' })"

    $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"
    Write-Log "Ensure BitLocker Drive Encryption is available and you are running as Administrator." "Yellow"
    exit 1
}
