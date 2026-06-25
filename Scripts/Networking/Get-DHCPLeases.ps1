# Get active DHCP leases from a DHCP server with optional scope filter

param(
    [Parameter(Mandatory=$true)]
    [string]$DHCPServer,
    [Parameter(Mandatory=$false)]
    [string]$ScopeId = "",
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
$safeName   = $DHCPServer -replace '[\\/:*?"<>|]', '_'
$outputFile = Join-Path $OutputDirectory "DHCPLeases_${safeName}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "DHCPLeases_${safeName}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "Connecting to DHCP server: $DHCPServer" "Cyan"

try {
    # Get scopes
    $scopes = Get-DhcpServerv4Scope -ComputerName $DHCPServer -ErrorAction Stop
    Write-Log "Found $($scopes.Count) scope(s)." "Cyan"

    $targetScopes = if (-not [string]::IsNullOrEmpty($ScopeId)) {
        $scopes | Where-Object { $_.ScopeId -eq $ScopeId }
    } else { $scopes }

    if (-not $targetScopes) {
        Write-Log "Scope '$ScopeId' not found on $DHCPServer." "Red"; exit 1
    }

    $allLeases = foreach ($scope in $targetScopes) {
        Write-Log "  Scope: $($scope.ScopeId)  [$($scope.Name)]  $($scope.StartRange) - $($scope.EndRange)" "Gray"

        $leases = Get-DhcpServerv4Lease -ComputerName $DHCPServer -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue

        foreach ($lease in $leases) {
            [PSCustomObject]@{
                ScopeId     = $scope.ScopeId
                ScopeName   = $scope.Name
                IPAddress   = $lease.IPAddress
                HostName    = $lease.HostName
                MACAddress  = $lease.ClientId
                LeaseExpiry = if ($lease.LeaseExpiryTime) { $lease.LeaseExpiryTime.ToString("yyyy-MM-dd HH:mm") } else { "Reservation" }
                AddressState = $lease.AddressState
                Description = $lease.Description
            }
        }
    }

    $active      = @($allLeases | Where-Object { $_.AddressState -eq "Active" })
    $reserved    = @($allLeases | Where-Object { $_.AddressState -like "*Reservation*" })
    $expired     = @($allLeases | Where-Object { $_.AddressState -eq "Expired" })

    Write-Log "Total leases: $($allLeases.Count)  |  Active: $($active.Count)  |  Reservations: $($reserved.Count)  |  Expired: $($expired.Count)" "Cyan"
    Write-Host ""

    $allLeases | Sort-Object ScopeId, IPAddress | ForEach-Object {
        $color = switch ($_.AddressState) {
            "Active"           { "Green" }
            "Expired"          { "DarkGray" }
            default            { "Yellow" }
        }
        Write-Host ("  {0,-16} {1,-35} {2,-20} [{3}]" -f $_.IPAddress, $_.HostName, $_.MACAddress, $_.AddressState) -ForegroundColor $color
    }

    $allLeases | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"
    Write-Log "Ensure DHCP Server Tools (RSAT) are installed and you have admin rights on $DHCPServer." "Yellow"
    exit 1
}
