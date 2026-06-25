<#
.SYNOPSIS
    Setup script for M365 Admin TUI on Windows
.DESCRIPTION
    This script installs all necessary dependencies including PowerShell Core,
    Python packages, and PowerShell modules required for M365 management.
#>

# Requires -Version 5.1
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Microsoft 365 Admin TUI Setup        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator (recommended for winget)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Not running as Administrator. Some installations may require elevated privileges." -ForegroundColor Yellow
    Write-Host ""
}

# Check Python installation
Write-Host "Checking Python installation..." -ForegroundColor Cyan
try {
    $pythonVersion = & python --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$pythonVersion detected" -ForegroundColor Green
    } else {
        throw "Python not found"
    }
} catch {
    Write-Host "Python 3.12 or higher is required but not found." -ForegroundColor Red
    Write-Host ""
    $response = Read-Host "Would you like to install Python? (Y/n)"
    if ($response -eq "" -or $response -eq "Y" -or $response -eq "y") {
        Write-Host "Installing Python..." -ForegroundColor Cyan
        winget install -e --id Python.Python.3.12 --source winget
        Write-Host "Python installed. Please restart your terminal and run setup again." -ForegroundColor Green
        exit 0
    } else {
        Write-Host "Python is required. Exiting setup." -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# Check PowerShell Core
Write-Host "Checking PowerShell Core..." -ForegroundColor Cyan
$pwshInstalled = Get-Command pwsh -ErrorAction SilentlyContinue
if ($null -eq $pwshInstalled) {
    Write-Host "PowerShell Core not found." -ForegroundColor Yellow
    Write-Host ""
    $response = Read-Host "Would you like to install PowerShell Core? (Y/n)"
    if ($response -eq "" -or $response -eq "Y" -or $response -eq "y") {
        Write-Host "Installing PowerShell Core..." -ForegroundColor Cyan
        winget install -e --id Microsoft.PowerShell --source winget
        Write-Host "PowerShell Core installed." -ForegroundColor Green
    } else {
        Write-Host "PowerShell Core is required for M365 management. Exiting setup." -ForegroundColor Red
        exit 1
    }
} else {
    $pwshVersion = & pwsh --version
    Write-Host "$pwshVersion detected" -ForegroundColor Green
}
Write-Host ""

# Check for uv package manager
Write-Host "Checking for uv package manager..." -ForegroundColor Cyan
$uvInstalled = Get-Command uv -ErrorAction SilentlyContinue
if ($null -eq $uvInstalled) {
    Write-Host "uv package manager not found." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "uv is a fast Python package installer and manager."
    Write-Host "It's recommended for better performance, but not required."
    Write-Host ""
    $response = Read-Host "Would you like to install uv? (Y/n/c)"
    
    if ($response -eq "" -or $response -eq "Y" -or $response -eq "y") {
        Write-Host "Installing uv package manager..." -ForegroundColor Cyan
        powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
        
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        $uvInstalled = Get-Command uv -ErrorAction SilentlyContinue
        if ($null -ne $uvInstalled) {
            Write-Host "uv package manager installed." -ForegroundColor Green
        } else {
            Write-Host "uv was installed but not found in PATH. Continuing with pip..." -ForegroundColor Yellow
        }
    } elseif ($response -eq "C" -or $response -eq "c") {
        Write-Host "Setup cancelled by user." -ForegroundColor Red
        exit 1
    } else {
        Write-Host " Continuing with pip instead..." -ForegroundColor Yellow
    }
} else {
    $uvVersion = & uv --version
    Write-Host "$uvVersion detected" -ForegroundColor Green
}
Write-Host ""

# Create virtual environment
Write-Host "Setting up Python virtual environment..." -ForegroundColor Cyan
$uvInstalled = Get-Command uv -ErrorAction SilentlyContinue
if ($null -ne $uvInstalled) {
    Write-Host "   Using uv to create virtual environment..." -ForegroundColor Cyan
    uv venv .\.venv
} else {
    Write-Host "   Using python -m venv..." -ForegroundColor Cyan
    python -m venv .\.venv
}

# Activate virtual environment
Write-Host "   Activating virtual environment..." -ForegroundColor Cyan
& .\.venv\Scripts\Activate.ps1

Write-Host "Virtual environment created and activated" -ForegroundColor Green
Write-Host ""

# Install Python dependencies
Write-Host "Installing Python dependencies..." -ForegroundColor Cyan
$uvInstalled = Get-Command uv -ErrorAction SilentlyContinue
if ($null -ne $uvInstalled) {
    Write-Host "   Using uv for faster installation..." -ForegroundColor Cyan
    uv pip install -r requirements.txt --quiet
} else {
    Write-Host "   Using pip..." -ForegroundColor Cyan
    pip install -r requirements.txt --quiet
}
Write-Host "Python dependencies installed" -ForegroundColor Green
Write-Host ""

# Check/Install PowerShell modules
Write-Host "Checking PowerShell modules..." -ForegroundColor Cyan

$modules = @("Microsoft.Graph.Authentication", "Microsoft.Graph.Users", "ExchangeOnlineManagement")
$missing = @()

foreach ($module in $modules) {
    if ($null -eq (Get-Module -ListAvailable -Name $module)) {
        $missing += $module
    } else {
        Write-Host "   $module" -ForegroundColor Green
    }
}

if ($missing.Count -gt 0) {
    Write-Host "" 
    Write-Host "Missing PowerShell modules:" -ForegroundColor Yellow
    foreach ($module in $missing) {
        Write-Host "   - $module" -ForegroundColor Yellow
    }
    Write-Host ""
    
    $response = Read-Host "Would you like to install missing modules now? (Y/n)"
    if ($response -eq "" -or $response -eq "Y" -or $response -eq "y") {
        Write-Host ""
        Write-Host "Installing PowerShell modules..." -ForegroundColor Cyan
        
        # Install Graph modules
        if ($missing -like "Microsoft.Graph.*") {
            Write-Host "   Installing Microsoft.Graph..." -ForegroundColor Cyan
            pwsh -Command "Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber"
            Write-Host "   Microsoft.Graph installed" -ForegroundColor Green
        }
        
        # Install Exchange module
        if ($missing -contains "ExchangeOnlineManagement") {
            Write-Host "   Installing ExchangeOnlineManagement..." -ForegroundColor Cyan
            pwsh -Command "Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber"
            Write-Host "   ExchangeOnlineManagement installed" -ForegroundColor Green
        }
        
        Write-Host ""
        Write-Host "All PowerShell modules installed" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "You can install modules later by running:" -ForegroundColor Yellow
        Write-Host "   pwsh" -ForegroundColor White
        Write-Host "   Install-Module Microsoft.Graph -Scope CurrentUser -Force" -ForegroundColor White
        Write-Host "   Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force" -ForegroundColor White
    }
} else {
    Write-Host "   All PowerShell modules are installed" -ForegroundColor Green
}
Write-Host ""

# Create necessary directories
Write-Host "Creating directories..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path "logs" | Out-Null
New-Item -ItemType Directory -Force -Path "$HOME\Documents\M365Reports" | Out-Null
Write-Host "Directories created" -ForegroundColor Green
Write-Host ""

Write-Host ""
Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   Setup completed successfully!        ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host ""
Write-Host " 1. Activate the virtual environment (if not already active):" -ForegroundColor White
Write-Host "    .\.venv\Scripts\Activate.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host " 2. Run the application:" -ForegroundColor White
Write-Host "    python main.py" -ForegroundColor Cyan
Write-Host ""
Write-Host "For more information, see README.md" -ForegroundColor White
Write-Host ""