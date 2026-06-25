# List files currently open or locked on a local or remote server

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
$outputFile = Join-Path $OutputDirectory "OpenFiles_${target}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "OpenFiles_${target}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "Retrieving open files on: $target" "Cyan"

try {
    $openFiles = Get-SmbOpenFile -ErrorAction Stop |
        Where-Object { -not [string]::IsNullOrEmpty($_.Path) } |
        Sort-Object Path |
        ForEach-Object {
            [PSCustomObject]@{
                FileId      = $_.FileId
                SessionId   = $_.SessionId
                Path        = $_.Path
                ClientComputerName = $_.ClientComputerName
                ClientUserName     = $_.ClientUserName
                Locks       = $_.Locks
            }
        }

    Write-Log "Open files: $($openFiles.Count)" "$(if ($openFiles.Count -gt 0) { 'Yellow' } else { 'Green' })"
    Write-Host ""

    if ($openFiles.Count -gt 0) {
        # Group by user
        $byUser = $openFiles | Group-Object ClientUserName | Sort-Object Count -Descending
        Write-Host "  Open files by user:" -ForegroundColor DarkGray
        $byUser | ForEach-Object {
            Write-Host ("  {0,-35} {1} file(s)" -f $_.Name, $_.Count) -ForegroundColor Cyan
        }

        Write-Host ""
        $openFiles | ForEach-Object {
            $lockColor = if ($_.Locks -gt 0) { "Yellow" } else { "White" }
            $lockStr   = if ($_.Locks -gt 0) { "  [LOCKED]" } else { "" }
            Write-Host ("  {0,-30} {1}{2}" -f $_.ClientUserName, $_.Path, $lockStr) -ForegroundColor $lockColor
        }

        $openFiles | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
        Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
    } else {
        Write-Log "No open SMB files found on $target." "Green"
    }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"
    Write-Log "Ensure you have admin rights and the Server service is running." "Yellow"
    exit 1
}
