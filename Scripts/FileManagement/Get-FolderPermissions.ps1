# Audit NTFS permissions on a folder, with optional recursive traversal

param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [Parameter(Mandatory=$false)]
    [string]$Recurse = "false",
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
$outputFile = Join-Path $OutputDirectory "FolderPermissions_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "FolderPermissions_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

if (-not (Test-Path $Path)) {
    Write-Log "Path not found: $Path" "Red"; exit 1
}

$isRecurse = $Recurse -eq "true" -or $Recurse -eq "1"
Write-Log "Auditing permissions: $Path$(if ($isRecurse) { ' (recursive)' })" "Cyan"

try {
    $folders = if ($isRecurse) {
        @(Get-Item $Path) + @(Get-ChildItem -Path $Path -Directory -Recurse -ErrorAction SilentlyContinue)
    } else {
        @(Get-Item $Path)
    }

    Write-Log "Processing $($folders.Count) folder(s)..." "Cyan"

    $report = foreach ($folder in $folders) {
        $acl = Get-Acl -Path $folder.FullName -ErrorAction SilentlyContinue
        if (-not $acl) { continue }

        $inherited = $acl.AreAccessRulesProtected -eq $false

        foreach ($ace in $acl.Access) {
            [PSCustomObject]@{
                FolderPath        = $folder.FullName
                IdentityReference = $ace.IdentityReference
                AccessRights      = $ace.FileSystemRights
                AccessType        = $ace.AccessControlType
                IsInherited       = $ace.IsInherited
                InheritanceFlags  = $ace.InheritanceFlags
                PropagationFlags  = $ace.PropagationFlags
                InheritanceBreak  = -not $inherited
            }
        }
    }

    # Flag explicit (non-inherited) permissions
    $explicit = @($report | Where-Object { -not $_.IsInherited })
    Write-Log "Total ACEs: $($report.Count)  |  Explicit (non-inherited): $($explicit.Count)" "$(if ($explicit.Count -gt 0) { 'Yellow' } else { 'Green' })"

    if ($explicit.Count -gt 0) {
        Write-Host ""
        Write-Host "  Explicit permissions (review these):" -ForegroundColor Yellow
        $explicit | ForEach-Object {
            Write-Host ("  {0}" -f $_.FolderPath) -ForegroundColor DarkGray
            Write-Host ("    {0,-35} {1,-30} [{2}]" -f $_.IdentityReference, $_.AccessRights, $_.AccessType) -ForegroundColor Yellow
        }
    }

    $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
