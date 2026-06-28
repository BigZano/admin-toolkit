# Show network adapters, virtual switches, MAC addresses, and IPs for Hyper-V VMs

param(
    [Parameter(Mandatory=$false)]
    [string]$VMName = "",
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ""
)

if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = Join-Path $env:USERPROFILE "Documents\AdminToolReports"
}
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "VMNetworkInfo_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "VMNetworkInfo_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$getParams = @{ ErrorAction = "Stop" }
if (-not [string]::IsNullOrEmpty($VMName))       { $getParams["Name"]         = $VMName }
if (-not [string]::IsNullOrEmpty($ComputerName)) { $getParams["ComputerName"] = $ComputerName }

try {
    $vms = Get-VM @getParams
} catch {
    Write-Log "Failed to retrieve VMs: $($_.Exception.Message)" "Red"; exit 1
}

Write-Log "Collecting network info for $($vms.Count) VM(s)..." "Cyan"
Write-Host ""

$report = foreach ($vm in $vms | Sort-Object Name) {
    Write-Host "  $($vm.Name)  [$($vm.State)]" -ForegroundColor $(if ($vm.State -eq "Running") { "Cyan" } else { "DarkGray" })

    $adapParams = @{ VMName = $vm.Name; ErrorAction = "SilentlyContinue" }
    if (-not [string]::IsNullOrEmpty($ComputerName)) { $adapParams["ComputerName"] = $ComputerName }
    $adapters = Get-VMNetworkAdapter @adapParams

    if (-not $adapters) {
        Write-Host "    (no network adapters)" -ForegroundColor DarkGray
        continue
    }

    foreach ($nic in $adapters) {
        $ips   = ($nic.IPAddresses | Where-Object { $_ }) -join ", "
        $mac   = $nic.MacAddress -replace '(.{2})(?!$)', '$1-'
        $color = if ($nic.Connected) { "White" } else { "DarkGray" }

        Write-Host ("    {0,-22} Switch: {1,-20} MAC: {2,-17} IP: {3}" -f `
            $nic.Name, ($nic.SwitchName -replace '^$', '(none)'), $mac, ($ips -replace '^$', '-')) -ForegroundColor $color

        [PSCustomObject]@{
            VMName      = $vm.Name
            VMState     = $vm.State
            Adapter     = $nic.Name
            Switch      = $nic.SwitchName
            MAC         = $mac
            Connected   = $nic.Connected
            IPAddresses = $ips
            VlanId      = $nic.VlanSetting.AccessVlanId
        }
    }
    Write-Host ""
}

$report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Log "Report saved to: $outputFile" "Green"
