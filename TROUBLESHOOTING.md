# Troubleshooting Checklist

## Pre-flight Checks

Before running the application, verify:

### System Requirements
- [ ] Python 3.12 or higher installed
  ```bash
  python --version
  ```
- [ ] PowerShell Core installed
  ```bash
  pwsh --version
  ```
- [ ] Git installed (for cloning)
  ```bash
  git --version
  ```

### Dependencies Installed
- [ ] Python packages installed
  ```bash
  pip list | grep textual
  ```
- [ ] PowerShell modules installed
  ```powershell
  pwsh -c "Get-Module -ListAvailable Microsoft.Graph*"
  pwsh -c "Get-Module -ListAvailable ExchangeOnlineManagement"
  ```

### Permissions
- [ ] Admin account has required roles:
  - User Administrator or Global Administrator
  - Exchange Administrator
  - Security Reader or Global Reader

## Common Issues

### Issue: "PowerShell (pwsh) not found"

**Symptoms:**
- Error when running scripts
- "pwsh: command not found"

**Solution:**
```bash
# Ubuntu/Debian
sudo apt-get install powershell

# macOS
brew install --cask powershell

# Verify
pwsh --version
```

---

### Issue: "Failed to import modules"

**Symptoms:**
- "Import-Module: The specified module could not be loaded"
- Script fails at module import

**Solution:**
```powershell
pwsh
Install-Module Microsoft.Graph -Scope CurrentUser -Force
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
exit
```

---

### Issue: "Authentication failed"

**Symptoms:**
- Cannot connect to Microsoft Graph or Exchange Online
- "Access Denied" errors
- MFA prompt doesn't appear

**Solution:**
1. Clear cached credentials:
   ```powershell
   pwsh
   Disconnect-MgGraph
   Disconnect-ExchangeOnline -Confirm:$false
   exit
   ```

2. Verify admin roles in Microsoft 365 Admin Center

3. Check Conditional Access policies aren't blocking sign-in

4. Try incognito/private browsing for authentication

---

### Issue: "Import errors in Python"

**Symptoms:**
- "ModuleNotFoundError: No module named 'textual'"
- "Import "lib.logger" could not be resolved"

**Solution:**
```bash
# Check Python version
python --version

# Reinstall requirements
pip install -r requirements.txt --force-reinstall

# Or use virtual environment
python -m venv venv
source venv/bin/activate  # Linux/Mac
pip install -r requirements.txt
```

---

### Issue: "No such file or directory: Scripts/..."

**Symptoms:**
- Script files not found
- Path errors when running operations

**Solution:**
1. Ensure you're in the project directory:
   ```bash
   cd /path/to/TUI-project
   pwd  # Should show .../TUI-project
   ```

2. Verify Scripts directory exists:
   ```bash
   ls Scripts/
   ```

3. Run from project root:
   ```bash
   python main.py
   ```

---

### Issue: "Insufficient privileges"

**Symptoms:**
- Operations fail with permission errors
- "User does not have permission to access..."

**Solution:**
1. Verify your account has admin roles:
   - Go to Microsoft 365 Admin Center
   - Active users → Your account → Assigned roles
   
2. Required roles by operation:
   - **Create User**: User Administrator or Global Admin
   - **Exchange operations**: Exchange Administrator
   - **MFA Audit**: Security Reader or Global Reader

3. Wait 15-30 minutes after role assignment

---

### Issue: "Script takes too long"

**Symptoms:**
- Operations timeout
- No output for extended periods

**Solution:**
1. Check network connectivity:
   ```bash
   ping graph.microsoft.com
   ```

2. Verify firewall isn't blocking:
   - Port 443 (HTTPS)
   - Microsoft domains

3. For large tenants, operations may take time:
   - MFA Audit: 1-5 minutes per 100 users
   - Mailbox Export: 30-60 seconds per 100 mailboxes

4. Check logs for progress:
   ```bash
   tail -f logs/m365admin_*.log
   ```

---

### Issue: "Report files not generated"

**Symptoms:**
- Script completes but no CSV file
- Can't find output files

**Solution:**
1. Check output directory:
   ```bash
   ls ~/Documents/M365Reports/
   ```

2. Verify directory was created:
   ```bash
   mkdir -p ~/Documents/M365Reports
   ```

3. Check script output for actual save location

4. Look in alternate locations:
   - Current directory: `ls *.csv`
   - User profile: `ls $HOME/*.csv`

---

## Diagnostic Commands

### Check Everything
```bash
# System info
uname -a
python --version
pwsh --version

# Python packages
pip list | grep textual

# PowerShell modules
pwsh -c "Get-Module -ListAvailable | Select-Object Name, Version"

# Directories
ls -la ~/Documents/M365Reports/
ls -la logs/

# Recent logs
tail -20 logs/m365admin_*.log
```

### Test PowerShell Script Manually
```bash
pwsh Scripts/mfa_audit.ps1
```

### Test Python Import
```python
python -c "from lib.logger import get_logger; print('OK')"
python -c "from lib.config import Config; print('OK')"
python -c "from textual.app import App; print('OK')"
```

## Getting More Help

### Review Logs
Logs contain detailed information:
```bash
# View latest log
ls -lt logs/ | head -1
tail -50 logs/m365admin_*.log
```

### Check Script Output
PowerShell scripts have their own logs:
```bash
ls -lt ~/Documents/M365Reports/*.log
```

### Enable Debug Mode
For Python issues:
```bash
python -v main.py 2>&1 | tee debug.log
```

For PowerShell issues:
```powershell
pwsh -NoProfile -File Scripts/script.ps1 -Verbose
```

## Still Having Issues?

1. **Check README.md** - Full documentation
2. **Check QUICKSTART.md** - Setup guide
3. **Check logs/** - Detailed error logs
4. **Check GitHub Issues** - Known issues
5. **Create new issue** - Include:
   - Error message
   - Log excerpts
   - System info (OS, Python version, PowerShell version)
   - Steps to reproduce

## Emergency Reset

If all else fails:
```bash
# Clean Python cache
find . -type d -name __pycache__ -exec rm -rf {} +
find . -type f -name "*.pyc" -delete

# Disconnect PowerShell sessions
pwsh -c "Disconnect-MgGraph; Disconnect-ExchangeOnline -Confirm:\$false"

# Reinstall Python deps
pip uninstall textual textual-dev -y
pip install -r requirements.txt

# Rerun setup
./setup.sh
```

Then try again:
```bash
python main.py
```
