# Report the current Windows audit policy configuration for all categories

param(
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
$outputFile = Join-Path $OutputDirectory "AuditPolicy_$timestamp.csv"
$logFile    = Join-Path $OutputDirectory "AuditPolicy_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File $logFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "Reading audit policy via auditpol.exe..." "Cyan"

try {
    # /r emits CSV (structurally locale-stable), avoiding fragile parsing of the aligned table output
    $raw = auditpol.exe /get /category:* /r 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "auditpol failed. Ensure you are running as Administrator." "Red"; exit 1
    }

    $rows = $raw | Where-Object { "$_".Trim() } | ConvertFrom-Csv

    $report = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $subcat  = $row.Subcategory
        $setting = $row.'Inclusion Setting'
        if ([string]::IsNullOrWhiteSpace($subcat) -or [string]::IsNullOrWhiteSpace($setting)) { continue }

        $status = switch ($setting) {
            "Success and Failure" { "Full" }
            "Success"             { "Partial" }
            "Failure"             { "Partial" }
            "No Auditing"         { "Off" }
            default               { $setting }
        }

        $color = switch ($status) {
            "Full"    { "Green" }
            "Partial" { "Yellow" }
            "Off"     { "Red" }
            default   { "Gray" }
        }

        Write-Host ("  {0,-45} [{1}]" -f $subcat, $setting) -ForegroundColor $color

        $report.Add([PSCustomObject]@{
            Subcategory     = $subcat
            SubcategoryGuid = $row.'Subcategory GUID'
            Setting         = $setting
            Status          = $status
        })
    }

    if ($report.Count -eq 0) {
        Write-Log "auditpol returned no parseable rows." "Red"; exit 1
    }

    $full    = @($report | Where-Object { $_.Status -eq "Full" })
    $partial = @($report | Where-Object { $_.Status -eq "Partial" })
    $off     = @($report | Where-Object { $_.Status -eq "Off" })

    Write-Host ""
    Write-Log "Full audit: $($full.Count)  |  Partial: $($partial.Count)  |  Off: $($off.Count)" `
        "$(if ($off.Count -gt ($report.Count / 2)) { 'Red' } else { 'Yellow' })"

    # Flag critical subcategories that should always be on
    $criticalOff = @($off | Where-Object {
        $_.Subcategory -in @(
            "Logon", "Logoff", "Account Lockout",
            "Audit Policy Change", "User Account Management",
            "Security Group Management", "Process Creation",
            "Special Logon", "Sensitive Privilege Use"
        )
    })
    if ($criticalOff.Count -gt 0) {
        Write-Host ""
        Write-Host "  WARNING - Critical subcategories not audited:" -ForegroundColor Red
        $criticalOff | ForEach-Object {
            Write-Host ("  {0}" -f $_.Subcategory) -ForegroundColor Red
        }
    }

    $report | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host ""; Write-Log "Report saved to: $outputFile" "Green"
} catch {
    Write-Log "Error: $($_.Exception.Message)" "Red"; exit 1
}
