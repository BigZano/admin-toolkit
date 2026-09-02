# Exec & I/O Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close four concrete exec/IO hardening gaps in the admin-toolkit TUI: password params leaking onto the child process's argv, parameter-value argument-smuggling, a fragile `cmd /c start` shell-out, and unsanitized external text (script content + subprocess output) reaching the terminal.

**Architecture:** Two new small, single-purpose Go files (`sanitize.go`, `execargs.go`) hold pure, unit-testable helpers. `registry.go` and `main.go` call into them at the points where untrusted data crosses a trust boundary. Four `.ps1` scripts gain a stdin-fallback + direct-`SecureString`-build block in place of binding `-Password`/`-NewPassword` from argv.

**Tech Stack:** Go 1.26 (Bubble Tea/Lip Gloss TUI), `golang.org/x/sys/windows` (already a transitive dependency), PowerShell 7 (`pwsh`).

## Global Constraints

- Windows-only application (per README) — no cross-platform build tags needed anywhere in this plan.
- No new external dependencies: `golang.org/x/sys v0.38.0` is already in `go.mod` as `// indirect`; adding a direct import and running `go mod tidy` promotes it, nothing more.
- Verification gate for every Go task: `go build ./...` and `go vet ./...` must be clean (this repo has no other CI).
- Script edits must preserve existing conventions (from project memory): pwsh 7 only, guarded `Import-Module ... -ErrorAction Stop`, `Write-Log` for all status output, `exit 1` on failure — do not introduce new patterns where the existing one already does the job.
- Non-goals (do not do these in this plan): static content-scanning of adopted `.ps1` files, `#Requires`/module-dependency detection or install prompts, any change to which cmdlets/modules the 101 existing scripts use.

---

### Task 1: `sanitizeText` helper

**Files:**
- Create: `sanitize.go`
- Test: `sanitize_test.go`

**Interfaces:**
- Produces: `func sanitizeText(s string) string` — strips runes `< 0x20`, `== 0x7F`, and `0x80–0x9F`. Used by Task 2 (registry.go) and Task 3 (main.go).

- [ ] **Step 1: Write the failing test**

Create `sanitize_test.go`:

