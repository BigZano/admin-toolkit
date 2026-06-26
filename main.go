package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ── States & messages ────────────────────────────────────────────────────────

type appState int

const (
	stateCategories appState = iota
	stateScripts
	stateParamInput
	stateConfirm
	stateExecuting
	stateEditModal  // disclaimer before opening script in editor
	stateAdoptModal // path input + disclaimer for importing a new script
)

type execOutputMsg string
type execDoneMsg struct {
	exitCode int
	err      error
}

// ── Model ────────────────────────────────────────────────────────────────────

type model struct {
	width, height int
	leftW         int // outer left panel width (includes border)

	reg        *Registry
	categories []string
	catIdx     int
	scripts    []*ScriptInfo
	scriptIdx  int

	vp      viewport.Model
	vpReady bool

	state appState

	curScript  *ScriptInfo
	inputs     []textinput.Model
	inputFocus int

	sp       spinner.Model
	execCh   chan execOutputMsg
	outLines []string
	outError string

	notification string

	// adopt-script modal
	adoptInput textinput.Model
	adoptCat   string
	adoptErr   string
}

func newModel(reg *Registry) model {
	sp := spinner.New()
	sp.Spinner = spinner.MiniDot
	sp.Style = runningSt

	return model{
		reg:        reg,
		categories: reg.Categories(),
		sp:         sp,
	}
}

func (m model) Init() tea.Cmd {
	return m.sp.Tick
}

// ── Update ───────────────────────────────────────────────────────────────────

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.leftW = clamp(m.width/4, 26, 36)
		vpW := m.width - m.leftW - 4 // right border + padding
		vpH := m.height - 5           // top/bottom borders + footer
		if vpH < 1 {
			vpH = 1
		}
		if !m.vpReady {
			m.vp = viewport.New(vpW, vpH)
			m.vpReady = true
			m.refreshRight()
		} else {
			m.vp.Width = vpW
			m.vp.Height = vpH
		}
		return m, nil

	case tea.KeyMsg:
		switch m.state {
		case stateCategories:
			return m.updateCategories(msg)
		case stateScripts:
			return m.updateScripts(msg)
		case stateParamInput:
			return m.updateParamInput(msg)
		case stateConfirm:
			return m.updateConfirm(msg)
		case stateExecuting:
			if msg.String() == "ctrl+c" {
				return m, tea.Quit
			}
		case stateEditModal:
			return m.updateEditModal(msg)
		case stateAdoptModal:
			return m.updateAdoptModal(msg)
		}

	case execOutputMsg:
		m.outLines = append(m.outLines, string(msg))
		m.vp.SetContent(strings.Join(m.outLines, ""))
		m.vp.GotoBottom()
		return m, listenExec(m.execCh)

	case execDoneMsg:
		m.state = stateScripts
		if msg.err != nil {
			m.outError = msg.err.Error()
			m.vp.SetContent(errorSt.Render("Error: "+msg.err.Error()) + "\n\n" + strings.Join(m.outLines, ""))
		} else if msg.exitCode != 0 {
			m.vp.SetContent(errorSt.Render(fmt.Sprintf("Exited with code %d\n\n", msg.exitCode)) + strings.Join(m.outLines, ""))
		} else {
			m.vp.SetContent(successSt.Render("Done.\n\n") + strings.Join(m.outLines, ""))
		}
		m.vp.GotoTop()
		return m, nil

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.sp, cmd = m.sp.Update(msg)
		return m, cmd
	}

	return m, nil
}

func (m model) updateCategories(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "up", "k":
		if m.catIdx > 0 {
			m.catIdx--
			m.refreshRight()
		}
	case "down", "j":
		if m.catIdx < len(m.categories)-1 {
			m.catIdx++
			m.refreshRight()
		}
	case "enter", " ":
		m.scripts = m.reg.ScriptsIn(m.categories[m.catIdx])
		m.scriptIdx = 0
		m.state = stateScripts
		m.refreshRight()
	case "a":
		m.adoptCat = m.categories[m.catIdx]
		m.adoptInput, m.adoptErr = newAdoptInput()
		m.state = stateAdoptModal
	case "q", "ctrl+c":
		return m, tea.Quit
	}
	return m, nil
}

