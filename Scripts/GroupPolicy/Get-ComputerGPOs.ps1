# Get the Group Policy Objects applied to a specific computer (equivalent to gpresult)

param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,
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

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$htmlReport = Join-Path $OutputDirectory "ComputerGPOs_${ComputerName}_$timestamp.html"
$csvReport  = Join-Path $OutputDirectory "ComputerGPOs_${ComputerName}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "ComputerGPOs_${ComputerName}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

try {
    Import-Module GroupPolicy -ErrorAction Stop
} catch {
    Write-Log "GroupPolicy module not found. Install RSAT: Group Policy Management Tools." "Red"
    exit 1
}

Write-Log "Generating RSoP for computer: $ComputerName" "Cyan"
Write-Log "This may take a moment..." "Yellow"

$xmlPath = Join-Path $OutputDirectory "ComputerGPOs_${ComputerName}_$timestamp.tmp.xml"
try {
    # Generate HTML RSoP report for the computer scope
    Get-GPResultantSetOfPolicy -Computer $ComputerName -ReportType HTML -Path $htmlReport -ErrorAction Stop
    Write-Log "HTML RSoP report saved to: $htmlReport" "Green"

    # Parse applied GPOs from XML for console display and CSV
    Get-GPResultantSetOfPolicy -Computer $ComputerName -ReportType XML -Path $xmlPath -ErrorAction Stop

    [xml]$rsop = Get-Content $xmlPath

    # Guard against an empty result set (piping $null would produce one blank row);
    # XML booleans are the strings "true"/"false" - parse to real booleans.
    $gpoNodes = @($rsop.Rsop.ComputerResults.GPO | Where-Object { $_ })
    $appliedGPOs = $gpoNodes | ForEach-Object {
        [PSCustomObject]@{
            Name         = $_.Name
            Enabled      = ($_.Enabled -eq 'true')
            IsValid      = ($_.IsValid -eq 'true')
            Version      = $_.VersionDirectory
            AccessDenied = ($_.AccessDenied -eq 'true')
        }
    } | Sort-Object Name

    $applied  = @($appliedGPOs | Where-Object { $_.Enabled -eq $true -and $_.IsValid -eq $true })
    $denied   = @($appliedGPOs | Where-Object { $_.AccessDenied -eq $true })
    $disabled = @($appliedGPOs | Where-Object { $_.Enabled -eq $false })

    Write-Log "Applied: $($applied.Count)  |  Access denied: $($denied.Count)  |  Disabled: $($disabled.Count)" "Cyan"
    Write-Host ""

    $appliedGPOs | ForEach-Object {
        $color = if ($_.AccessDenied) { "Red" } elseif (-not $_.Enabled) { "DarkGray" } else { "White" }
        $flag  = if ($_.AccessDenied) { " [ACCESS DENIED]" } elseif (-not $_.Enabled) { " [DISABLED]" } else { "" }
        Write-Host ("  {0}{1}" -f $_.Name, $flag) -ForegroundColor $color
    }

    if ($appliedGPOs) {
        $appliedGPOs | Export-Csv -Path $csvReport -NoTypeInformation -Encoding UTF8
        Write-Host ""
        Write-Log "CSV report saved to: $csvReport" "Green"
    } else {
        Write-Log "No GPO results returned for $ComputerName - CSV not written." "Yellow"
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"
    Write-Log "Ensure the computer is reachable, you have local admin rights on it, and this session is elevated." "Yellow"
    exit 1
} finally {
    if (Test-Path $xmlPath) { Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue }
}
