# Check machines for pending reboot flags

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerList = "",
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
$outputFile = Join-Path $OutputDirectory "Get-PendingReboot_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "Get-PendingReboot_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

if ([string]::IsNullOrEmpty($ComputerList)) {
    $computers = @($env:COMPUTERNAME)
} else {
    $computers = $ComputerList -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

Write-Log "Checking pending reboot flags on $($computers.Count) machine(s)..." "Cyan"

$checkBlock = {
    $cbs = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $wu  = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'

    $fileRename = $false
    try {
        $pfro = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($pfro -and $pfro.PendingFileRenameOperations) { $fileRename = $true }
    } catch { }

    $rename = $false
    try {
        $active  = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction SilentlyContinue).ComputerName
        $pending = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction SilentlyContinue).ComputerName
        if ($active -and $pending -and ($active -ne $pending)) { $rename = $true }
    } catch { }

    [PSCustomObject]@{
        CBS           = $cbs
        WindowsUpdate = $wu
        FileRename    = $fileRename
        Rename        = $rename
    }
}

$results = @()
$failed  = 0

foreach ($computer in $computers) {
    try {
        if ($computer -eq $env:COMPUTERNAME) {
            $check = & $checkBlock
        } else {
            $check = Invoke-Command -ComputerName $computer -ScriptBlock $checkBlock -ErrorAction Stop
        }

        $anyPending = $check.CBS -or $check.WindowsUpdate -or $check.FileRename -or $check.Rename
        $results += [PSCustomObject]@{
            Machine       = $computer
            CBS           = $check.CBS
            WindowsUpdate = $check.WindowsUpdate
            FileRename    = $check.FileRename
            Rename        = $check.Rename
            AnyPending    = $anyPending
        }

        if ($anyPending) {
            Write-Log ("  {0,-20} REBOOT PENDING (CBS:{1} WU:{2} FileRename:{3} Rename:{4})" -f $computer, $check.CBS, $check.WindowsUpdate, $check.FileRename, $check.Rename) "Yellow"
        } else {
            Write-Log ("  {0,-20} no pending reboot" -f $computer) "Green"
        }
    } catch {
        $failed++
        Write-Log ("  {0,-20} UNREACHABLE: {1}" -f $computer, $_.Exception.Message) "Red"
        $results += [PSCustomObject]@{
            Machine       = $computer
            CBS           = ""
            WindowsUpdate = ""
            FileRename    = ""
            Rename        = ""
            AnyPending    = "Unreachable"
        }
    }
}

$results | Export-Csv -Path $outputFile -NoTypeInformation
Write-Host ""
$results | Format-Table -AutoSize

$pending = @($results | Where-Object { $_.AnyPending -eq $true })
Write-Log "Machines: $($computers.Count); pending reboot: $($pending.Count); unreachable: $failed" $(if ($pending.Count -gt 0) { "Yellow" } else { "Cyan" })
Write-Log "Report saved: $outputFile" "Green"
