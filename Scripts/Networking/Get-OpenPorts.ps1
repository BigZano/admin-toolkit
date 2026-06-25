# Scan a host for open TCP ports; use 'common' for well-known ports or specify a range

param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,
    [Parameter(Mandatory=$false)]
    [string]$PortRange = "common",
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
$safeName   = $ComputerName -replace '[\\/:*?"<>|]', '_'
$outputFile = Join-Path $OutputDirectory "OpenPorts_${safeName}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "OpenPorts_${safeName}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$portNames = @{
    21 = "FTP"; 22 = "SSH"; 23 = "Telnet"; 25 = "SMTP"; 53 = "DNS"; 67 = "DHCP"
    80 = "HTTP"; 88 = "Kerberos"; 110 = "POP3"; 111 = "RPC"; 135 = "RPC Endpoint"
    139 = "NetBIOS"; 143 = "IMAP"; 389 = "LDAP"; 443 = "HTTPS"; 445 = "SMB"
    464 = "Kerberos PW"; 514 = "Syslog"; 636 = "LDAPS"; 993 = "IMAPS"; 995 = "POP3S"
    1433 = "MSSQL"; 1521 = "Oracle"; 2049 = "NFS"; 3268 = "GC LDAP"; 3269 = "GC LDAPS"
    3306 = "MySQL"; 3389 = "RDP"; 5985 = "WinRM HTTP"; 5986 = "WinRM HTTPS"
    6379 = "Redis"; 8080 = "HTTP Alt"; 8443 = "HTTPS Alt"; 27017 = "MongoDB"
}

$commonPorts = $portNames.Keys | Sort-Object

# Resolve port list
$ports = if ($PortRange -eq "common") {
    $commonPorts
} elseif ($PortRange -match '^\d+-\d+$') {
    $parts = $PortRange -split '-'
    [int]$parts[0]..[int]$parts[1]
} else {
    $PortRange -split ',' | ForEach-Object { [int]$_.Trim() }
}

Write-Log "Scanning $($ports.Count) ports on: $ComputerName" "Cyan"
Write-Host ""

$openPorts = [System.Collections.Generic.List[object]]::new()

foreach ($port in $ports) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $connect = $tcp.BeginConnect($ComputerName, $port, $null, $null)
        $open    = $connect.AsyncWaitHandle.WaitOne(500, $false)

        if ($open -and $tcp.Connected) {
            $tcp.EndConnect($connect)
            $name = if ($portNames.ContainsKey([int]$port)) { $portNames[[int]$port] } else { "Unknown" }
            Write-Host ("  {0,5}  {1,-20}  OPEN" -f $port, $name) -ForegroundColor Green
            $openPorts.Add([PSCustomObject]@{
                Host    = $ComputerName
                Port    = $port
                Service = $name
                Status  = "Open"
            })
        }
    } catch { } finally { $tcp.Close() }
}

Write-Host ""
Write-Log "Open ports found: $($openPorts.Count) of $($ports.Count) scanned" "$(if ($openPorts.Count -gt 0) { 'Yellow' } else { 'Green' })"

if ($openPorts.Count -gt 0) {
    $openPorts | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Log "Report saved to: $outputFile" "Green"
}
