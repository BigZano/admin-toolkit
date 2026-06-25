# Query DNS records for a host or domain; supports A, AAAA, MX, NS, CNAME, TXT, PTR

param(
    [Parameter(Mandatory=$true)]
    [string]$Target,
    [Parameter(Mandatory=$false)]
    [string]$RecordType = "A",
    [Parameter(Mandatory=$false)]
    [string]$DNSServer = ""
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "$(Get-Date -Format 'HH:mm:ss') $Message" -ForegroundColor $Color
}

$type = $RecordType.ToUpper()
$validTypes = @("A", "AAAA", "MX", "NS", "CNAME", "TXT", "PTR", "SOA", "SRV", "ALL")

if ($type -notin $validTypes) {
    Write-Log "Invalid record type '$type'. Valid: $($validTypes -join ', ')" "Red"; exit 1
}

$dnsParams = @{ Name = $Target; ErrorAction = "Stop" }
if (-not [string]::IsNullOrEmpty($DNSServer)) { $dnsParams["Server"] = $DNSServer }
if ($type -ne "ALL") { $dnsParams["Type"] = $type }

$serverStr = if ($DNSServer) { " via $DNSServer" } else { " (default resolver)" }
Write-Log "DNS lookup: $Target  type=$type$serverStr" "Cyan"
Write-Host ""

try {
    $results = Resolve-DnsName @dnsParams | Sort-Object Type, Name

    if (-not $results) {
        Write-Log "No records found." "Yellow"; exit 0
    }

    $results | ForEach-Object {
        $line = switch ($_.Type) {
            "A"     { "  {0,-40} A      {1}" -f $_.Name, $_.IPAddress }
            "AAAA"  { "  {0,-40} AAAA   {1}" -f $_.Name, $_.IPAddress }
            "MX"    { "  {0,-40} MX     {1}  (priority: {2})" -f $_.Name, $_.NameExchange, $_.Preference }
            "NS"    { "  {0,-40} NS     {1}" -f $_.Name, $_.NameHost }
            "CNAME" { "  {0,-40} CNAME  -> {1}" -f $_.Name, $_.NameHost }
            "TXT"   { "  {0,-40} TXT    {1}" -f $_.Name, ($_.Strings -join " ") }
            "PTR"   { "  {0,-40} PTR    {1}" -f $_.Name, $_.NameHost }
            "SOA"   { "  {0,-40} SOA    Primary: {1}  Serial: {2}" -f $_.Name, $_.PrimaryServer, $_.SerialNumber }
            default { "  {0,-40} {1,-6} {2}" -f $_.Name, $_.Type, $_.QueryType }
        }
        Write-Host $line -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Log "$($results.Count) record(s) returned." "Green"
} catch [System.ComponentModel.Win32Exception] {
    Write-Log "DNS query failed: $($_.Exception.Message)" "Red"
    Write-Log "The name '$Target' does not exist or could not be resolved." "Yellow"
    exit 1
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
