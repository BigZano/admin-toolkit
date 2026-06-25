#!/bin/bash
# Setup script for M365 Admin TUI
# This script will install all necessary dependencies for Linux/macOS

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo ""
echo "╔════════════════════════════════════════╗"
echo "║   Microsoft 365 Admin TUI Setup       ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check Python version
echo "Checking Python version..."
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Python 3 is not installed. Please install Python 3.12 or higher.${NC}"
    exit 1
fi

PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)

if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 12 ]); then
    echo -e "${RED}Python 3.12 or higher is required. Current version: $PYTHON_VERSION${NC}"
    exit 1
fi

echo -e "${GREEN}Python $PYTHON_VERSION detected${NC}"
echo ""

# Check for PowerShell Core
echo "Checking PowerShell Core..."
if ! command -v pwsh &> /dev/null; then
    echo -e "${YELLOW}PowerShell Core (pwsh) is not installed.${NC}"
    echo ""
    echo "PowerShell Core is required for M365 management scripts."
    echo ""
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Installation command for Ubuntu/Debian:"
        echo -e "${CYAN}  wget -q https://packages.microsoft.com/config/ubuntu/\$(lsb_release -rs)/packages-microsoft-prod.deb${NC}"
        echo -e "${CYAN}  sudo dpkg -i packages-microsoft-prod.deb${NC}"
        echo -e "${CYAN}  sudo apt-get update${NC}"
        echo -e "${CYAN}  sudo apt-get install -y powershell${NC}"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Installation command for macOS:"
        echo -e "${CYAN}  brew install --cask powershell${NC}"
    fi
    echo ""
    
    read -p "Would you like to continue without PowerShell? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Setup cancelled. Please install PowerShell Core and run setup again.${NC}"
        exit 1
    fi
    echo -e "${YELLOW}Continuing without PowerShell - M365 scripts will not work until installed.${NC}"
else
    PWSH_VERSION=$(pwsh --version)
    echo -e "${GREEN}$PWSH_VERSION detected${NC}"
fi
echo ""

# Check for uv package manager
echo "Checking for uv package manager..."
if ! command -v uv &> /dev/null; then
    echo -e "${YELLOW}uv package manager not found.${NC}"
    echo ""
    echo "uv is a fast Python package installer and manager."
    echo "It's recommended for better performance, but not required."
    echo ""
    
    read -p "Would you like to install uv? (Y/n/c): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        echo -e "${CYAN}Installing uv package manager...${NC}"
        curl -LsSf https://astral.sh/uv/install.sh | sh
        
        # Source the uv environment
        export PATH="$HOME/.cargo/bin:$PATH"
        
        if command -v uv &> /dev/null; then
            echo -e "${GREEN}uv package manager installed successfully${NC}"
        else
            echo -e "${YELLOW}uv was installed but not found in PATH. You may need to restart your shell.${NC}"
            echo -e "${YELLOW}   Continuing with pip instead...${NC}"
        fi
    elif [[ $REPLY =~ ^[Cc]$ ]]; then
        echo -e "${RED}Setup cancelled by user.${NC}"
        exit 1
    else
        echo -e "${YELLOW}Continuing with pip instead...${NC}"
    fi
else
    UV_VERSION=$(uv --version)
    echo -e "${GREEN}$UV_VERSION detected${NC}"
fi
echo ""

# Create virtual environment
echo "Setting up Python virtual environment..."
if command -v uv &> /dev/null; then
    echo -e "${CYAN}   Using uv to create virtual environment...${NC}"
    uv venv .venv
else
    echo -e "${CYAN}   Using python3 -m venv...${NC}"
    python3 -m venv .venv
fi

# Activate virtual environment
source .venv/bin/activate

echo -e "${GREEN}Virtual environment created and activated${NC}"
echo ""

# Install Python dependencies
echo "Installing Python dependencies..."
if command -v uv &> /dev/null; then
    echo -e "${CYAN}   Using uv for faster installation...${NC}"
    uv pip install -r requirements.txt --quiet
else
    echo -e "${CYAN}   Using pip...${NC}"
    pip install -r requirements.txt --quiet
fi
echo -e "${GREEN}Python dependencies installed${NC}"
echo ""

# Check/Install PowerShell modules
if command -v pwsh &> /dev/null; then
    echo "Checking PowerShell modules..."
    
    # Create a temporary PowerShell script
    cat > /tmp/check_modules.ps1 << 'EOF'
$modules = @("Microsoft.Graph.Authentication", "Microsoft.Graph.Users", "ExchangeOnlineManagement")
$missing = @()

foreach ($module in $modules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
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
            Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
            Write-Host "   Microsoft.Graph installed" -ForegroundColor Green
        }
        
        # Install Exchange module
        if ($missing -contains "ExchangeOnlineManagement") {
            Write-Host "   Installing ExchangeOnlineManagement..." -ForegroundColor Cyan
            Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber
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
EOF
    
    pwsh -NoProfile -File /tmp/check_modules.ps1
    rm /tmp/check_modules.ps1
    echo ""
fi

# Create necessary directories
echo "Creating directories..."
mkdir -p logs
mkdir -p ~/Documents/M365Reports
echo -e "${GREEN}Directories created${NC}"
echo ""

echo ""
echo "╔════════════════════════════════════════╗"
echo "║   Setup completed successfully!        ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo ""
echo " 1. Activate the virtual environment (if not already active):"
echo -e "    ${CYAN}source .venv/bin/activate${NC}"
echo ""
echo " 2. Run the application:"
echo -e "    ${CYAN}python main.py${NC}"
echo ""
echo "For more information, see README.md"
echo ""