# Export an event log to EVTX archive file

param(
    [Parameter(Mandatory=$false)]
    [string]$LogName = "System",
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
$logFile   = Join-Path $OutputDirectory "Export-EventLog_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

# Security log (and some others) require elevation to export
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($LogName -match '(?i)^security$' -and -not $isAdmin) {
    Write-Log "Exporting the Security log requires Administrator rights. Please relaunch the tool elevated." "Red"
    exit 1
}

# Sanitize log name for use in a filename (channels like "Microsoft-Windows-XYZ/Operational")
$safeName   = $LogName -replace '[/\\ ]', '-'
$exportFile = Join-Path $OutputDirectory "$($safeName)_$timestamp.evtx"

Write-Log "Exporting event log '$LogName' to EVTX..." "Cyan"

$output = wevtutil epl "$LogName" "$exportFile" 2>&1 | Out-String

if ($LASTEXITCODE -ne 0) {
    Write-Log "ERROR: wevtutil failed (exit code $LASTEXITCODE):" "Red"
    if ($output.Trim()) { Write-Log $output.Trim() "Red" }
    if ($output -match '(?i)access is denied' -and -not $isAdmin) {
        Write-Log "This log requires Administrator rights to export. Please relaunch the tool elevated." "Yellow"
    }
    exit 1
}

if (-not (Test-Path $exportFile)) {
    Write-Log "ERROR: wevtutil reported success but the export file was not created." "Red"
    exit 1
}

$sizeMB = [math]::Round((Get-Item $exportFile).Length / 1MB, 2)
Write-Log "Exported '$LogName' successfully ($sizeMB MB)." "Cyan"
Write-Log "Report saved: $exportFile" "Green"