```go
package main

import "testing"

func TestSanitizeText(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"plain text unchanged", "Restarts the print spooler", "Restarts the print spooler"},
		{"strips leading ESC of a CSI sequence", "desc \x1b[2Jtail", "desc [2Jtail"},
		{"strips DEL", "a\x7fb", "ab"},
		{"strips C1 control NEL", "a\u0085b", "ab"},
		{"strips embedded newline and tab", "a\nb\tc", "abc"},
		{"empty string", "", ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := sanitizeText(c.in)
			if got != c.want {
				t.Errorf("sanitizeText(%q) = %q, want %q", c.in, got, c.want)
			}
		})
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test -run TestSanitizeText .`
Expected: FAIL — `undefined: sanitizeText` (compile error; `sanitize.go` doesn't exist yet).

- [ ] **Step 3: Write the implementation**

Create `sanitize.go`:

```go
package main

import "strings"

// sanitizeText strips control characters that could otherwise be
// interpreted as terminal escape sequences (ANSI/CSI, C1 controls) when
// rendered. It operates on decoded runes so multi-byte C1 code points
// (U+0080-U+009F) are matched by value, not by raw UTF-8 byte pattern.
func sanitizeText(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		if r < 0x20 || r == 0x7F || (r >= 0x80 && r <= 0x9F) {
			continue
		}
		b.WriteRune(r)
	}
	return b.String()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test -run TestSanitizeText .`
Expected: PASS (all 6 subtests).

- [ ] **Step 5: Commit**

```bash
git add sanitize.go sanitize_test.go
git commit -m "Add sanitizeText helper to strip control/escape sequences from untrusted text"
```

---

### Task 2: Sanitize script-content-derived text in `registry.go`

**Files:**
- Modify: `registry.go` (`extractDescription`, `extractParams`)
- Test: `registry_test.go`

**Interfaces:**
- Consumes: `sanitizeText(s string) string` from Task 1.

- [ ] **Step 1: Write the failing tests**

Create `registry_test.go`:

```go
package main

import "testing"

func TestExtractDescriptionSanitizesControlChars(t *testing.T) {
	content := "# Restarts the print spooler \x1b[2Jservice\nparam(\n    [string]$ServiceName\n)\n"
	got := extractDescription(content)
	want := "Restarts the print spooler [2Jservice"
	if got != want {
		t.Errorf("extractDescription() = %q, want %q", got, want)
	}
}

func TestExtractParamsSanitizesDefaultValue(t *testing.T) {
	content := "param(\n    [string]$Mode = \"bad\x1b[2Jvalue\"\n)\n"
	params := extractParams(content)
	if len(params) != 1 {
		t.Fatalf("extractParams() returned %d params, want 1", len(params))
	}
	want := "bad[2Jvalue"
	if params[0].Default != want {
		t.Errorf("params[0].Default = %q, want %q", params[0].Default, want)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `go test -run 'TestExtractDescriptionSanitizesControlChars|TestExtractParamsSanitizesDefaultValue' .`
Expected: FAIL on both — `extractDescription()`/`params[0].Default` still contain the raw `\x1b` byte.

- [ ] **Step 3: Apply the fix**

In `registry.go`, `extractDescription`, change:

```go
		if strings.HasPrefix(s, "#") {
			desc := strings.TrimSpace(strings.TrimLeft(s, "#"))
			if len(desc) > 10 {
				return desc
			}
		}
```

to:

```go
		if strings.HasPrefix(s, "#") {
			desc := sanitizeText(strings.TrimSpace(strings.TrimLeft(s, "#")))
			if len(desc) > 10 {
				return desc
			}
		}
```

In `registry.go`, `extractParams`, change:

```go
		paramType, paramName, defaultVal := em[1], em[2], strings.TrimSpace(em[3])
```

to:

```go
		paramType, paramName, defaultVal := em[1], em[2], sanitizeText(strings.TrimSpace(em[3]))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test -run 'TestExtractDescriptionSanitizesControlChars|TestExtractParamsSanitizesDefaultValue' .`
Expected: PASS.

- [ ] **Step 5: Run the full test suite so far**

Run: `go test .`
Expected: PASS (Task 1's tests plus these two).

- [ ] **Step 6: Commit**

```bash
git add registry.go registry_test.go
git commit -m "Sanitize script-content-derived description/default text at parse time"
```

---

### Task 3: Sanitize subprocess stdout/stderr lines in `main.go`

**Files:**
- Modify: `main.go` (`startExec`)

**Interfaces:**
- Consumes: `sanitizeText(s string) string` from Task 1.

No new pure logic here — `sanitizeText` is already tested (Task 1). This task wires it into two existing call sites; verification is `go build`/`go vet` plus one manual check.

- [ ] **Step 1: Apply the fix**

In `main.go`, inside `startExec`, change:

```go
			go func() {
				defer wg.Done()
				sc := bufio.NewScanner(stdout)
				for sc.Scan() {
					ch <- execOutputMsg(sc.Text() + "\n")
				}
			}()
			go func() {
				defer wg.Done()
				sc := bufio.NewScanner(stderr)
				for sc.Scan() {
					ch <- execOutputMsg(dimSt.Render("  "+sc.Text()) + "\n")
				}
			}()
```

to:

```go
			go func() {
				defer wg.Done()
				sc := bufio.NewScanner(stdout)
				for sc.Scan() {
					ch <- execOutputMsg(sanitizeText(sc.Text()) + "\n")
				}
			}()
			go func() {
				defer wg.Done()
				sc := bufio.NewScanner(stderr)
				for sc.Scan() {
					ch <- execOutputMsg(dimSt.Render("  "+sanitizeText(sc.Text())) + "\n")
				}
			}()
```

- [ ] **Step 2: Build and vet**

Run: `go build ./... && go vet ./...`
Expected: clean, no errors.

- [ ] **Step 3: Manual verification**

Run the app (`go run .`), pick any script with no required params (e.g. a SystemInventory script), and confirm output still streams into the right pane normally. Then verify the escape-sequence case specifically:

```powershell
pwsh -NoProfile -Command "Write-Output ('desc ' + [char]27 + '[2Jtail')"
```

confirms `pwsh` will actually emit a raw ESC byte on stdout when asked to. Temporarily add a line like `Write-Output ('probe ' + [char]27 + '[2Jtail')` to the top of any existing script's body, run it through the TUI, and confirm the output pane shows the literal text `probe [2Jtail` (ESC stripped, rest inert) rather than clearing the screen or otherwise manipulating the terminal. Remove the temporary line afterward.

- [ ] **Step 4: Commit**

```bash
git add main.go
git commit -m "Sanitize subprocess stdout/stderr lines before rendering"
```

---

### Task 4: `buildArgs` colon-syntax helper

**Files:**
- Create: `execargs.go`
- Test: `execargs_test.go`

**Interfaces:**
- Produces: `func buildArgs(params map[string]string) []string` — returns one `"-Name:value"` token per entry. Used by Task 6 (`startExec`).

- [ ] **Step 1: Write the failing tests**

Create `execargs_test.go`:

```go
package main

import (
	"sort"
	"testing"
)

func TestBuildArgsUsesColonSyntax(t *testing.T) {
	params := map[string]string{
		"Username": "jsmith",
		"Force":    "true",
	}
	got := buildArgs(params)
	sort.Strings(got)
	want := []string{"-Force:true", "-Username:jsmith"}
	if len(got) != len(want) {
		t.Fatalf("buildArgs() = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("buildArgs() = %v, want %v", got, want)
		}
	}
}

func TestBuildArgsPreservesSwitchLikeValue(t *testing.T) {
	params := map[string]string{"ComputerName": "-NotASwitch"}
	got := buildArgs(params)
	want := "-ComputerName:-NotASwitch"
	if len(got) != 1 || got[0] != want {
		t.Fatalf("buildArgs() = %v, want [%q]", got, want)
	}
}

func TestBuildArgsEmpty(t *testing.T) {
	got := buildArgs(map[string]string{})
	if len(got) != 0 {
		t.Fatalf("buildArgs() = %v, want empty", got)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `go test -run TestBuildArgs .`
Expected: FAIL — `undefined: buildArgs`.

- [ ] **Step 3: Write the implementation**

Create `execargs.go`:

```go
package main

// buildArgs converts a map of parameter name/value pairs into PowerShell
// colon-syntax argument tokens ("-Name:value"). The colon form forces
// PowerShell's parameter binder to treat everything after the colon as the
// value, even if it looks like a switch (e.g. "-Force"), closing off
// argument-smuggling via a crafted parameter value.
func buildArgs(params map[string]string) []string {
	args := make([]string, 0, len(params))
	for k, v := range params {
		args = append(args, "-"+k+":"+v)
	}
	return args
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test -run TestBuildArgs .`
Expected: PASS (all 3 subtests).

- [ ] **Step 5: Commit**

```bash
git add execargs.go execargs_test.go
git commit -m "Add buildArgs helper for colon-syntax PowerShell argument binding"
```

---

### Task 5: Split `collectValues` into args/secrets, add `clearSecretInputs`

**Files:**
- Modify: `main.go` (`collectValues`, add `clearSecretInputs`)
- Test: `main_test.go`

**Interfaces:**
- Produces: `func (m model) collectValues() (args map[string]string, secrets []string)` (replaces the old `func (m model) collectValues() map[string]string`).
- Produces: `func (m *model) clearSecretInputs()`.
- Consumes: `ScriptParam.Password bool` (already exists in `registry.go`).
- Used by: Task 6 (`updateConfirm`, `startExec`).

- [ ] **Step 1: Write the failing tests**

Create `main_test.go`:

```go
package main

import (
	"testing"

	"github.com/charmbracelet/bubbles/textinput"
)

func newTestModel(params []ScriptParam, values []string) model {
	inputs := make([]textinput.Model, len(params))
	for i := range params {
		ti := textinput.New()
		ti.SetValue(values[i])
		inputs[i] = ti
	}
	return model{
		curScript: &ScriptInfo{Params: params},
		inputs:    inputs,
	}
}

func TestCollectValuesSeparatesSecretsFromArgs(t *testing.T) {
	params := []ScriptParam{
		{Name: "Username", Password: false},
		{Name: "NewPassword", Password: true},
	}
	m := newTestModel(params, []string{"jsmith", "hunter2"})

	args, secrets := m.collectValues()

	if args["Username"] != "jsmith" {
		t.Errorf("args[Username] = %q, want %q", args["Username"], "jsmith")
	}
	if _, ok := args["NewPassword"]; ok {
		t.Errorf("args contains NewPassword, want it excluded from argv")
	}
	if len(secrets) != 1 || secrets[0] != "hunter2" {
		t.Errorf("secrets = %v, want [hunter2]", secrets)
	}
}

func TestCollectValuesKeepsSecretPositionEvenWhenBlank(t *testing.T) {
	params := []ScriptParam{
		{Name: "FirstSecret", Password: true},
		{Name: "SecondSecret", Password: true},
	}
	m := newTestModel(params, []string{"", "second"})

	_, secrets := m.collectValues()

	if len(secrets) != 2 {
		t.Fatalf("secrets = %v, want 2 entries (positional protocol requires one per password param)", secrets)
	}
	if secrets[0] != "" || secrets[1] != "second" {
		t.Errorf("secrets = %v, want [\"\", \"second\"]", secrets)
	}
}

func TestClearSecretInputsBlanksOnlyPasswordFields(t *testing.T) {
	params := []ScriptParam{
		{Name: "Username", Password: false},
		{Name: "NewPassword", Password: true},
	}
	m := newTestModel(params, []string{"jsmith", "hunter2"})

	m.clearSecretInputs()

	if m.inputs[0].Value() != "jsmith" {
		t.Errorf("non-secret input was cleared: %q", m.inputs[0].Value())
	}
	if m.inputs[1].Value() != "" {
		t.Errorf("secret input was not cleared: %q", m.inputs[1].Value())
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `go test -run 'TestCollectValues|TestClearSecretInputs' .`
Expected: FAIL — compile error, `collectValues` returns one value not two, `clearSecretInputs` undefined.

- [ ] **Step 3: Apply the fix**

In `main.go`, change:

```go
func (m model) collectValues() map[string]string {
	vals := make(map[string]string)
	for i, param := range m.curScript.Params {
		v := strings.TrimSpace(m.inputs[i].Value())
		if v == "" {
			v = param.Default
		}
		if v != "" {
			vals[param.Name] = v
		}
	}
	return vals
}
```

to:

```go
func (m model) collectValues() (args map[string]string, secrets []string) {
	args = make(map[string]string)
	for i, param := range m.curScript.Params {
		v := strings.TrimSpace(m.inputs[i].Value())
		if v == "" {
			v = param.Default
		}
		if param.Password {
			secrets = append(secrets, v)
			continue
		}
		if v != "" {
			args[param.Name] = v
		}
	}
	return args, secrets
}

// clearSecretInputs blanks any password-flagged input field once its value
// has been handed off to the child process. The TUI process outlives the
// child by the rest of the session, so leaving the plaintext in a live
// textinput.Model would be a bigger exposure window than anything on the
// child's side.
func (m *model) clearSecretInputs() {
	for i, param := range m.curScript.Params {
		if param.Password {
			m.inputs[i].SetValue("")
		}
	}
}
```

Note: this change alone will not compile yet — `updateConfirm` and `startExec` still call the old one-return-value signature. That wiring is Task 6. For this task, temporarily confirm the new functions compile in isolation by running `go vet .` and expecting it to report the call-site mismatch in `updateConfirm` (not a new bug — expected until Task 6 lands). Do not modify `updateConfirm`/`startExec` in this task.

- [ ] **Step 4: Run the package tests directly (bypassing the known call-site break)**

Since `go test .` will fail to build the whole package until Task 6 fixes the call site, run just this task's new test file plus its dependency to confirm the logic itself is correct before wiring:

Run: `go build ./... 2>&1 | head -20` (or view full output) — expect exactly one error, from `updateConfirm`'s call to `m.collectValues()` and `m.startExec(m.curScript, params)`, e.g. `assignment mismatch: 1 variable but m.collectValues returns 2 values`. No other errors.

This confirms the only breakage is the known, expected call site — proceed to Task 6 immediately (these two tasks are not independently shippable; Task 6 completes the wiring in the same work session).

- [ ] **Step 5: Commit**

```bash
git add main.go main_test.go
git commit -m "Split collectValues into args/secrets and add clearSecretInputs (call sites updated in next commit)"
```

---

### Task 6: Wire secret delivery + colon-syntax argv into `startExec`

**Files:**
- Modify: `main.go` (`updateConfirm`, `startExec`)

**Interfaces:**
- Consumes: `buildArgs` (Task 4), `m.collectValues() (map[string]string, []string)` and `m.clearSecretInputs()` (Task 5).

- [ ] **Step 1: Update `updateConfirm`'s call site**

In `main.go`, change:

```go
func (m model) updateConfirm(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "enter":
		params := m.collectValues()
		return m, m.startExec(m.curScript, params)
```

to:

```go
func (m model) updateConfirm(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "enter":
		args, secrets := m.collectValues()
		m.clearSecretInputs()
		return m, m.startExec(m.curScript, args, secrets)
```

- [ ] **Step 2: Rewrite `startExec`**

In `main.go`, change:

```go
func (m *model) startExec(script *ScriptInfo, params map[string]string) tea.Cmd {
	m.outLines = nil
	m.outError = ""
	m.execCh = make(chan execOutputMsg, 64)
	m.state = stateExecuting
	m.vp.SetContent(runningSt.Render("Running " + displayName(script.Name) + "...\n"))

	ch := m.execCh
	return tea.Batch(
		listenExec(ch),
		func() tea.Msg {
			args := []string{"-NoProfile", "-NonInteractive", "-File", script.Path}
			for k, v := range params {
				args = append(args, "-"+k, v)
			}
			cmd := exec.Command("pwsh", args...)
			stdout, _ := cmd.StdoutPipe()
			stderr, _ := cmd.StderrPipe()
			if err := cmd.Start(); err != nil {
				close(ch)
				return execDoneMsg{exitCode: 1, err: err}
			}
			var wg sync.WaitGroup
```

to:

```go
func (m *model) startExec(script *ScriptInfo, args map[string]string, secrets []string) tea.Cmd {
	m.outLines = nil
	m.outError = ""
	m.execCh = make(chan execOutputMsg, 64)
	m.state = stateExecuting
	m.vp.SetContent(runningSt.Render("Running " + displayName(script.Name) + "...\n"))

	ch := m.execCh
	return tea.Batch(
		listenExec(ch),
		func() tea.Msg {
			cmdArgs := []string{"-NoProfile", "-NonInteractive", "-File", script.Path}
			cmdArgs = append(cmdArgs, buildArgs(args)...)
			cmd := exec.Command("pwsh", cmdArgs...)
			stdin, _ := cmd.StdinPipe()
			stdout, _ := cmd.StdoutPipe()
			stderr, _ := cmd.StderrPipe()
			if err := cmd.Start(); err != nil {
				close(ch)
				return execDoneMsg{exitCode: 1, err: err}
			}
			// Secrets are one short line each; writing them before the
			// stdout/stderr readers start can't deadlock on pipe-buffer
			// limits at this size.
			for _, secret := range secrets {
				b := []byte(secret + "\n")
				stdin.Write(b)
				for i := range b {
					b[i] = 0
				}
			}
			stdin.Close()
			var wg sync.WaitGroup
```

The rest of the function (the two scanner goroutines, `wg.Wait()`, `cmd.Wait()`, the exit-code handling) is unchanged from Task 3's version — only the signature, the `args`/`cmdArgs` construction, and the new `stdin`/secrets block change.

- [ ] **Step 3: Build and vet**

Run: `go build ./... && go vet ./...`
Expected: clean — this resolves the call-site mismatch left open at the end of Task 5.

- [ ] **Step 4: Run the full test suite**

Run: `go test .`
Expected: PASS — all tests from Tasks 1, 2, 4, and 5.

- [ ] **Step 5: Manual verification (non-secret path)**

Run `go run .`, execute any script that takes at least one non-password string parameter (e.g. an ActiveDirectory or Networking script with a `-ComputerName`-style param), and confirm it still runs successfully end-to-end with the colon-syntax argv change — output streams, exit code handling still shows success/failure correctly.

- [ ] **Step 6: Commit**

```bash
git add main.go
git commit -m "Deliver password params via stdin instead of argv; use colon-syntax for all params"
```

---

### Task 7: Update the 4 password-taking scripts

**Files:**
- Modify: `Scripts/ActiveDirectory/Reset-UserPassword.ps1`
- Modify: `Scripts/Helpdesk/Reset-AccountFull.ps1`
- Modify: `Scripts/Helpdesk/New-OnboardUser.ps1`
- Modify: `Scripts/M365/MgGraphUserCreation.ps1`

**Interfaces:**
- Consumes: Task 6's stdin-delivery contract — the TUI writes exactly one line (possibly empty) per `Password`-flagged param, in `ScriptParam` order, then closes stdin.
- Design note used throughout this task: check `[Console]::IsInputRedirected` before attempting the blocking stdin read. When the TUI runs the script, stdin is always a redirected pipe (`IsInputRedirected` is `$true`), so the read completes immediately (even if the line is empty). When a human runs the script directly from a real console with no `-Password`/`-NewPassword` and nothing piped, `IsInputRedirected` is `$false`, so the script skips the blocking read entirely instead of hanging — preserving today's direct-invocation behavior exactly.

- [ ] **Step 1: `Reset-UserPassword.ps1` — make the param optional**

Change:

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$true)]
    [string]$NewPassword,
    [Parameter(Mandatory=$false)]
    [string]$ForceChangeAtLogon = "true"
)
```

to:

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$false)]
    [string]$NewPassword = "",
    [Parameter(Mandatory=$false)]
    [string]$ForceChangeAtLogon = "true"
)
```

- [ ] **Step 2: `Reset-UserPassword.ps1` — build the SecureString from stdin when needed**

Change:

```powershell
try {
    $securePassword = ConvertTo-SecureString $NewPassword -AsPlainText -Force
    Set-ADAccountPassword -Identity $Username -NewPassword $securePassword -Reset -ErrorAction Stop
} catch {
    Write-Log "Failed to reset password: $($_.Exception.Message)" "Red"
    exit 1
}
```

to:

```powershell
if (-not $NewPassword -and [Console]::IsInputRedirected) {
    # Piped by the TUI: build the SecureString directly from stdin so a
    # full plaintext copy of the password never exists in this process.
    $securePassword = New-Object System.Security.SecureString
    while (($ch = [Console]::In.Read()) -notin -1, 13, 10) { $securePassword.AppendChar([char]$ch) }
    $securePassword.MakeReadOnly()
} elseif ($NewPassword) {
    $securePassword = ConvertTo-SecureString $NewPassword -AsPlainText -Force
} else {
    Write-Log "No new password supplied (use -NewPassword, or pipe one via stdin)." "Red"
    exit 1
}

try {
    Set-ADAccountPassword -Identity $Username -NewPassword $securePassword -Reset -ErrorAction Stop
} catch {
    Write-Log "Failed to reset password: $($_.Exception.Message)" "Red"
    exit 1
}
```

- [ ] **Step 3: `Reset-AccountFull.ps1` — build the SecureString up front, branch on its length**

The param block already has `[string]$NewPassword = ""` (`Mandatory=$false`) — no change needed there.

Change:

```powershell
# Reset password if provided
if (-not [string]::IsNullOrEmpty($NewPassword)) {
    $pwReset = $false
    try {
        $secure = ConvertTo-SecureString $NewPassword -AsPlainText -Force
        Set-ADAccountPassword -Identity $Username -NewPassword $secure -Reset -ErrorAction Stop
        $pwReset = $true
    } catch {
        Write-Log "Failed to reset password: $($_.Exception.Message)" "Red"
        $hadError = $true
    }

    if ($pwReset) {
        $mustChange = $ForceChangeAtLogon -eq "true" -or $ForceChangeAtLogon -eq "1"
        if ($mustChange) {
            try {
                Set-ADUser -Identity $Username -ChangePasswordAtLogon $true -ErrorAction Stop
                Write-Log "Password reset. User must change at next logon." "Green"
                $actions.Add("Password reset (force change)")
            } catch {
                Write-Log "Password was reset, but failed to set change-at-logon flag: $($_.Exception.Message)" "Red"
                $actions.Add("Password reset (change-at-logon flag FAILED)")
                $hadError = $true
            }
        } else {
            Write-Log "Password reset." "Green"
            $actions.Add("Password reset")
        }
    }
} else {
    Write-Log "No new password provided — password not changed." "Yellow"
}
```

to:

```powershell
# Build the secure password up front — from -NewPassword if given, or piped
# via stdin by the TUI (so a full plaintext copy never exists in this
# process). A direct/interactive run with neither yields an empty
# SecureString, treated the same as "not provided" below — password reset
# is an optional step in this script (unlock/status-check can run without it).
if (-not $NewPassword -and [Console]::IsInputRedirected) {
    $secure = New-Object System.Security.SecureString
    while (($ch = [Console]::In.Read()) -notin -1, 13, 10) { $secure.AppendChar([char]$ch) }
    $secure.MakeReadOnly()
} elseif ($NewPassword) {
    $secure = ConvertTo-SecureString $NewPassword -AsPlainText -Force
} else {
    $secure = New-Object System.Security.SecureString
}

# Reset password if provided
if ($secure.Length -gt 0) {
    $pwReset = $false
    try {
        Set-ADAccountPassword -Identity $Username -NewPassword $secure -Reset -ErrorAction Stop
        $pwReset = $true
    } catch {
        Write-Log "Failed to reset password: $($_.Exception.Message)" "Red"
        $hadError = $true
    }

    if ($pwReset) {
        $mustChange = $ForceChangeAtLogon -eq "true" -or $ForceChangeAtLogon -eq "1"
        if ($mustChange) {
            try {
                Set-ADUser -Identity $Username -ChangePasswordAtLogon $true -ErrorAction Stop
                Write-Log "Password reset. User must change at next logon." "Green"
                $actions.Add("Password reset (force change)")
            } catch {
                Write-Log "Password was reset, but failed to set change-at-logon flag: $($_.Exception.Message)" "Red"
                $actions.Add("Password reset (change-at-logon flag FAILED)")
                $hadError = $true
            }
        } else {
            Write-Log "Password reset." "Green"
            $actions.Add("Password reset")
        }
    }
} else {
    Write-Log "No new password provided — password not changed." "Yellow"
}
```

- [ ] **Step 4: `New-OnboardUser.ps1` — make the param optional**

Change:

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$FirstName,
    [Parameter(Mandatory=$true)]
    [string]$LastName,
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$true)]
    [string]$Password,
    [Parameter(Mandatory=$false)]
    [string]$Title = "",
    [Parameter(Mandatory=$false)]
    [string]$Department = "",
    [Parameter(Mandatory=$false)]
    [string]$TargetOU = "",
    [Parameter(Mandatory=$false)]
    [string]$TemplateUser = ""
)
```

to:

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$FirstName,
    [Parameter(Mandatory=$true)]
    [string]$LastName,
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$false)]
    [string]$Password = "",
    [Parameter(Mandatory=$false)]
    [string]$Title = "",
    [Parameter(Mandatory=$false)]
    [string]$Department = "",
    [Parameter(Mandatory=$false)]
    [string]$TargetOU = "",
    [Parameter(Mandatory=$false)]
    [string]$TemplateUser = ""
)
```

- [ ] **Step 5: `New-OnboardUser.ps1` — build the SecureString before account creation**

Change:

```powershell
# ── Create the account ────────────────────────────────────────────────────────
Write-Log "Creating AD account..." "Cyan"
try {
    $params = @{
        SamAccountName        = $Username
        UserPrincipalName     = $upn
        Name                  = $displayName
        GivenName             = $FirstName
        Surname               = $LastName
        DisplayName           = $displayName
        AccountPassword       = (ConvertTo-SecureString $Password -AsPlainText -Force)
        Enabled               = $true
        ChangePasswordAtLogon = $true
        Path                  = $ou
    }
```

to:

```powershell
if (-not $Password -and [Console]::IsInputRedirected) {
    $secure = New-Object System.Security.SecureString
    while (($ch = [Console]::In.Read()) -notin -1, 13, 10) { $secure.AppendChar([char]$ch) }
    $secure.MakeReadOnly()
} elseif ($Password) {
    $secure = ConvertTo-SecureString $Password -AsPlainText -Force
} else {
    Write-Log "No password supplied (use -Password, or pipe one via stdin)." "Red"
    exit 1
}

# ── Create the account ────────────────────────────────────────────────────────
Write-Log "Creating AD account..." "Cyan"
try {
    $params = @{
        SamAccountName        = $Username
        UserPrincipalName     = $upn
        Name                  = $displayName
        GivenName             = $FirstName
        Surname               = $LastName
        DisplayName           = $displayName
        AccountPassword       = $secure
        Enabled               = $true
        ChangePasswordAtLogon = $true
        Path                  = $ou
    }
```

- [ ] **Step 6: `MgGraphUserCreation.ps1` — build the SecureString from stdin, fix the missing-param check**

Change:

```powershell
# If not listing licenses, ensure required user creation params are present
if (-not $ListLicenses) {
    $missing = @()
    if (-not $DisplayName) { $missing += 'DisplayName' }
    if (-not $UserPrincipalName) { $missing += 'UserPrincipalName' }
    if (-not $UsageLocation) { $missing += 'UsageLocation' }
    if (-not $Password) { $missing += 'Password' }
    if ($missing.Count -gt 0) {
        Write-Log "FATAL: Missing required parameters: $($missing -join ', ')" "Red"
        Write-Log "SOLUTION: Provide all mandatory fields for user creation or use -ListLicenses mode." "Yellow"
        exit 1
    }
}

# Validate UsageLocation format (should be 2-letter ISO code)
if (-not $ListLicenses -and $UsageLocation.Length -ne 2) {
    Write-Log "FATAL: UsageLocation must be a 2-letter ISO country code (e.g., 'US', 'GB', 'CA')" "Red"
    Write-Log "SOLUTION: Provide a valid ISO 3166-1 alpha-2 country code" "Yellow"
    exit 1
}
if (-not $ListLicenses) { $UsageLocation = $UsageLocation.ToUpper() }

# Convert user password to SecureString (no admin password needed with OAuth)
if (-not $ListLicenses) {
    Write-Log "Converting user password to secure format..." "Yellow"
    $secureUserPassword = ConvertTo-SecureString $Password -AsPlainText -Force
    # Clear plain text password from memory
    $Password = $null
    [System.GC]::Collect()
}
```

to:

```powershell
# If not listing licenses, ensure required user creation params are present.
# Password is checked for availability (argv OR a redirected stdin the TUI
# will pipe it through), not for an already-nonempty value — it's converted
# to a SecureString further down, after this check.
if (-not $ListLicenses) {
    $missing = @()
    if (-not $DisplayName) { $missing += 'DisplayName' }
    if (-not $UserPrincipalName) { $missing += 'UserPrincipalName' }
    if (-not $UsageLocation) { $missing += 'UsageLocation' }
    if (-not $Password -and -not [Console]::IsInputRedirected) { $missing += 'Password' }
    if ($missing.Count -gt 0) {
        Write-Log "FATAL: Missing required parameters: $($missing -join ', ')" "Red"
        Write-Log "SOLUTION: Provide all mandatory fields for user creation or use -ListLicenses mode." "Yellow"
        exit 1
    }
}

# Validate UsageLocation format (should be 2-letter ISO code)
if (-not $ListLicenses -and $UsageLocation.Length -ne 2) {
    Write-Log "FATAL: UsageLocation must be a 2-letter ISO country code (e.g., 'US', 'GB', 'CA')" "Red"
    Write-Log "SOLUTION: Provide a valid ISO 3166-1 alpha-2 country code" "Yellow"
    exit 1
}
if (-not $ListLicenses) { $UsageLocation = $UsageLocation.ToUpper() }

# Build the secure password (from -Password, or piped via stdin by the TUI)
if (-not $ListLicenses) {
    Write-Log "Converting user password to secure format..." "Yellow"
    $secureUserPassword = New-Object System.Security.SecureString
    if (-not $Password -and [Console]::IsInputRedirected) {
        while (($ch = [Console]::In.Read()) -notin -1, 13, 10) { $secureUserPassword.AppendChar([char]$ch) }
    } elseif ($Password) {
        $secureUserPassword = ConvertTo-SecureString $Password -AsPlainText -Force
    }
    $secureUserPassword.MakeReadOnly()
    $Password = $null
    [System.GC]::Collect()
    if ($secureUserPassword.Length -eq 0) {
        Write-Log "FATAL: No password supplied (use -Password, or pipe one via stdin)." "Red"
        exit 1
    }
}
```

Leave the rest of `MgGraphUserCreation.ps1` (the `SecureStringToBSTR` → use → `ZeroFreeBSTR`-in-`finally` block at lines 241–288) unchanged — it already correctly handles the one point where this script needs a genuine plaintext copy, for the Graph REST call.

- [ ] **Step 7: Parse-check all 4 scripts (no AD/Graph connection required)**

Run this for each of the 4 files, substituting the path:

```powershell
pwsh -NoProfile -Command "$errors = $null; [void][System.Management.Automation.Language.Parser]::ParseFile('Scripts/ActiveDirectory/Reset-UserPassword.ps1', [ref]$null, [ref]$errors); if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host $_.Message } } else { Write-Host 'OK' }"
```

Repeat with `Scripts/Helpdesk/Reset-AccountFull.ps1`, `Scripts/Helpdesk/New-OnboardUser.ps1`, `Scripts/M365/MgGraphUserCreation.ps1`.

Expected: `OK` for all 4 — this confirms the edits are syntactically valid PowerShell without needing a real AD/Graph connection.

- [ ] **Step 8: Manual end-to-end verification (requires a real AD test account / Graph tenant)**

For each of the 4 scripts, run it through the TUI against a real (test) target, and while it's running, capture the child process's command line from a second window:

```powershell
Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" | Select-Object ProcessId, CommandLine
```

Confirm no password value appears in `CommandLine` for any running `pwsh.exe` instance, and confirm the script still completes its intended action (password actually reset / account actually created) — this second part depends on having a test AD/tenant available; if none is available yet, note it as outstanding per the project's existing "no test env for AD scripts" gap and defer to when one exists.

- [ ] **Step 9: Commit**

```bash
git add Scripts/ActiveDirectory/Reset-UserPassword.ps1 Scripts/Helpdesk/Reset-AccountFull.ps1 Scripts/Helpdesk/New-OnboardUser.ps1 Scripts/M365/MgGraphUserCreation.ps1
git commit -m "Deliver passwords via stdin/SecureString instead of binding from argv"
```

---

### Task 8: Replace `cmd /c start` with `windows.ShellExecute`

**Files:**
- Modify: `main.go` (`openInEditor`)
- Modify: `go.mod`, `go.sum` (via `go mod tidy`)

**Interfaces:** none consumed from other tasks; fully independent.

- [ ] **Step 1: Apply the fix**

In `main.go`, change:

```go
func openInEditor(path string) {
	exec.Command("cmd", "/c", "start", "", path).Start()
}
```

to:

```go
func openInEditor(path string) {
	verb, err := windows.UTF16PtrFromString("open")
	if err != nil {
		return
	}
	file, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return
	}
	_ = windows.ShellExecute(0, verb, file, nil, nil, windows.SW_SHOWNORMAL)
}
```

Add `"golang.org/x/sys/windows"` to the import block at the top of `main.go`.

- [ ] **Step 2: Promote the dependency from indirect to direct**

Run: `go mod tidy`
Expected: `go.mod`'s `golang.org/x/sys v0.38.0` line moves out of the `// indirect` block into the direct `require` block (or its own `require` line). `go.sum` may pick up no changes, or minor changes, since the module was already present.

- [ ] **Step 3: Build and vet**

Run: `go build ./... && go vet ./...`
Expected: clean.

- [ ] **Step 4: Manual verification**

Run `go run .`, select any script, press `e`. Confirm the script opens in your default `.ps1` editor/handler exactly as before. Then specifically test the injection-shaped case: adopt (`a`) a copy of any script renamed to include `&` and `%`, e.g. `Test & Report.ps1`, then select it and press `e`. Confirm it simply opens in the editor with no unexpected side effect (no new window/process beyond the editor, no command executed).

- [ ] **Step 5: Commit**

```bash
git add main.go go.mod go.sum
git commit -m "Replace cmd /c start with a direct ShellExecute call in openInEditor"
```

---

### Task 9: Final verification pass

**Files:** none modified — this task only verifies prior work.

- [ ] **Step 1: Full build/vet/test**

Run: `go build ./... && go vet ./... && go test ./...`
Expected: all clean/passing.

- [ ] **Step 2: Re-run the manual checks from Tasks 3, 6, 7, and 8 in one sitting**

Confirm together: normal script execution still streams output and reports success/failure correctly (Task 6); the ESC-byte probe still renders as inert text (Task 3); a script adopted with `&`/`%` in its filename still opens cleanly via `e` (Task 8); and, when a real AD/Graph test target is available, the 4 password scripts complete successfully with no secret visible in `Get-CimInstance Win32_Process` output during the run (Task 7).

- [ ] **Step 3: No commit needed**

This task verifies already-committed work from Tasks 1–8; nothing new to stage.

---

## Self-Review Notes

- **Spec coverage:** §1 (secret delivery) → Tasks 5, 6, 7. §2 (colon syntax) → Tasks 4, 6. §3 (ShellExecute) → Task 8. §4 (sanitization) → Tasks 1, 2, 3. Spec's Testing section → Steps embedded in Tasks 3, 6, 7 (parse-check), 8, and consolidated in Task 9.
- **Placeholder scan:** no TBD/TODO; the one open item (Task 7 Step 8's real-AD-account verification) is explicitly framed as depending on test-environment availability, matching this project's existing, already-accepted "no test env for AD scripts" gap from prior audits — not a placeholder in the plan itself, all code changes are complete and concrete.
- **Type consistency:** `collectValues() (map[string]string, []string)` (Task 5) matches its call site in `updateConfirm` and `startExec`'s new signature `startExec(script *ScriptInfo, args map[string]string, secrets []string)` (Task 6). `buildArgs(map[string]string) []string` (Task 4) matches its call in `startExec` (Task 6). `sanitizeText(string) string` (Task 1) matches all three call sites (Tasks 2, 3).
