# List all programs configured to run at startup

param(
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
$outputFile = Join-Path $OutputDirectory "Get-StartupPrograms_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Get-StartupPrograms_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "Collecting startup programs from registry, startup folders, and WMI..." "Cyan"

$entries = @()

# 1. Registry Run/RunOnce keys
$regPaths = @(
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";              Source = "HKLM Run" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce";          Source = "HKLM RunOnce" },
    @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run";  Source = "HKLM Run (32-bit)" },
    @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce"; Source = "HKLM RunOnce (32-bit)" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";              Source = "HKCU Run" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce";          Source = "HKCU RunOnce" }
)

foreach ($reg in $regPaths) {
    try {
        if (Test-Path $reg.Path) {
            $props = Get-ItemProperty -Path $reg.Path -ErrorAction Stop
            foreach ($prop in $props.PSObject.Properties) {
                if ($prop.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$') {
                    $entries += [PSCustomObject]@{
                        Name    = $prop.Name
                        Command = "$($prop.Value)"
                        Source  = $reg.Source
                    }
                }
            }
        }
    } catch {
        Write-Log "Could not read $($reg.Path): $($_.Exception.Message)" "Yellow"
    }
}

# 2. Startup folders (user + common)
$startupFolders = @(
    @{ Path = [Environment]::GetFolderPath("Startup");       Source = "User Startup folder" },
    @{ Path = [Environment]::GetFolderPath("CommonStartup"); Source = "Common Startup folder" }
)

foreach ($folder in $startupFolders) {
    if (-not [string]::IsNullOrEmpty($folder.Path) -and (Test-Path $folder.Path)) {
        Get-ChildItem -Path $folder.Path -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "desktop.ini" } |
            ForEach-Object {
                $entries += [PSCustomObject]@{
                    Name    = $_.BaseName
                    Command = $_.FullName
                    Source  = $folder.Source
                }
            }
    }
}

# 3. WMI Win32_StartupCommand (catches additional locations)
try {
    Get-CimInstance Win32_StartupCommand -ErrorAction Stop | ForEach-Object {
        $entries += [PSCustomObject]@{
            Name    = $_.Name
            Command = $_.Command
            Source  = "WMI ($($_.Location))"
        }
    }
} catch {
    Write-Log "Win32_StartupCommand query failed: $($_.Exception.Message)" "Yellow"
}

# De-duplicate on Name + Command, keep first source seen and note extras
$results = @()
$seen    = @{}
foreach ($entry in $entries) {
    $key = "$($entry.Name)|$($entry.Command)".ToLowerInvariant()
    if ($seen.ContainsKey($key)) {
        $existing = $seen[$key]
        if ($existing.Source -notmatch [regex]::Escape($entry.Source)) {
            $existing.Source = "$($existing.Source); $($entry.Source)"
        }
    } else {
        $copy = [PSCustomObject]@{ Name = $entry.Name; Command = $entry.Command; Source = $entry.Source }
        $seen[$key] = $copy
        $results += $copy
    }
}

$results = @($results | Sort-Object Name)

if ($results.Count -eq 0) {
    Write-Log "No startup programs found." "Yellow"
    exit 0
}

$results | Export-Csv -Path $outputFile -NoTypeInformation
$results | Format-Table Name, Source, Command -AutoSize

Write-Log "Found $($results.Count) unique startup entrie(s) ($($entries.Count) raw across all sources)." "Cyan"
Write-Log "Report saved: $outputFile" "Green"