func (m model) updateScripts(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "up", "k":
		if m.scriptIdx > 0 {
			m.scriptIdx--
			m.refreshRight()
		}
	case "down", "j":
		if m.scriptIdx < len(m.scripts)-1 {
			m.scriptIdx++
			m.refreshRight()
		}
	case "enter", " ":
		if len(m.scripts) == 0 {
			break
		}
		m.curScript = m.scripts[m.scriptIdx]
		if len(m.curScript.Params) == 0 {
			return m, m.startExec(m.curScript, nil)
		}
		m.inputs = buildInputs(m.curScript)
		m.inputFocus = 0
		if len(m.inputs) > 0 {
			m.inputs[0].Focus()
		}
		m.state = stateParamInput
	case "e":
		if len(m.scripts) > 0 {
			m.state = stateEditModal
		}
	case "a":
		cat := ""
		if m.catIdx < len(m.categories) {
			cat = m.categories[m.catIdx]
		}
		m.adoptCat = cat
		m.adoptInput, m.adoptErr = newAdoptInput()
		m.state = stateAdoptModal
	case "esc":
		m.state = stateCategories
		m.scripts = nil
		m.scriptIdx = 0
		m.refreshRight()
	case "q", "ctrl+c":
		return m, tea.Quit
	}
	return m, nil
}

func (m model) updateParamInput(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.state = stateScripts
		return m, nil
	case "tab", "down":
		m.inputs[m.inputFocus].Blur()
		m.inputFocus = (m.inputFocus + 1) % len(m.inputs)
		m.inputs[m.inputFocus].Focus()
		return m, textinput.Blink
	case "shift+tab", "up":
		m.inputs[m.inputFocus].Blur()
		m.inputFocus = (m.inputFocus - 1 + len(m.inputs)) % len(m.inputs)
		m.inputs[m.inputFocus].Focus()
		return m, textinput.Blink
	case "enter":
		if m.inputFocus < len(m.inputs)-1 {
			m.inputs[m.inputFocus].Blur()
			m.inputFocus++
			m.inputs[m.inputFocus].Focus()
			return m, textinput.Blink
		}
		// Last field: validate and go to confirm
		if missing := m.missingRequired(); len(missing) > 0 {
			m.notification = "Required: " + strings.Join(missing, ", ")
			return m, nil
		}
		m.notification = ""
		m.state = stateConfirm
		return m, nil
	default:
		var cmd tea.Cmd
		m.inputs[m.inputFocus], cmd = m.inputs[m.inputFocus].Update(msg)
		return m, cmd
	}
	return m, nil
}

func (m model) updateConfirm(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "enter":
		params := m.collectValues()
		return m, m.startExec(m.curScript, params)
	case "r":
		m.state = stateParamInput
		if len(m.inputs) > 0 {
			m.inputs[m.inputFocus].Focus()
		}
		return m, textinput.Blink
	case "esc":
		m.state = stateScripts
		m.refreshRight()
		return m, nil
	case "ctrl+c", "q":
		return m, tea.Quit
	}
	return m, nil
}

func (m model) updateExecuting(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	return m, nil
}

func (m model) updateEditModal(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "enter":
		if len(m.scripts) > 0 {
			openInEditor(m.scripts[m.scriptIdx].Path)
		}
		m.state = stateScripts
	case "esc", "q":
		m.state = stateScripts
	}
	return m, nil
}

