# Admin Toolkit

A fast, keyboard-driven Terminal User Interface (TUI) for running SysAdmin PowerShell
scripts. Built in Go with [Bubble Tea](https://github.com/charmbracelet/bubbletea),
it auto-discovers your PowerShell scripts, organizes them by category, prompts for
parameters in plain language, and streams output live — no menus to maintain, no code
to change when you add a script.

## Features

- **Auto-discovery** — drop a `.ps1` into `Scripts/<Category>/` and it appears instantly
- **Plain-language prompts** — parameters are parsed from each script's `param()` block and shown with friendly labels
- **Two-pane layout** — categories/scripts on the left, live output & details on the right
- **Confirmation step** — review every parameter before a script runs
- **Edit & add in place** — open a script in your editor (`e`) or import an external `.ps1` (`a`) without leaving the TUI
- **Password masking** — fields named like passwords are hidden in the input and confirmation views
- **Reports** — scripts write CSVs to `~/Documents/AdminToolReports`

## Script categories

Scripts ship under `Scripts/<Category>/`. Current categories:

| Category          | Examples                                                            |
|-------------------|--------------------------------------------------------------------|
| ActiveDirectory   | unlock / reset / disable users, stale accounts, group membership   |
| GroupPolicy       | GPO reports, unlinked GPOs, GPO links & permissions                |
| Helpdesk          | onboarding/offboarding, print queue, logged-in users, remote svc   |
| M365              | MFA & auth-method audits, mailbox export, delegate access          |
| Networking        | connectivity & port tests, DNS/DHCP lookups, open ports            |
| Security          | local admins, failed logins, audit/firewall policy, BitLocker      |
| SystemInventory   | system/hardware info, installed software, disk health, updates     |
| FileManagement    | large files, folder sizes & permissions, orphaned profiles         |

## Prerequisites

- **Windows** (the AD, GPO, and editor-launch features target Windows)
- **PowerShell 7+** (`pwsh`) on your `PATH` — verify with `pwsh --version`
- **Module / RSAT requirements depend on which scripts you run:**
  - ActiveDirectory & GroupPolicy scripts → RSAT (`ActiveDirectory`, `GroupPolicy` modules)
  - M365 scripts → `Microsoft.Graph` and `ExchangeOnlineManagement`
    ```powershell
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
    Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
    ```
  - Networking / Security / SystemInventory / FileManagement → built-in Windows cmdlets

## Getting started

### Option A — run the prebuilt binary

Place `admin-toolkit.exe` next to the `Scripts/` folder and run it:

```powershell
.\admin-toolkit.exe
```

The toolkit looks for `Scripts/` in the current directory first, then next to the binary.

### Option B — build from source

Requires [Go](https://go.dev/dl/) 1.23+ (Go will fetch the toolchain pinned in `go.mod` automatically).

```powershell
git clone https://github.com/BigZano/admin-toolkit.git
cd admin-toolkit
go build -o admin-toolkit.exe
.\admin-toolkit.exe
```

For development you can also run without building:

```powershell
go run .
```

## Usage

The TUI has two states — **categories** and **scripts** — plus modals for parameter
entry and confirmation.

### Keyboard shortcuts

| Key            | Action                                              |
|----------------|-----------------------------------------------------|
| `↑` `↓` / `k` `j` | Move selection                                   |
| `Enter`        | Open a category → open the scripts list → run a script |
| `e`            | Edit the selected script in your default editor     |
| `a`            | Add (import) an external `.ps1` into this category  |
| `Esc`          | Back to the previous view / cancel a modal          |
| `Tab` / `Shift+Tab` | Move between parameter fields                   |
| `q` / `Ctrl+C` | Quit                                                |

### Running a script

1. Pick a category, press `Enter`.
2. Pick a script, press `Enter`.
3. If the script has parameters, fill the form — required fields are marked `*`, optional fields show their default.
4. Review the confirmation screen and press `Enter` to run (`r` to go back and edit).
5. Output streams into the right pane. CSV reports (where applicable) are saved to `~/Documents/AdminToolReports`.

## Adding your own scripts

No code changes are needed — the registry auto-discovers anything under `Scripts/<Category>/*.ps1`.

Follow these conventions so the TUI can describe and prompt for your script:

- **Line 1:** a `# description` comment — shown as the script's description.
- **`param()` block:** declare parameters with `[string]` types. Friendly labels are
  derived automatically; common names (e.g. `Username`, `ComputerName`, `DaysInactive`)
  get curated prompts.
- Mark required parameters with `[Parameter(Mandatory=$true)]`, or give optional ones a
  default value.
- An optional `$OutputDirectory` parameter is recognized and hidden from the prompt
  (it defaults to `~/Documents/AdminToolReports`).
- `switch` parameters are skipped in the prompt.

To create a new category, just make a new subfolder under `Scripts/`.

## How it works

- `main.go` — the Bubble Tea model: state machine, views, and script execution (`pwsh -NoProfile -NonInteractive -File <script> -Param value`).
- `registry.go` — discovers scripts, parses descriptions and `param()` blocks, and maps parameter names to friendly labels.
- `styles.go` — Lip Gloss styles for the UI.

## Disclaimer

These scripts perform administrative operations against AD, Microsoft 365, and local/remote
systems. Always test in a non-production environment first, review what a script does before
running it, and follow your organization's change-management process. Scripts you add or edit
are **not** validated or tested by this tool.

## License

See [LICENSE](LICENSE).
