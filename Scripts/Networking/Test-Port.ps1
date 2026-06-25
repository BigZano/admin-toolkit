# Test TCP port connectivity to a host with optional timeout

param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,
    [Parameter(Mandatory=$true)]
    [string]$Port,
    [Parameter(Mandatory=$false)]
    [string]$TimeoutSeconds = "3"
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "$(Get-Date -Format 'HH:mm:ss') $Message" -ForegroundColor $Color
}

$ports   = $Port -split ',' | ForEach-Object { [int]$_.Trim() }
$timeout = [int]$TimeoutSeconds * 1000

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
