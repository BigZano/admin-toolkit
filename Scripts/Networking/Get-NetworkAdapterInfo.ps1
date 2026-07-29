# Get network adapter configuration for a local or remote computer

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
$outputFile = Join-Path $OutputDirectory "NetworkAdapters_${target}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "NetworkAdapters_${target}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module NetAdapter, NetTCPIP, DnsClient -ErrorAction Stop
} catch {
    Write-Log "Required networking modules not available: $($_.Exception.Message)" "Red"; exit 1
}

Write-Log "Retrieving network adapter info from: $target" "Cyan"

# For remote targets, create ONE CimSession and reuse it (passing a string to
# -CimSession would create and tear down a session on every call)
$cimSession = $null
if ($target -ne $env:COMPUTERNAME) {
    try {
        $cimSession = New-CimSession -ComputerName $target -ErrorAction Stop
    } catch {
        Write-Log "Cannot connect to $target : $($_.Exception.Message)" "Red"; exit 1
    }
}
$cimParams = if ($cimSession) { @{ CimSession = $cimSession } } else { @{} }

try {
    $adapters = Get-NetAdapter @cimParams -ErrorAction Stop

    $report = foreach ($adapter in ($adapters | Sort-Object Status, Name)) {
        $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex @cimParams -ErrorAction SilentlyContinue

        $dns = (Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex @cimParams -ErrorAction SilentlyContinue).ServerAddresses

        $ipv4 = ($ipConfig | Where-Object { $_.AddressFamily -eq "IPv4" } | Select-Object -ExpandProperty IPAddress) -join ", "
        $ipv6 = ($ipConfig | Where-Object { $_.AddressFamily -eq "IPv6" -and $_.IPAddress -notlike "fe80*" } | Select-Object -ExpandProperty IPAddress) -join ", "

        $color = switch ($adapter.Status) {
            "Up"         { "Green" }
            "Disabled"   { "DarkGray" }
            default      { "Yellow" }
        }

        Write-Host ""
        Write-Host ("  [{0}] {1}" -f $adapter.Status, $adapter.Name) -ForegroundColor $color
        Write-Host ("    MAC:  {0}" -f $adapter.MacAddress) -ForegroundColor Gray
        Write-Host ("    IPv4: {0}" -f $(if ($ipv4) { $ipv4 } else { "Not assigned" })) -ForegroundColor $(if ($ipv4) { "White" } else { "DarkGray" })
        if ($ipv6) { Write-Host ("    IPv6: {0}" -f $ipv6) -ForegroundColor DarkGray }
        if ($dns)  { Write-Host ("    DNS:  {0}" -f ($dns -join ", ")) -ForegroundColor DarkGray }
        Write-Host ("    Speed: {0}  |  Type: {1}" -f $adapter.LinkSpeed, $adapter.MediaType) -ForegroundColor DarkGray

        [PSCustomObject]@{
            Name        = $adapter.Name
            Status      = $adapter.Status
            MACAddress  = $adapter.MacAddress
            IPv4Address = $ipv4
            IPv6Address = $ipv6
            DNSServers  = ($dns -join "; ")
            LinkSpeed   = $adapter.LinkSpeed
            MediaType   = $adapter.MediaType
            InterfaceDescription = $adapter.InterfaceDescription
        }
    }

    if ($report) {
        $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
        Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
    } else {
        Write-Log "No adapters found; no CSV report generated." "Yellow"
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
} finally {
    if ($cimSession) { Remove-CimSession -CimSession $cimSession -ErrorAction SilentlyContinue }
}
