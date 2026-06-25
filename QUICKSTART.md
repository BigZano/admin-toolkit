# Quick Start Guide

## For Technicians - First Time Setup

### 1. Install Prerequisites

**Install PowerShell Core:**
```bash
# Ubuntu/Debian
sudo apt-get install -y powershell

# macOS
brew install --cask powershell
```

**Verify PowerShell:**
```bash
pwsh --version
```

### 2. Clone and Setup

```bash
# Clone the repository
git clone https://github.com/BigZano/TUI-project.git
cd TUI-project

# Run setup script (Linux/macOS)
./setup.sh

# Or install manually
pip install -r requirements.txt
```

### 3. Install PowerShell Modules

```bash
pwsh
```

Then in PowerShell:
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
exit
```

### 4. Run the Tool

```bash
python main.py
```

## Usage

### Creating a User
1. Launch the tool: `python main.py`
2. Select "Create User (Microsoft Graph)"
3. Fill in the form:
   - Display Name: `John Doe`
   - User Principal Name: `john.doe@company.com`
   - Usage Location: `US` (2-letter country code)
   - Password: At least 8 characters
   - License Index: `0` to skip, or number after listing licenses
4. Click "Create User"
5. Sign in when prompted (web browser will open)
6. Check output panel for results

### Running an Audit
1. Select the audit type (MFA Audit, Delegate Access, etc.)
2. Enter required information if prompted
3. Sign in when prompted
4. Wait for completion
5. Reports saved to `~/Documents/M365Reports/`

### Tips
- Press `q` to quit
- Press `d` to toggle dark/light theme
- Press `c` to clear output
- Press `Escape` to cancel dialogs
- Check `logs/` directory for detailed logs

## Common Tasks

### List Available Licenses
```bash
pwsh Scripts/MgGraphUserCreation.ps1 -ListLicenses
```

### Check Delegate Access
Run from TUI: Select "Audit Delegate Access"
Enter user email to check who has access to their mailbox

### Export All Mailboxes
Run from TUI: Select "Export Mailbox Report"
Choose mailbox type (All, UserMailbox, SharedMailbox, etc.)

## Troubleshooting

**"pwsh not found"**
- Install PowerShell Core (see step 1 above)

**"Failed to import modules"**
- Install PowerShell modules (see step 3 above)

**"Authentication failed"**
- Ensure you're using an admin account
- Check your account has required permissions
- Try disconnecting first:
  ```powershell
  pwsh
  Disconnect-MgGraph
  Disconnect-ExchangeOnline -Confirm:$false
  ```

**"Import errors in Python"**
- Check Python version: `python --version` (need 3.12+)
- Reinstall requirements: `pip install -r requirements.txt --force-reinstall`

## Getting Help

1. Check the full README.md
2. Review logs in `logs/` directory
3. Check output panel in the TUI
4. Pray. And Google. 
