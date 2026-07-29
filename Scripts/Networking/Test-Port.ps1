# Test TCP port connectivity to a host with optional timeout

param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,
    [Parameter(Mandatory=$true)]
    [string]$Port,
    [Parameter(Mandatory=$false)]
    [string]$TimeoutSeconds = "3",
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
$outputFile = Join-Path $OutputDirectory "PortTest_${safeName}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "PortTest_${safeName}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$timeoutSec = 0
if (-not [int]::TryParse($TimeoutSeconds, [ref]$timeoutSec) -or $timeoutSec -lt 1) {
    Write-Log "Invalid TimeoutSeconds value: '$TimeoutSeconds' (expected an integer >= 1)" "Red"; exit 1
}
$ports = @()
foreach ($p in ($Port -split ',')) {
    $n = 0
    if (-not [int]::TryParse($p.Trim(), [ref]$n) -or $n -lt 1 -or $n -gt 65535) {
        Write-Log "Invalid port value: '$($p.Trim())' (expected 1-65535)" "Red"; exit 1
    }
    $ports += $n
}
$timeout = $timeoutSec * 1000

# Fail fast on unresolvable hosts (otherwise every port reports a misleading error)
try {
    [System.Net.Dns]::GetHostAddresses($ComputerName) | Out-Null
} catch {
    Write-Log "Cannot resolve host: $ComputerName" "Red"; exit 1
}

Write-Log "Testing $($ports.Count) port(s) on: $ComputerName  (timeout: ${TimeoutSeconds}s)" "Cyan"
Write-Host ""

# Well-known port names
$portNames = @{
    21 = "FTP"; 22 = "SSH"; 23 = "Telnet"; 25 = "SMTP"; 53 = "DNS"
    80 = "HTTP"; 88 = "Kerberos"; 110 = "POP3"; 135 = "RPC"; 139 = "NetBIOS"
    143 = "IMAP"; 389 = "LDAP"; 443 = "HTTPS"; 445 = "SMB"; 464 = "Kerberos PW"
    636 = "LDAPS"; 993 = "IMAPS"; 995 = "POP3S"; 1433 = "MSSQL"; 1521 = "Oracle"
    3268 = "GC LDAP"; 3269 = "GC LDAPS"; 3389 = "RDP"; 5985 = "WinRM HTTP"
    5986 = "WinRM HTTPS"; 8080 = "HTTP Alt"; 8443 = "HTTPS Alt"
}

$results = foreach ($p in $ports) {
    $name = if ($portNames.ContainsKey($p)) { $portNames[$p] } else { "Unknown" }
    $tcp  = New-Object System.Net.Sockets.TcpClient
    try {
        $connect = $tcp.BeginConnect($ComputerName, $p, $null, $null)
        $success = $connect.AsyncWaitHandle.WaitOne($timeout, $false)
        if ($success -and $tcp.Connected) {
            $tcp.EndConnect($connect)
            Write-Host ("  Port {0,5}  {1,-15}  OPEN" -f $p, $name) -ForegroundColor Green
            [PSCustomObject]@{ Host = $ComputerName; Port = $p; Name = $name; Status = "Open" }
        } else {
            Write-Host ("  Port {0,5}  {1,-15}  CLOSED / FILTERED" -f $p, $name) -ForegroundColor Red
            [PSCustomObject]@{ Host = $ComputerName; Port = $p; Name = $name; Status = "Closed/Filtered" }
        }
    } catch {
        Write-Host ("  Port {0,5}  {1,-15}  ERROR: {2}" -f $p, $name, $_.Exception.Message) -ForegroundColor Yellow
        [PSCustomObject]@{ Host = $ComputerName; Port = $p; Name = $name; Status = "Error" }
    } finally {
        $tcp.Close()
    }
}

Write-Host ""
$open   = @($results | Where-Object { $_.Status -eq "Open" })
$closed = @($results | Where-Object { $_.Status -ne "Open" })
Write-Log "Open: $($open.Count)  |  Closed/Filtered: $($closed.Count)" "$(if ($open.Count -eq $ports.Count) { 'Green' } elseif ($open.Count -eq 0) { 'Red' } else { 'Yellow' })"

$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Log "Report saved to: $outputFile" "Green"