func (m model) updateAdoptModal(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		if m.state == stateScripts || len(m.scripts) > 0 {
			m.state = stateScripts
		} else {
			m.state = stateCategories
		}
		m.adoptErr = ""
		return m, nil
	case "enter":
		src := strings.TrimSpace(m.adoptInput.Value())
		if src == "" {
			m.adoptErr = "Enter a path to a .ps1 file."
			return m, nil
		}
		if err := adoptScript(src, m.adoptCat, findScriptsDir()); err != nil {
			m.adoptErr = err.Error()
			return m, nil
		}
		// Reload registry and return to whichever view makes sense
		m.reg = NewRegistry(findScriptsDir())
		m.categories = m.reg.Categories()
		m.scripts = m.reg.ScriptsIn(m.adoptCat)
		m.adoptErr = ""
		m.notification = "Script added to " + m.adoptCat
		if len(m.scripts) > 0 {
			m.state = stateScripts
		} else {
			m.state = stateCategories
		}
		m.refreshRight()
		return m, nil
	default:
		var cmd tea.Cmd
		m.adoptInput, cmd = m.adoptInput.Update(msg)
		return m, cmd
	}
	return m, nil
}

// ── Execution ────────────────────────────────────────────────────────────────

func (m *model) startExec(script *ScriptInfo, params map[string]string) tea.Cmd {
	m.outLines = nil
	m.outError = ""
	m.execCh = make(chan execOutputMsg, 64)
	m.state = stateExecuting
	m.vp.SetContent(runningSt.Render("Running "+displayName(script.Name)+"...\n"))

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
			wg.Add(2)
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
			wg.Wait()
			err := cmd.Wait()
			close(ch)
			code := 0
			if err != nil {
				if ex, ok := err.(*exec.ExitError); ok {
					code = ex.ExitCode()
					err = nil // exit code captured; not a launch error
				}
			}
			return execDoneMsg{exitCode: code, err: err}
		},
		m.sp.Tick,
	)
}

func listenExec(ch chan execOutputMsg) tea.Cmd {
	return func() tea.Msg {
		msg, ok := <-ch
		if !ok {
			return nil
		}
		return msg
	}
}

// ── View ─────────────────────────────────────────────────────────────────────

func (m model) View() string {
	if m.width == 0 {
		return ""
	}
	switch m.state {
	case stateParamInput:
		return m.viewModal(m.renderParamModal())
	case stateConfirm:
		return m.viewModal(m.renderConfirmModal())
	case stateEditModal:
		return m.viewModal(m.renderEditModal())
	case stateAdoptModal:
		return m.viewModal(m.renderAdoptModal())
	default:
		return m.viewMain()
	}
}

func (m model) viewMain() string {
	left := m.renderLeft()
	right := m.renderRight()
	panels := lipgloss.JoinHorizontal(lipgloss.Top, left, right)
	footer := m.renderFooter()
	return lipgloss.JoinVertical(lipgloss.Left, panels, footer)
}

func (m model) viewModal(modal string) string {
	return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center, modal)
}

// ── Left panel ───────────────────────────────────────────────────────────────

func (m model) renderLeft() string {
	innerW := m.leftW - 2 // subtract rounded border chars
	innerH := m.height - 5

	var title string
	var items []string

	if m.state == stateCategories || m.state == stateExecuting || m.curScript == nil {
		title = titleSt.Render("Categories")
		for i, cat := range m.categories {
			label := fmt.Sprintf("%s (%d)", cat, len(m.reg.ScriptsIn(cat)))
			if i == m.catIdx && m.state == stateCategories {
				items = append(items, selectedSt.Render(fmt.Sprintf(" %-*s", innerW-1, "> "+label)))
			} else {
				items = append(items, "  "+normalSt.Render(label))
			}
		}
	} else {
		catName := ""
		if len(m.categories) > m.catIdx {
			catName = m.categories[m.catIdx]
		}
		title = titleSt.Render(catName)
		for i, s := range m.scripts {
			dn := displayName(s.Name)
			if i == m.scriptIdx {
				items = append(items, selectedSt.Render(fmt.Sprintf(" %-*s", innerW-1, "> "+dn)))
			} else {
				items = append(items, "  "+normalSt.Render(dn))
			}
		}
	}

	content := title + "\n" + hrSt.Render(strings.Repeat("─", innerW)) + "\n"
	for _, item := range items {
		content += item + "\n"
	}

	return panelSt.
		Width(innerW).
		Height(innerH).
		Render(content)
}

// ── Right panel ──────────────────────────────────────────────────────────────

