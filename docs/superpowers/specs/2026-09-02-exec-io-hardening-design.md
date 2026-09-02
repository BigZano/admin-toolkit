# Exec & I/O Hardening (sub-project 1 of the TUI robustness pass)

## Purpose

The TUI shells out to `pwsh`/`cmd.exe` and renders text pulled from two untrusted
sources — user-typed parameter values and PowerShell script content (including
content from user-adopted, non-audited `.ps1` files). This spec hardens the
places where that untrusted data crosses a trust boundary: into a child
process's command line, into a child process's memory, or into the terminal
display. It does not cover static content-scanning of adopted scripts for
dangerous patterns (that's a separate sub-project — the "trust scanner").

Four concrete problems, found by inspecting `main.go`/`registry.go` for two
issue classes: (1) the app doing something other than what was intended when
handed adversarial-shaped input, and (2) external data being displayed/handled
without sanitization.

## 1. Secret delivery (password params never touch argv)

**Problem:** `startExec` (main.go:354) builds `args = append(args, "-"+k, v)`
for every collected param, including the 4 scripts with a `Password`-flagged
param (`Reset-UserPassword.ps1`, `Reset-AccountFull.ps1`,
`New-OnboardUser.ps1`, `MgGraphUserCreation.ps1`). Command-line arguments are
visible to any process on the machine via `tasklist`, `Get-Process`, or
`Get-CimInstance Win32_Process`, and are captured by Windows command-line
auditing (Event ID 4688, Sysmon Event ID 1) if an org has that policy enabled.

**Fix:**
- `registry.go`: no changes. It already flags password-like params
  (`Password: true` when the name contains "password") and already marks them
  required when there's no default — the masked input field and the
  bullet-masked confirmation display keep working unchanged.
- `main.go` `startExec`: split collected params into two groups. Non-secret
  params go on argv as `-Name:value` (see §2 — colon syntax, not space
  syntax). Secret params are *not* added to `args`; instead, after
  `cmd.Start()`, write each secret's bytes + `\n` to the child's stdin pipe
  (`cmd.StdinPipe()`), in the order the params appear in `script.Params`,
  then close the pipe.
- The moment a secret has been hand off to the child (written to the pipe),
  clear that field's `textinput.Model` value (`ti.SetValue("")`). This matters
  because the *TUI process* lives for the whole session while the child
  process lives for seconds — without this, the plaintext sits in a live,
  named struct field for the rest of the app's runtime, which is a bigger
  exposure window than anything on the child side.
- Convert the collected secret to `[]byte` once, write it, zero that byte
  slice immediately after the write succeeds, and don't retain a second copy
  in the params map past the point `args`/the stdin payload are built.
- Each of the 4 scripts: change the password param to optional (default
  `""`), and read it from stdin when not bound via argv, building the
  `SecureString` directly rather than materializing a plaintext string:

  ```powershell
  if (-not $Password) {
      $secure = New-Object System.Security.SecureString
      while (($ch = [Console]::In.Read()) -notin -1, 13, 10) { $secure.AppendChar([char]$ch) }
      $secure.MakeReadOnly()
  } else {
      $secure = ConvertTo-SecureString $Password -AsPlainText -Force
  }
  ```
  `[Console]::In` bypasses PowerShell's host-UI layer, so it works under
  `-NonInteractive` (unlike `Read-Host`, which `-NonInteractive` explicitly
  blocks) — verify this against a real `pwsh` process during implementation.
- `Reset-UserPassword.ps1` and `Reset-AccountFull.ps1` pass `$secure`
  directly to `Set-ADAccountPassword -NewPassword` (line 45 / line 100);
  `New-OnboardUser.ps1` passes it as the `AccountPassword` value in the
  `New-ADUser @params` splat (line 79). Both cmdlets accept `SecureString`
  natively — these three never hold a full plaintext copy in the TUI-driven
  path at all.
- `MgGraphUserCreation.ps1`: keep its existing `SecureStringToBSTR` →
  use → `ZeroFreeBSTR`-in-`finally` pattern (lines 242–288) unchanged — it's
  already correct, and a plaintext copy is unavoidable there because Graph's
  REST API requires it on the wire.
- Direct/manual invocation of any of the 4 scripts outside the TUI is
  unaffected (`-Password 'x'` still binds normally via the `else` branch).

**Explicitly rejected** (considered, not worth it):
- Encrypting/obfuscating the stdin pipe transport itself — defeats nothing,
  since an attacker who can read process memory already sees the value at
  point of use.
- `unsafe`-pointer scrubbing of the Go string's backing array — relies on
  undefined-behavior-adjacent assumptions about Go's memory model; marginal
  benefit given the accepted residual risk below.
- A third-party Go secure-memory library (e.g. memguard) — real hardening in
  general, but targets the same accepted residual risk for more complexity
  than this project's size justifies.
- Disabling WER crash dumps or PowerShell logging policy from the TUI —
  machine-wide settings; not this app's business to change silently.

**Accepted residual risk:** a local admin (via `SeDebugPrivilege` +
`ReadProcessMemory`), a debugger attached to one's own process, or EDR
hooking process I/O can still observe the secret. This is unclosable by any
in-process mechanism — it's a statement about what OS memory isolation
protects (peers from each other), not what it protects against (the
machine's own administrator, or yourself). Solving that for real requires
never having plaintext touch the machine as anything but a short-lived vault
token — out of scope for this tool.

## 2. Colon-syntax parameter binding (argument-smuggling)

**Problem:** `-Name value` binding means a value like `-Force` typed into an
unrelated text field can be parsed by PowerShell's parameter binder as a new
switch rather than the previous parameter's value, changing which flags the
script actually runs with.

**Fix:** `startExec` builds every non-secret argument as a single token
`-Name:value` instead of two tokens `-Name`, `value`. The colon form forces
PowerShell to always treat everything after the colon as the value, never as
a new parameter name, regardless of what it looks like.

## 3. Replace `cmd /c start` with a direct ShellExecute call

**Problem:** `openInEditor` (main.go:728) runs
`exec.Command("cmd", "/c", "start", "", path).Start()`. `path`, for an
*adopted* script, is a filename the user pointed the import flow at — content
that may not have originated with the user (downloaded, emailed, copied from
a share). `&`, `%`, and `^` are all legal in Windows filenames, and
`cmd.exe`'s re-tokenizing of the string after `/c` (plus `start`'s own
argument parsing) is the same general shape as a long-running class of
Windows shell-injection bugs. No working exploit against this exact
invocation was demonstrated — cmd.exe's quoting behavior here is genuinely
finicky — but there's a strictly safer option at equal cost, so this gets
fixed regardless of whether this specific shape is provably exploitable.

**Fix:** call `windows.ShellExecute` directly (`golang.org/x/sys/windows` —
already present as a transitive dependency via bubbletea et al., so this adds
no new dependency, just a direct import) instead of shelling through
`cmd.exe`. `ShellExecuteW` takes the path as a discrete parameter, not a
string to be re-tokenized by a command interpreter, which removes the class
of risk rather than arguing about whether this instance of it fires.

## 4. Sanitize untrusted text before it reaches the terminal

**Problem:** Two kinds of external data are rendered into the terminal with
no sanitization: (a) child-process stdout/stderr lines (main.go:134, 389),
and (b) script-content-derived text — `Description` and `Default` values
parsed out of a script's file content (`registry.go` `extractDescription`,
`extractParams`), rendered in the category/script preview panels and the
confirm modal (main.go:544, 560, 646). A script whose content didn't
originate with the user (adopted from elsewhere) could embed ANSI/terminal
control sequences in a comment or a param default to manipulate what's
displayed — spoof a "SUCCESS" line, hide a real error, move the cursor —
before the script has even been run once, or via its live output while
running.

