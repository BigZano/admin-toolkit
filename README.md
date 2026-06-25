# Microsoft 365 Admin TUI

A professional Terminal User Interface (TUI) for managing Microsoft 365 via PowerShell scripts. Built with Python's Textual framework, this tool provides a secure, user-friendly interface for common M365 administrative tasks.

## Features

- **Secure OAuth2 Authentication**: Interactive sign-in with full MFA support
- **User Management**: Create users with Microsoft Graph API
- **Delegate Access Auditing**: Comprehensive mailbox permission analysis
- **Mailbox Reporting**: Export detailed mailbox information
- **MFA & Auth Method Reports**: Audit authentication methods across your tenant
- **Detailed Logging**: All operations logged for audit trails
- **Professional UI**: Warm, intuitive terminal interface

## Prerequisites

### System Requirements
- **Operating System**: Linux, macOS, or Windows with WSL2
- **Python**: 3.12 or higher
- **PowerShell Core**: 7.0 or higher (`pwsh`)

### Required PowerShell Modules
- Microsoft.Graph (Authentication, Users)
- ExchangeOnlineManagement

## Quick Start

The below commands will clone the most recent release, change into the directory, turn the setup script executable and run. They are provided for convenience and you are **strongly encouraged** to review any commands you get from a stranger on the internet before running. 

### Ubuntu/Debian
```bash
git clone https://github.com/BigZano/365Adm-TUI.git && cd 365Adm-TUI && chmod +x setup.sh && ./setup.sh
```

### macOS
```bash
git clone https://github.com/BigZano/365Adm-TUI.git && cd 365Adm-TUI && chmod +x setup.sh && ./setup.sh
```

### Windows (WSL2 users should use the Ubuntu install directions, or install according to your distro)
```powershell
git clone https://github.com/BigZano/365Adm-TUI.git; cd 365Adm-TUI; powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

### Manual Setup (All Platforms)

<details>
<summary>Click to expand manual installation steps</summary>

#### 1. Clone the Repository
```bash
git clone https://github.com/BigZano/365Adm-TUI.git
cd 365Adm-TUI
```

#### 2. Install Python Dependencies
```bash
# Using pip
pip install -r requirements.txt

# Or using uv (recommended)
uv pip install -r requirements.txt
```

#### 3. Install PowerShell Core
If you don't have PowerShell Core installed:

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y wget apt-transport-https software-properties-common
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y powershell
```

**macOS:**
```bash
brew install --cask powershell
```

**Verify installation:**
```bash
pwsh --version
```

#### 4. Install Required PowerShell Modules
Run PowerShell and install the necessary modules:
```powershell
pwsh
Install-Module Microsoft.Graph -Scope CurrentUser -Force
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
```

#### 5. Run the Application
```bash
python main.py
```

</details>


## Usage

### Main Interface
When you launch the application, you'll see a menu with available operations:

1. **Create User (Microsoft Graph)**: Create new M365 users with licenses
2. **Audit Delegate Access**: Check mailbox delegation permissions
3. **Export Mailbox Report**: Generate comprehensive mailbox reports
4. **MFA Audit (All Users)**: Audit MFA status across all users
5. **Authentication Method Report**: Report on auth methods and policies

### Authentication Flow
- Select an operation
- You'll be prompted to sign in via web browser (OAuth2)
- MFA is fully supported and will prompt as configured in your tenant
- Session persists for the PowerShell module session duration

### Keyboard Shortcuts
- `q` - Quit application
- `d` - Toggle dark/light theme
- `c` - Clear output panel
- `Escape` - Cancel current dialog

## Directory Structure

```
365Adm-TUI/
├── main.py                          # Main TUI application (terminal interface)
├── lib/                             # Python library modules (logging functions here as well)
│   ├── __init__.py
│   └── script_registry.py           # Auto-discovers PowerShell scripts
├── Scripts/                         # PowerShell scripts (auto-discovered)
│   ├── Loop for Delegate access.ps1
│   ├── Mailbox export.ps1
│   ├── mfa_audit.ps1
│   ├── MFA_AuthMethod.ps1
│   └── MgGraphUserCreation.ps1
├── themes/
│   └── terminal.tcss                # Terminal UI styling (Textual CSS)
├── logs/                            # Application logs (auto-created)
├── requirements.txt                 # Python dependencies (I'm using uv, you can 100% use pip normally)
└── README.md                        # This file
```

## Output and Reports

All reports are automatically saved to:
- **Linux/macOS**: `~/Documents/M365Reports/`
- **Windows**: `%USERPROFILE%\Documents\M365Reports\`

Report files include timestamps and are in CSV format for easy analysis.

Application logs are saved to the `logs/` directory in the project root.

## Security Considerations

### OAuth2 with MFA
- All scripts use interactive OAuth2 authentication
- No credentials are stored in the application
- MFA challenges are handled by Microsoft's authentication flow
- Token caching is managed by PowerShell modules

### Logging
- Sensitive information (passwords) is never logged
- All operations are logged with timestamps
- Logs include user context and operation results

### Permissions Required
Your admin account needs these roles:
- **User Administrator** or **Global Administrator** (for user creation)
- **Exchange Administrator** (for mailbox operations)
- **Security Reader** or **Global Reader** (for MFA/auth reports)

## Troubleshooting

### "PowerShell (pwsh) not found"
- Install PowerShell Core (see Prerequisites)
- Verify with: `pwsh --version`

### "Failed to import modules"
- Run PowerShell as admin and install modules:
  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser -Force
  Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
  ```

### Authentication Issues
- Clear cached credentials:
  ```powershell
  Disconnect-MgGraph
  Disconnect-ExchangeOnline -Confirm:$false
  ```
- Verify your account has the required admin roles
- Check that your organization allows the required permissions

### Import Errors in Python
- Ensure you're using Python 3.12+: `python --version`
- Reinstall dependencies: `pip install -r requirements.txt --force-reinstall`

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Adding Scripts

New PowerShell scripts placed in the `Scripts/` directory are automatically discovered. Script names are displayed in PascalCase format derived from the filename.

**Script Descriptions:**
- Automatically extracted from the first comment line in each script
- To override, edit `SCRIPT_DESCRIPTIONS` in `lib/script_registry.py`:
```python
SCRIPT_DESCRIPTIONS = {
    "YourScriptName": "Your custom description here",
}
```

**Tip:** Add a descriptive comment at the top of your script for automatic description extraction.

## License

This project is provided as-is for administrative use.

## Disclaimer

This tool performs administrative operations on your Microsoft 365 tenant. Always:
- Test in a non-production environment first
- Review all operations before executing
- Maintain proper backups
- Follow your organization's change management procedures

## Support

For issues and questions:
- Check the Troubleshooting section above
- Review logs in the `logs/` directory
- Open an issue on GitHub

## Roadmap

- Batch processing from CSV for user creation
- Unattended tasks
- Sharepoint Management
- Script favorites/history
- Custom key bindings
- Additional utility switches
- Progress bar
- Custom output options
- PowerShell syntax highlighting in script output window

---

**Built with ❤️ using [Textual](https://textual.textualize.io/)**
 