func (m model) renderRight() string {
	rightW := m.width - m.leftW
	innerW := rightW - 2

	var title string
	if m.state == stateExecuting {
		title = runningSt.Render(m.sp.View() + "  Running " + displayName(m.curScript.Name))
	} else {
		title = titleSt.Render("Output & Details")
	}

	header := title + "\n" + hrSt.Render(strings.Repeat("─", innerW))
	vpView := m.vp.View()

	content := lipgloss.JoinVertical(lipgloss.Left, header, vpView)

	return panelSt.
		Width(innerW).
		Height(m.height - 5).
		Render(content)
}

func (m *model) refreshRight() {
	if !m.vpReady {
		return
	}
	switch m.state {
	case stateCategories:
		m.vp.SetContent(m.buildCatPreview())
	case stateScripts:
		m.vp.SetContent(m.buildScriptPreview())
	}
	m.vp.GotoTop()
}

func (m model) buildCatPreview() string {
	if len(m.categories) == 0 {
		return dimSt.Render("No categories found.")
	}
	cat := m.categories[m.catIdx]
	scripts := m.reg.ScriptsIn(cat)
	var sb strings.Builder
	sb.WriteString(dimSt.Render(fmt.Sprintf("%d scripts\n\n", len(scripts))))
	for _, s := range scripts {
		sb.WriteString(scriptNameSt.Render("  "+displayName(s.Name)) + "\n")
		if s.Description != "" {
			sb.WriteString(scriptDescSt.Render("  "+s.Description) + "\n")
		}
		sb.WriteString("\n")
	}
	sb.WriteString(dimSt.Render("Enter to open"))
	return sb.String()
}

func (m model) buildScriptPreview() string {
	if len(m.scripts) == 0 {
		return ""
	}
	s := m.scripts[m.scriptIdx]
	var sb strings.Builder
	sb.WriteString(scriptNameSt.Render(displayName(s.Name)) + "\n")
	if s.Description != "" {
		sb.WriteString(scriptDescSt.Render(s.Description) + "\n")
	}
	sb.WriteString("\n")
	if len(s.Params) > 0 {
		sb.WriteString(dimSt.Render("Parameters:") + "\n")
		for _, p := range s.Params {
			req := ""
			if p.Required {
				req = requiredSt.Render(" *")
			}
			sb.WriteString(fmt.Sprintf("  %s%s\n", normalSt.Render(p.Label), req))
		}
		sb.WriteString("\n")
	}
	sb.WriteString(dimSt.Render("Enter to run"))
	return sb.String()
}

// ── Footer ───────────────────────────────────────────────────────────────────

func (m model) renderFooter() string {
	var keys string
	switch m.state {
	case stateCategories:
		keys = fkey("↑↓", "navigate") + sep() + fkey("↵", "open") + sep() + fkey("a", "add script") + sep() + fkey("q", "quit")
	case stateScripts:
		keys = fkey("↑↓", "navigate") + sep() + fkey("↵", "run") + sep() + fkey("e", "edit") + sep() + fkey("a", "add script") + sep() + fkey("Esc", "back") + sep() + fkey("q", "quit")
	case stateParamInput:
		keys = fkey("Tab", "next field") + sep() + fkey("↵", "submit") + sep() + fkey("Esc", "cancel")
	case stateConfirm:
		keys = fkey("↵", "confirm") + sep() + fkey("r", "edit") + sep() + fkey("Esc", "cancel")
	case stateEditModal:
		keys = fkey("↵", "open in editor") + sep() + fkey("Esc", "cancel")
	case stateAdoptModal:
		keys = fkey("↵", "add script") + sep() + fkey("Esc", "cancel")
	case stateExecuting:
		keys = runningSt.Render("running — ctrl+c to quit")
	}
	bar := hrSt.Render(strings.Repeat("─", m.width)) + "\n" + footerSt.Render(" "+keys)
	return bar
}

func fkey(key, desc string) string {
	return accentSt.Render(key) + " " + dimSt.Render(desc)
}

func sep() string {
	return dimSt.Render("  ·  ")
}

