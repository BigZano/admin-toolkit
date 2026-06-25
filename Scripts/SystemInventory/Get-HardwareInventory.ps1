# Detailed hardware inventory including CPU, RAM, disks, GPU, and network adapters

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
$outputFile = Join-Path $OutputDirectory "HardwareInventory_${target}_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "HardwareInventory_${target}_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

function Print-Section { param([string]$Title)
    Write-Host ""; Write-Host "  -- $Title --" -ForegroundColor DarkYellow
}

Write-Log "Gathering hardware inventory from: $target" "Cyan"

try {
    $cimParams = if ($target -ne $env:COMPUTERNAME) { @{ CimSession = New-CimSession -ComputerName $target } } else { @{} }

    $cs      = Get-CimInstance Win32_ComputerSystem @cimParams
    $cpus    = Get-CimInstance Win32_Processor @cimParams
    $mem     = Get-CimInstance Win32_PhysicalMemory @cimParams
    $disks   = Get-CimInstance Win32_DiskDrive @cimParams
    $gpus    = Get-CimInstance Win32_VideoController @cimParams
    $nics    = Get-CimInstance Win32_NetworkAdapter @cimParams | Where-Object { $_.PhysicalAdapter }
    $bios    = Get-CimInstance Win32_BIOS @cimParams

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    Write-Host ("  Hardware Inventory: {0}" -f $cs.Name) -ForegroundColor Yellow
    Write-Host ("  {0} {1}" -f $cs.Manufacturer, $cs.Model) -ForegroundColor Gray
    Write-Host ("=" * 60) -ForegroundColor DarkGray

    Print-Section "CPU"
    $cpus | ForEach-Object {
        Write-Host ("  {0}" -f $_.Name.Trim()) -ForegroundColor Cyan
        Write-Host ("  Cores: {0}  Logical: {1}  Speed: {2} MHz  Socket: {3}" -f
            $_.NumberOfCores, $_.NumberOfLogicalProcessors, $_.MaxClockSpeed, $_.SocketDesignation) -ForegroundColor Gray
    }

    Print-Section "Memory"
    $totalRam = [math]::Round(($mem | Measure-Object -Property Capacity -Sum).Sum / 1GB, 0)
    Write-Host ("  Total: {0} GB  |  Slots used: {1}" -f $totalRam, $mem.Count) -ForegroundColor Cyan
    $mem | ForEach-Object {
        $gb = [math]::Round($_.Capacity / 1GB, 0)
        Write-Host ("  [{0}] {1} GB  {2} MHz  {3}" -f $_.DeviceLocator, $gb, $_.Speed, $_.Manufacturer) -ForegroundColor Gray
    }

    Print-Section "Disks"
    $disks | ForEach-Object {
        $gb = [math]::Round($_.Size / 1GB, 0)
        Write-Host ("  {0}  {1,6} GB  {2}  [{3}]" -f $_.Model, $gb, $_.MediaType, $_.Status) -ForegroundColor Cyan
        Write-Host ("  Serial: {0}  Interface: {1}" -f $_.SerialNumber, $_.InterfaceType) -ForegroundColor Gray
    }

    Print-Section "GPU"
    $gpus | ForEach-Object {
        $vramMB = [math]::Round($_.AdapterRAM / 1MB, 0)
        Write-Host ("  {0}" -f $_.Name) -ForegroundColor Cyan
        Write-Host ("  VRAM: {0} MB  Driver: {1}  Resolution: {2}x{3}" -f
            $vramMB, $_.DriverVersion, $_.CurrentHorizontalResolution, $_.CurrentVerticalResolution) -ForegroundColor Gray
    }

    Print-Section "Network Adapters"
    $nics | ForEach-Object {
        Write-Host ("  {0}" -f $_.Name) -ForegroundColor Cyan
        Write-Host ("  MAC: {0}  Speed: {1}" -f $_.MACAddress, $_.Speed) -ForegroundColor Gray
    }

    Write-Host ("=" * 60) -ForegroundColor DarkGray

    # Flat record for CSV
    $record = [PSCustomObject]@{
        Computer       = $cs.Name
        Manufacturer   = $cs.Manufacturer
        Model          = $cs.Model
        BIOSVersion    = $bios.SMBIOSBIOSVersion
        SerialNumber   = $bios.SerialNumber
        CPU            = ($cpus | Select-Object -First 1).Name.Trim()
        CPUSockets     = $cpus.Count
        CoresPerCPU    = ($cpus | Select-Object -First 1).NumberOfCores
        LogicalCPUs    = ($cpus | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        RAMtotalGB     = [math]::Round(($mem | Measure-Object -Property Capacity -Sum).Sum / 1GB, 0)
        RAMslots       = $mem.Count
        DiskCount      = $disks.Count
        TotalDiskGB    = [math]::Round(($disks | Measure-Object -Property Size -Sum).Sum / 1GB, 0)
        GPU            = ($gpus | Select-Object -First 1).Name
        NICCount       = $nics.Count
    }

    $record | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"

    if ($cimParams.ContainsKey("CimSession")) { Remove-CimSession $cimParams["CimSession"] }
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
