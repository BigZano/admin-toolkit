# Show public IP address and ISP details for this connection

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

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile   = Join-Path $OutputDirectory "Get-PublicIP_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "Detecting public IP address..." "Cyan"

$publicIp = $null

# Primary source: ipify
try {
    $resp = Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 10
    $publicIp = $resp.ip
    Write-Log "Public IP (via api.ipify.org): $publicIp" "Green"
} catch {
    Write-Log "api.ipify.org failed: $($_.Exception.Message)" "Yellow"
}

# Fallback source: ifconfig.me
if ([string]::IsNullOrEmpty($publicIp)) {
    try {
        $publicIp = (Invoke-RestMethod -Uri 'https://ifconfig.me/ip' -TimeoutSec 10).ToString().Trim()
        Write-Log "Public IP (via ifconfig.me): $publicIp" "Green"
    } catch {
        Write-Log "ifconfig.me failed: $($_.Exception.Message)" "Yellow"
    }
}

if ([string]::IsNullOrEmpty($publicIp)) {
    Write-Log "ERROR: Could not determine public IP from any source. Check internet connectivity." "Red"
    exit 1
}

# Optional geo/ISP lookup
Write-Host ""
try {
    $geo = Invoke-RestMethod -Uri "http://ip-api.com/json/$publicIp" -TimeoutSec 10
    if ($geo.status -eq "success") {
        Write-Log "ISP details:" "Cyan"
        Write-Log ("  ISP     : {0}" -f $geo.isp)
        Write-Log ("  Org     : {0}" -f $geo.org)
        Write-Log ("  City    : {0}" -f $geo.city)
        Write-Log ("  Region  : {0}" -f $geo.regionName)
        Write-Log ("  Country : {0}" -f $geo.country)
    } else {
        Write-Log "Geo/ISP lookup returned no data for $publicIp" "Yellow"
    }
} catch {
    Write-Log "Geo/ISP lookup unavailable: $($_.Exception.Message)" "Yellow"
}

Write-Host ""
Write-Log "Public IP: $publicIp" "Green"
Write-Log "Log saved: $logFile" "Green"