// ── Parameter modal ──────────────────────────────────────────────────────────

func (m model) renderParamModal() string {
	var sb strings.Builder
	title := modalTitleSt.Render("  " + displayName(m.curScript.Name))
	sb.WriteString(title + "\n")
	sb.WriteString(dimSt.Render(strings.Repeat("─", 52)) + "\n\n")

	for i, param := range m.curScript.Params {
		label := param.Label
		if param.Required {
			label += requiredSt.Render(" *")
		} else {
			label += dimSt.Render(" (optional)")
		}
		sb.WriteString(labelSt.Render(label) + "\n")
		sb.WriteString(m.inputs[i].View() + "\n\n")
	}

	if m.notification != "" {
		sb.WriteString(requiredSt.Render("⚠  "+m.notification) + "\n\n")
	}
	sb.WriteString(dimSt.Render("Tab next  ·  Shift+Tab back  ·  Enter submit  ·  Esc cancel"))

	return modalSt.Width(58).Render(sb.String())
}

func (m model) renderConfirmModal() string {
	var sb strings.Builder
	title := modalTitleSt.Render("  Confirm: " + displayName(m.curScript.Name))
	sb.WriteString(title + "\n")
	sb.WriteString(dimSt.Render(strings.Repeat("─", 52)) + "\n\n")

	for _, param := range m.curScript.Params {
		val := m.inputByName(param.Name)
		if val == "" && param.Default != "" {
			val = param.Default + dimSt.Render(" (default)")
		}
		if val == "" {
			continue
		}
		display := val
		if param.Password {
			display = strings.Repeat("•", len(val))
		}
		sb.WriteString(fmt.Sprintf("  %s  %s\n",
			labelSt.Render(param.Label+":"),
			normalSt.Render(display),
		))
	}

	sb.WriteString("\n" + dimSt.Render("Enter confirm  ·  r edit  ·  Esc cancel"))
	return modalSt.Width(58).Render(sb.String())
}

// ── Input helpers ─────────────────────────────────────────────────────────────

func buildInputs(script *ScriptInfo) []textinput.Model {
	inputs := make([]textinput.Model, len(script.Params))
	for i, p := range script.Params {
		ti := textinput.New()
		ti.Prompt = "  "
		ti.PromptStyle = dimSt
		ti.TextStyle = normalSt
		ti.PlaceholderStyle = dimSt
		ti.CursorStyle = inputActiveSt
		if p.Default != "" {
			ti.Placeholder = p.Default
			ti.SetValue(p.Default)
		} else {
			ti.Placeholder = "enter value"
		}
		if p.Password {
			ti.EchoMode = textinput.EchoPassword
			ti.EchoCharacter = '•'
		}
		ti.CharLimit = 256
		ti.Width = 50
		inputs[i] = ti
	}
	return inputs
}

func (m model) missingRequired() []string {
	var missing []string
	for i, param := range m.curScript.Params {
		if param.Required && strings.TrimSpace(m.inputs[i].Value()) == "" {
			missing = append(missing, param.Label)
		}
	}
	return missing
}

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

func (m model) inputByName(name string) string {
	for i, p := range m.curScript.Params {
		if p.Name == name {
			return strings.TrimSpace(m.inputs[i].Value())
		}
	}
	return ""
}

// ── Edit / Adopt helpers ──────────────────────────────────────────────────────

func openInEditor(path string) {
	exec.Command("cmd", "/c", "start", "", path).Start()
}

func newAdoptInput() (textinput.Model, string) {
	ti := textinput.New()
	ti.Prompt = "  "
	ti.PromptStyle = dimSt
	ti.TextStyle = normalSt
	ti.PlaceholderStyle = dimSt
	ti.CursorStyle = inputActiveSt
	ti.Placeholder = `C:\path\to\script.ps1`
	ti.Width = 52
	ti.CharLimit = 512
	ti.Focus()
	return ti, ""
}

