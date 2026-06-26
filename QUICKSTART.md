# Quick Start

## 1. Check prerequisites

You need **PowerShell 7+** on your `PATH`:

```powershell
pwsh --version
```

Depending on which scripts you run, you may also need:

- **AD / GroupPolicy scripts** → RSAT (`ActiveDirectory`, `GroupPolicy` modules)
- **M365 scripts** → `Microsoft.Graph` and `ExchangeOnlineManagement`:
  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser -Force
  Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
  ```

## 2. Get the toolkit

**Prebuilt binary:** put `admin-toolkit.exe` next to the `Scripts/` folder.

**Or build from source** (requires [Go](https://go.dev/dl/) 1.23+):

```powershell
git clone https://github.com/BigZano/admin-toolkit.git
cd admin-toolkit
go build -o admin-toolkit.exe
```

## 3. Run it

```powershell
.\admin-toolkit.exe
```

(or `go run .` during development)

## 4. Drive the UI

| Key            | Action                                      |
|----------------|---------------------------------------------|
| `↑` `↓`        | Move selection                              |
| `Enter`        | Open category → open script → run           |
| `Tab`          | Next parameter field                         |
| `e`            | Edit the selected script                     |
| `a`            | Add an external `.ps1` to the category       |
| `Esc`          | Back / cancel                                |
| `q`            | Quit                                         |

Flow: pick a **category** → pick a **script** → fill the **parameter form**
(required fields marked `*`) → **confirm** → watch output stream in the right pane.

CSV reports are saved to `~/Documents/AdminToolReports`.

## 5. Add your own scripts

Drop a `.ps1` into `Scripts/<Category>/` — it's auto-discovered, no code changes.
Put a `# description` on line 1 and a `param()` block with `[string]` parameters so the
TUI can describe it and prompt correctly. See [README.md](README.md) for full conventions.
