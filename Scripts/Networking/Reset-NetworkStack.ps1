# Flush DNS and reset network stack (fixes common connectivity issues)

param(
    [Parameter(Mandatory=$false)]
    [string]$RenewDhcp = "false",
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
$logFile   = Join-Path $OutputDirectory "Reset-NetworkStack_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "This script must be run as Administrator. Please relaunch the tool elevated." "Red"
    exit 1
}

$renewFlag = $RenewDhcp -match '^(?i)(true|yes|1)$'

Write-Log "Resetting network stack..." "Cyan"
Write-Host ""

# Step 1: Flush DNS cache
try {
    Clear-DnsClientCache -ErrorAction Stop
    Write-Log "[1/3] DNS client cache flushed." "Green"
} catch {
    Write-Log "[1/3] Failed to flush DNS cache: $($_.Exception.Message)" "Yellow"
}

# Step 2: Winsock reset
try {
    $out = netsh winsock reset 2>&1 | Out-String
    Write-Log "[2/3] netsh winsock reset:" "Green"
    Write-Log ($out.Trim())
} catch {
    Write-Log "[2/3] netsh winsock reset failed: $($_.Exception.Message)" "Yellow"
}

# Step 3: TCP/IP stack reset
try {
    $out = netsh int ip reset 2>&1 | Out-String
    Write-Log "[3/3] netsh int ip reset:" "Green"
    Write-Log ($out.Trim())
} catch {
    Write-Log "[3/3] netsh int ip reset failed: $($_.Exception.Message)" "Yellow"
}

# Optional: DHCP release/renew
if ($renewFlag) {
    Write-Host ""
    Write-Log "WARNING: Releasing and renewing DHCP lease - network connectivity will drop briefly." "Yellow"
    try {
        $out = ipconfig /release 2>&1 | Out-String
        Write-Log "ipconfig /release completed."
        $out = ipconfig /renew 2>&1 | Out-String
        Write-Log "ipconfig /renew completed." "Green"
        Write-Log ($out.Trim())
    } catch {
        Write-Log "DHCP release/renew failed: $($_.Exception.Message)" "Yellow"
    }
} else {
    Write-Log "DHCP renew skipped (RenewDhcp=false)."
}

Write-Host ""
Write-Log "NOTE: The winsock and TCP/IP resets require a reboot to fully apply." "Yellow"
Write-Log "Network stack reset complete. Log saved: $logFile" "Green"
