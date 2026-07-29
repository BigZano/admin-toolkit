# Enable or disable Remote Desktop with firewall rules

param(
    [Parameter(Mandatory=$false)]
    [string]$Enabled = "true",
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
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
$logFile   = Join-Path $OutputDirectory "Enable-RemoteDesktop_$timestamp.log"

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

$enableFlag = $Enabled -match '^(?i)(true|yes|1)$'
$action     = if ($enableFlag) { "Enable" } else { "Disable" }
$regPath    = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$target     = if ([string]::IsNullOrEmpty($ComputerName)) { $env:COMPUTERNAME } else { $ComputerName }

Write-Log "$action Remote Desktop on: $target" "Cyan"

$scriptBlock = {
    param([bool]$Enable, [string]$RegPath)
    $before = (Get-ItemProperty -Path $RegPath -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections
    $newValue = if ($Enable) { 0 } else { 1 }
    Set-ItemProperty -Path $RegPath -Name fDenyTSConnections -Value $newValue -Confirm:$false
    if ($Enable) {
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -Confirm:$false
    } else {
        Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -Confirm:$false
    }
    $after = (Get-ItemProperty -Path $RegPath -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections
    [PSCustomObject]@{ Before = $before; After = $after }
}

try {
    if ([string]::IsNullOrEmpty($ComputerName)) {
        $state = & $scriptBlock $enableFlag $regPath
    } else {
        $state = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock -ArgumentList $enableFlag, $regPath -ErrorAction Stop
    }
} catch {
    Write-Log "ERROR: Failed to configure Remote Desktop on ${target}: $($_.Exception.Message)" "Red"
    if (-not [string]::IsNullOrEmpty($ComputerName)) {
        Write-Log "Remote configuration requires WinRM (Enable-PSRemoting) on the target and admin rights there." "Yellow"
    }
    exit 1
}

$stateText = @{ 0 = "RDP ENABLED"; 1 = "RDP DISABLED" }
$beforeText = if ($null -ne $state.Before -and $stateText.ContainsKey([int]$state.Before)) { $stateText[[int]$state.Before] } else { "unknown" }
$afterText  = if ($null -ne $state.After  -and $stateText.ContainsKey([int]$state.After))  { $stateText[[int]$state.After] }  else { "unknown" }

Write-Host ""
Write-Log "Before: $beforeText"
Write-Log "After : $afterText" $(if ($enableFlag) { "Green" } else { "Yellow" })
Write-Log "Firewall group 'Remote Desktop' has been $(if ($enableFlag) { 'enabled' } else { 'disabled' })." "Cyan"
Write-Log "Done. Log saved: $logFile" "Green"
