# Get a comprehensive system overview including OS, hardware, and uptime

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
$outputFile = Join-Path $OutputDirectory "SystemInfo_${target}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "SystemInfo_${target}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "Gathering system info from: $target" "Cyan"

try {
    $cimParams = if ($target -ne $env:COMPUTERNAME) { @{ CimSession = New-CimSession -ComputerName $target } } else { @{} }

    $os      = Get-CimInstance Win32_OperatingSystem @cimParams
    $cs      = Get-CimInstance Win32_ComputerSystem @cimParams
    $cpu     = Get-CimInstance Win32_Processor @cimParams | Select-Object -First 1
    $bios    = Get-CimInstance Win32_BIOS @cimParams
    $disks   = Get-CimInstance Win32_LogicalDisk @cimParams -Filter "DriveType=3"

    $uptime  = (Get-Date) - $os.LastBootUpTime
    $uptimeStr = "{0}d {1}h {2}m" -f [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes
    $ramGB   = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $freeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    Write-Host ("  {0}" -f $cs.Name) -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor DarkGray

    $fields = [ordered]@{
        "OS"              = "$($os.Caption) (Build $($os.BuildNumber))"
        "OS Architecture" = $os.OSArchitecture
        "Install Date"    = $os.InstallDate.ToString("yyyy-MM-dd")
        "Last Boot"       = "$($os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm'))  (up $uptimeStr)"
        "Domain / WG"     = if ($cs.PartOfDomain) { $cs.Domain } else { "$($cs.Workgroup) [Workgroup]" }
        "Manufacturer"    = $cs.Manufacturer
        "Model"           = $cs.Model
        "CPU"             = "$($cpu.Name.Trim())  ($($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) logical)"
        "RAM"             = "$ramGB GB total  |  $freeGB GB free"
        "BIOS"            = "$($bios.SMBIOSBIOSVersion)  [$($bios.ReleaseDate.ToString('yyyy-MM-dd'))]"
        "Serial Number"   = $bios.SerialNumber
        "Logged In User"  = $cs.UserName
    }

    foreach ($f in $fields.GetEnumerator()) {
        Write-Host ("  {0,-20} {1}" -f "$($f.Key):", $f.Value) -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host "  Drives:" -ForegroundColor DarkGray
    foreach ($disk in ($disks | Sort-Object DeviceID)) {
        $totalGB = [math]::Round($disk.Size / 1GB, 1)
        $freeGB2 = [math]::Round($disk.FreeSpace / 1GB, 1)
        $usedPct = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 0)
        $dcolor  = if ($usedPct -ge 90) { "Red" } elseif ($usedPct -ge 75) { "Yellow" } else { "Green" }
        Write-Host ("  {0}  {1,6} GB total  {2,6} GB free  [{3}% used]" -f $disk.DeviceID, $totalGB, $freeGB2, $usedPct) -ForegroundColor $dcolor
    }

    Write-Host ("=" * 60) -ForegroundColor DarkGray

    # Export flat record
    $record = [PSCustomObject]@{
        Computer        = $cs.Name
        OS              = $os.Caption
        Build           = $os.BuildNumber
        Architecture    = $os.OSArchitecture
        Domain          = if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup }
        Manufacturer    = $cs.Manufacturer
        Model           = $cs.Model
        CPU             = $cpu.Name.Trim()
        Cores           = $cpu.NumberOfCores
        LogicalCPUs     = $cpu.NumberOfLogicalProcessors
        RAMtotalGB      = $ramGB
        RAMfreeGB       = $freeGB
        LastBoot        = $os.LastBootUpTime.ToString("yyyy-MM-dd HH:mm")
        UptimeDays      = [math]::Round($uptime.TotalDays, 1)
        BIOSVersion     = $bios.SMBIOSBIOSVersion
        SerialNumber    = $bios.SerialNumber
        LoggedInUser    = $cs.UserName
    }

    $record | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"

    if ($cimParams.ContainsKey("CimSession")) { Remove-CimSession $cimParams["CimSession"] }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
