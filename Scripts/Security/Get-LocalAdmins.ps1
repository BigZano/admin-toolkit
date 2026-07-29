# Audit local Administrators group membership on one or more computers

param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerList = "",
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
$outputFile = Join-Path $OutputDirectory "LocalAdmins_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "LocalAdmins_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

# Resolve computer list
$computers = if (-not [string]::IsNullOrEmpty($ComputerList) -and (Test-Path -LiteralPath $ComputerList -ErrorAction SilentlyContinue)) {
    Get-Content -LiteralPath $ComputerList | Where-Object { $_ -match '\S' }
} elseif (-not [string]::IsNullOrEmpty($ComputerList)) {
    $ComputerList -split ',' | ForEach-Object { $_.Trim() }
} else {
    @($env:COMPUTERNAME)
}
$computers = @($computers)

Write-Log "Auditing local Administrators on $($computers.Count) computer(s)..." "Cyan"

# Shared query: run directly on the local machine (no WinRM required),
# via Invoke-Command for remote machines.
$adminQuery = {
    $group = [ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group"
    $group.Members() | ForEach-Object {
        $path = $_.GetType().InvokeMember("ADsPath", "GetProperty", $null, $_, $null)
        $name = $_.GetType().InvokeMember("Name", "GetProperty", $null, $_, $null)
        $type = $_.GetType().InvokeMember("Class", "GetProperty", $null, $_, $null)
        $sid  = ""
        try {
            $sidBytes = $_.GetType().InvokeMember("objectSid", "GetProperty", $null, $_, $null)
            if ($sidBytes) { $sid = (New-Object System.Security.Principal.SecurityIdentifier($sidBytes, 0)).Value }
        } catch { }
        [PSCustomObject]@{
            Computer  = $env:COMPUTERNAME
            Member    = $name
            Type      = $type
            SID       = $sid
            # Local member ADsPaths look like WinNT://<domain-or-workgroup>/<computer>/<account>
            Source    = if ($path -match "/$env:COMPUTERNAME/") { "Local" } else { "Domain" }
            ADsPath   = $path
        }
    }
}

$failedCount = 0
$report = foreach ($computer in $computers) {
    Write-Log "  Processing: $computer" "Gray"
    try {
        if ($computer -eq $env:COMPUTERNAME) {
            & $adminQuery
        } else {
            Invoke-Command -ComputerName $computer -ErrorAction Stop -ScriptBlock $adminQuery
        }
    } catch {
        $failedCount++
        Write-Log "  Failed on $computer : $($_.Exception.Message)" "Red"
        [PSCustomObject]@{
            Computer = $computer; Member = "ERROR"; Type = ""; SID = ""; Source = ""; ADsPath = $_.Exception.Message
        }
    }
}

# Flag non-standard accounts: local users that are not the built-in Administrator.
# The built-in Administrator is identified by its well-known SID suffix (-500),
# which also catches a renamed Administrator account.
$nonStandard = @($report | Where-Object {
    $_.Source -eq "Local" -and $_.Type -eq "User" -and $_.SID -notlike "*-500"
})

$domainAccounts = @($report | Where-Object { $_.Source -eq "Domain" })

Write-Log "Total entries: $($report.Count)  |  Domain accounts: $($domainAccounts.Count)  |  Non-standard local users: $($nonStandard.Count)" `
    "$(if ($nonStandard.Count -gt 0) { 'Yellow' } else { 'Green' })"
Write-Host ""

$report | Group-Object Computer | ForEach-Object {
    Write-Host "  $($_.Name):" -ForegroundColor Cyan
    $_.Group | ForEach-Object {
        $color = if ($_.Source -eq "Local" -and $_.Type -eq "User" -and $_.SID -notlike "*-500") { "Yellow" }
                 elseif ($_.Source -eq "Domain") { "White" }
                 else { "DarkGray" }
        Write-Host ("    {0,-30} [{1}] [{2}]" -f $_.Member, $_.Type, $_.Source) -ForegroundColor $color
    }
}

$report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"

if ($failedCount -eq $computers.Count) {
    Write-Log "All $($computers.Count) computer(s) failed to respond." "Red"
    exit 1
}