Param *names* and *labels* are not at risk: names are regex-constrained to
`\w+` at extraction time, and labels are either our own hardcoded strings
(`paramLabels`) or derived from those constrained names. Filenames aren't at
risk from this specific class either — Windows disallows ASCII control
characters (0x00–0x1F, which includes ESC/0x1B) in filenames at the API
level, independent of anything this app does.

**Fix:** one shared helper, `sanitizeText(s string) string`, that strips
bytes below 0x20, 0x7F (DEL), and the 0x80–0x9F C1 control range (removing
the leading ESC/C1 byte turns a would-be escape sequence into inert visible
characters). Apply it at two boundaries:
- `registry.go`: on `Description` and each param's `Default` at parse time —
  sanitizing once at the point external file content enters the app's data
  model, rather than at every render call site.
- `main.go`: on each stdout/stderr line before it's appended to `m.outLines`
  (both the stdout branch at line 134 and the stderr branch at line 389).

This is expected to be a no-op for the 101 audited scripts' actual output:
`Write-Host -ForegroundColor` doesn't emit real ANSI codes when stdout is
redirected to a pipe (as it is here, via `cmd.StdoutPipe()`) rather than a
real console, so no legitimate coloring is being stripped today.

## Non-goals for this spec

- Static content-scanning of adopted `.ps1` files for dangerous patterns
  (IEX/download-and-run, obfuscation, etc.) — separate "trust scanner"
  sub-project.
- Runtime/module dependency detection (`#Requires` parsing, install prompts)
  — separate sub-project, follows this one.
- Any change to which cmdlets/modules the 101 existing scripts use.

## Testing

- Manual: run each of the 4 password scripts through the TUI end-to-end
  against a value; confirm via `Get-Process -Id <pid> | Select CommandLine`
  (or a similar tool) taken *during* execution that no secret appears on the
  command line, and confirm the script still succeeds functionally.
- Manual: adopt a script with `&` in its filename; press `e`; confirm it
  opens the editor rather than doing anything unexpected.
- Manual: adopt a script whose first-line comment or a param default embeds
  a raw ESC byte (e.g. `# desc \x1b[2J`); confirm the preview panel shows
  inert text, not a terminal effect.
- `go build` / `go vet` clean, as usual for this repo.
