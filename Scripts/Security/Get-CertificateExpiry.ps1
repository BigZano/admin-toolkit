# Find machine certificates expiring within X days

param(
    [Parameter(Mandatory=$false)]
    [string]$DaysUntilExpiry = "60",
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

$days       = [int]$DaysUntilExpiry
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDirectory "CertificateExpiry_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "CertificateExpiry_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

if (-not (Test-Path "Cert:\LocalMachine")) {
    Write-Log "Certificate provider (Cert:\LocalMachine) not available on this platform." "Red"
    exit 1
}

$cutoff = (Get-Date).AddDays($days)
Write-Log "Scanning machine certificate stores for certs expiring before $($cutoff.ToString('yyyy-MM-dd')) ($days days)..." "Cyan"

$stores    = @("Cert:\LocalMachine\My", "Cert:\LocalMachine\WebHosting")
$results   = @()
$skipCount = 0
$scanned   = 0

foreach ($store in $stores) {
    if (-not (Test-Path $store)) {
        Write-Log "Store not present, skipping: $store" "Yellow"
        continue
    }

    $certs = @()
    try {
        $certs = Get-ChildItem -Path $store -ErrorAction Stop | Where-Object { -not $_.PSIsContainer }
    } catch {
        Write-Log "Could not read store $store : $($_.Exception.Message)" "Yellow"
        continue
    }

    foreach ($cert in $certs) {
        $scanned++
        try {
            if ($cert.NotAfter -le $cutoff) {
                $daysLeft = [int](($cert.NotAfter) - (Get-Date)).TotalDays
                $results += [PSCustomObject]@{
                    Store         = $store
                    Subject       = $cert.Subject
                    Issuer        = $cert.Issuer
                    NotAfter      = $cert.NotAfter.ToString("yyyy-MM-dd HH:mm")
                    DaysLeft      = $daysLeft
                    Expired       = ($daysLeft -lt 0)
                    Thumbprint    = $cert.Thumbprint
                    HasPrivateKey = $cert.HasPrivateKey
                }
            }
        } catch {
            $skipCount++
            Write-Log "Skipped a certificate in $store : $($_.Exception.Message)" "Yellow"
        }
    }
}

$results = @($results | Sort-Object DaysLeft)

Write-Host ""
if ($results.Count -gt 0) {
    foreach ($item in $results) {
        $color = if ($item.Expired) { "Red" } else { "Yellow" }
        $state = if ($item.Expired) { "EXPIRED" } else { "expires in $($item.DaysLeft) days" }
        Write-Log ("{0} - {1} [{2}] ({3})" -f $item.Subject, $state, $item.NotAfter, $item.Store) $color
    }
    Write-Host ""
    $results | Format-Table Subject, NotAfter, DaysLeft, HasPrivateKey, Thumbprint -AutoSize | Out-String | Write-Host
    $expiredCount = @($results | Where-Object { $_.Expired }).Count
    Write-Log "Certificates expiring within $days days: $($results.Count) (already expired: $expiredCount) - scanned $scanned certs" "Yellow"
} else {
    Write-Log "No certificates expiring within $days days (scanned $scanned certs)." "Green"
}
if ($skipCount -gt 0) {
    Write-Log "Certificates skipped due to read errors: $skipCount" "Yellow"
}
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Log "Report saved: $outputFile" "Green"
