# Troubleshooting

## Pre-flight checks

```powershell
pwsh --version          # PowerShell 7+ must be on PATH
go version               # only needed if building from source
```

For specific script categories:

```powershell
# AD / GroupPolicy scripts need RSAT modules
Get-Module -ListAvailable ActiveDirectory, GroupPolicy

# M365 scripts need these
Get-Module -ListAvailable Microsoft.Graph*, ExchangeOnlineManagement
```

---

## Common issues

### "No scripts found in Scripts"

The toolkit exits immediately with this message when it can't find any scripts.

- Run it from the folder that contains `Scripts/`, **or** place `admin-toolkit.exe`
  directly next to the `Scripts/` folder. Discovery checks the current directory first,
  then the directory of the binary.
- Confirm scripts live under `Scripts/<Category>/*.ps1` (a category subfolder is required —
  loose `.ps1` files at the top of `Scripts/` are not discovered).

### A script doesn't appear / has no description or parameters

- The first line should be a `# description` comment (longer than ~10 characters).
- Parameters must be in a `param( ... )` block with `[type]$Name` entries.
  `switch` parameters and a parameter named `OutputDirectory` are intentionally hidden
  from the prompt.

### "pwsh: executable file not found" / script won't launch

PowerShell 7+ isn't installed or isn't on `PATH`. Install it (e.g. `winget install Microsoft.PowerShell`)
and re-check with `pwsh --version`.

### A script fails with "module could not be loaded"

Install the module the script needs (see Pre-flight checks above), for example:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
```

AD and GroupPolicy scripts require RSAT — install the relevant Windows optional features.

### M365 authentication fails

```powershell
Disconnect-MgGraph
Disconnect-ExchangeOnline -Confirm:$false
```

Then re-run. Verify your account holds the required admin roles (User/Exchange/Security
Administrator depending on the operation) and that Conditional Access isn't blocking sign-in.

### Reports aren't where I expect

Scripts default to `~/Documents/AdminToolReports`. Check there, or pass a different
`-OutputDirectory` if the script supports it.

### The build fails

- Ensure Go 1.23+ is installed; Go will fetch the toolchain pinned in `go.mod` automatically.
- From the project root: `go build -o admin-toolkit.exe`.
- If modules look stale: `go mod download` then rebuild.

---

## Test a script directly

To isolate whether a problem is in the script or the TUI, run the script straight from PowerShell
the same way the toolkit does:

```powershell
pwsh -NoProfile -NonInteractive -File .\Scripts\<Category>\<Script>.ps1 -Verbose
```

---

## Still stuck?

Open an issue on GitHub with the error message, the script and parameters you used, and your
OS / PowerShell version (`pwsh --version`).