func adoptScript(srcPath, category, scriptsDir string) error {
	info, err := os.Stat(srcPath)
	if err != nil {
		return fmt.Errorf("cannot read file: %w", err)
	}
	if info.IsDir() {
		return fmt.Errorf("path is a directory, not a .ps1 file")
	}
	if !strings.HasSuffix(strings.ToLower(srcPath), ".ps1") {
		return fmt.Errorf("file must be a .ps1 script")
	}
	destDir := filepath.Join(scriptsDir, category)
	if err := os.MkdirAll(destDir, 0755); err != nil {
		return fmt.Errorf("cannot create category dir: %w", err)
	}
	dest := filepath.Join(destDir, filepath.Base(srcPath))
	if _, err := os.Stat(dest); err == nil {
		return fmt.Errorf("%s already exists in %s", filepath.Base(srcPath), category)
	}
	data, err := os.ReadFile(srcPath)
	if err != nil {
		return fmt.Errorf("cannot read source file: %w", err)
	}
	return os.WriteFile(dest, data, 0644)
}

// ── Modal renderers for edit / adopt ─────────────────────────────────────────

func (m model) renderEditModal() string {
	script := m.scripts[m.scriptIdx]
	var sb strings.Builder
	sb.WriteString(modalTitleSt.Render("  Edit Script") + "\n")
	sb.WriteString(dimSt.Render(strings.Repeat("─", 52)) + "\n\n")
	sb.WriteString(scriptNameSt.Render("  "+displayName(script.Name)) + "\n")
	sb.WriteString(dimSt.Render("  "+script.Path) + "\n\n")
	sb.WriteString(dimSt.Render(strings.Repeat("─", 50)) + "\n")
	sb.WriteString(accentSt.Render("  ⚠  Disclaimer") + "\n\n")
	sb.WriteString(normalSt.Render("  This opens the script in your default editor.\n"))
	sb.WriteString(normalSt.Render("  Edits are not validated or tested by this tool.\n"))
	sb.WriteString(normalSt.Render("  Review all changes carefully before running.\n\n"))
	sb.WriteString(dimSt.Render("  Enter to open  ·  Esc to cancel"))
	return modalSt.Width(58).Render(sb.String())
}

func (m model) renderAdoptModal() string {
	var sb strings.Builder
	sb.WriteString(modalTitleSt.Render("  Add Script to: "+m.adoptCat) + "\n")
	sb.WriteString(dimSt.Render(strings.Repeat("─", 52)) + "\n\n")
	sb.WriteString(labelSt.Render("  Path to .ps1 file") + "\n")
	sb.WriteString(m.adoptInput.View() + "\n\n")
	if m.adoptErr != "" {
		sb.WriteString(requiredSt.Render("  ⚠  "+m.adoptErr) + "\n\n")
	}
	sb.WriteString(dimSt.Render(strings.Repeat("─", 50)) + "\n")
	sb.WriteString(accentSt.Render("  ⚠  Disclaimer") + "\n\n")
	sb.WriteString(normalSt.Render("  New scripts are not tested by this tool.\n"))
	sb.WriteString(normalSt.Render("  Ensure the script has a # description on\n"))
	sb.WriteString(normalSt.Render("  line 1 and a param() block before adding.\n\n"))
	sb.WriteString(dimSt.Render("  Enter to add  ·  Esc to cancel"))
	return modalSt.Width(58).Render(sb.String())
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func findScriptsDir() string {
	// Prefer CWD/Scripts (dev mode via `go run`)
	if _, err := os.Stat("Scripts"); err == nil {
		abs, _ := filepath.Abs("Scripts")
		return abs
	}
	// Fallback: next to the binary
	if exe, err := os.Executable(); err == nil {
		p := filepath.Join(filepath.Dir(exe), "Scripts")
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return "Scripts"
}

// ── Entry point ───────────────────────────────────────────────────────────────

func main() {
	scriptsDir := findScriptsDir()
	reg := NewRegistry(scriptsDir)

	if reg.Total() == 0 {
		fmt.Fprintf(os.Stderr, "No scripts found in %s\n", scriptsDir)
		os.Exit(1)
	}

	p := tea.NewProgram(
		newModel(reg),
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(),
	)
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
