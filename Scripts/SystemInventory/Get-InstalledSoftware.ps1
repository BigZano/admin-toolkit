# Report all installed software from the registry on a local or remote computer

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "",
    [Parameter(Mandatory=$false)]
    [string]$FilterName = "",
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
$outputFile = Join-Path $OutputDirectory "InstalledSoftware_${target}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "InstalledSoftware_${target}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

$collectScript = {
    $hives = @(
        @{ Root = [Microsoft.Win32.Registry]::LocalMachine; Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall";             Arch = "64-bit" }
        @{ Root = [Microsoft.Win32.Registry]::LocalMachine; Path = "SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"; Arch = "32-bit" }
        @{ Root = [Microsoft.Win32.Registry]::CurrentUser;  Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall";             Arch = "Per-user" }
    )
    foreach ($h in $hives) {
        try {
            $key = $h.Root.OpenSubKey($h.Path)
            if (-not $key) { continue }
            foreach ($subKeyName in $key.GetSubKeyNames()) {
                $sub = $key.OpenSubKey($subKeyName)
                if (-not $sub) { continue }
                $name = $sub.GetValue("DisplayName")
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                [PSCustomObject]@{
                    Name         = $name
                    Version      = $sub.GetValue("DisplayVersion")
                    Publisher    = $sub.GetValue("Publisher")
                    InstallDate  = $sub.GetValue("InstallDate")
                    InstallLocation = $sub.GetValue("InstallLocation")
                    Architecture = $h.Arch
                }
            }
        } catch {
            Write-Warning "Failed to read registry path '$($h.Path)': $($_.Exception.Message)"
        }
    }
}

Write-Log "Scanning installed software on: $target" "Cyan"

try {
    $software = if ($target -eq $env:COMPUTERNAME) {
        & $collectScript
    } else {
        Invoke-Command -ComputerName $target -ErrorAction Stop -ScriptBlock $collectScript
    }

    # Deduplicate by name+version
    $software = $software | Sort-Object Name, Version | Group-Object Name, Version |
        ForEach-Object { $_.Group[0] }

    if (-not [string]::IsNullOrEmpty($FilterName)) {
        $software = $software | Where-Object { $_.Name -match [regex]::Escape($FilterName) }
        Write-Log "Filter applied: '$FilterName'" "Yellow"
    }

    Write-Log "Found $($software.Count) installed packages." "Cyan"
    Write-Host ""

    $software | Sort-Object Name | ForEach-Object {
        $verStr = if ($_.Version) { "  v$($_.Version)" } else { "" }
        $pubStr = if ($_.Publisher) { "  [$($_.Publisher)]" } else { "" }
        Write-Host ("  {0}{1}{2}" -f $_.Name, $verStr, $pubStr) -ForegroundColor Gray
    }

    $software | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
