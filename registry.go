package main

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"unicode"
)

// ScriptParam describes one parameter of a PowerShell script.
type ScriptParam struct {
	Name     string
	Label    string // plain-language prompt
	Default  string
	Required bool
	Password bool
}

// ScriptInfo holds everything the TUI needs to know about one script.
type ScriptInfo struct {
	Name        string
	Category    string
	Path        string
	Description string
	Params      []ScriptParam
}

// Registry auto-discovers scripts under Scripts/<Category>/*.ps1.
type Registry struct {
	scripts    map[string]*ScriptInfo
	categories []string
}

func NewRegistry(scriptsDir string) *Registry {
	r := &Registry{scripts: make(map[string]*ScriptInfo)}
	r.discover(scriptsDir)
	return r
}

func (r *Registry) discover(root string) {
	entries, err := os.ReadDir(root)
	if err != nil {
		return
	}
	catSet := map[string]bool{}
	for _, d := range entries {
		if !d.IsDir() {
			continue
		}
		catPath := filepath.Join(root, d.Name())
		files, _ := os.ReadDir(catPath)
		for _, f := range files {
			if !strings.HasSuffix(f.Name(), ".ps1") {
				continue
			}
			path := filepath.Join(catPath, f.Name())
			content, err := os.ReadFile(path)
			if err != nil {
				continue
			}
			name := strings.TrimSuffix(f.Name(), ".ps1")
			info := parseScript(name, d.Name(), path, string(content))
			r.scripts[name] = info
			catSet[d.Name()] = true
		}
	}
	for c := range catSet {
		r.categories = append(r.categories, c)
	}
	sort.Strings(r.categories)
}

func (r *Registry) Categories() []string { return r.categories }

func (r *Registry) ScriptsIn(category string) []*ScriptInfo {
	var out []*ScriptInfo
	for _, s := range r.scripts {
		if s.Category == category {
			out = append(out, s)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

func (r *Registry) Get(name string) *ScriptInfo { return r.scripts[name] }
func (r *Registry) Total() int                  { return len(r.scripts) }

// ── Parsing ─────────────────────────────────────────────────────────────────

func parseScript(name, category, path, content string) *ScriptInfo {
	return &ScriptInfo{
		Name:        name,
		Category:    category,
		Path:        path,
		Description: extractDescription(content),
		Params:      extractParams(content),
	}
}

func extractDescription(content string) string {
	for _, line := range strings.SplitN(content, "\n", 30) {
		s := strings.TrimSpace(line)
		if s == "" || strings.HasPrefix(s, "#!") {
			continue
		}
		if strings.HasPrefix(s, "#") {
			desc := strings.TrimSpace(strings.TrimLeft(s, "#"))
			if len(desc) > 10 {
				return desc
			}
		}
		if !strings.HasPrefix(s, "#") && !strings.HasPrefix(s, "<#") {
			break
		}
	}
	return ""
}

var (
	paramBlockRe = regexp.MustCompile(`(?is)param\s*\((.*?)\n\)`)
	paramEntryRe = regexp.MustCompile(`(?i)\[(\w+)\]\s*\$(\w+)(?:\s*=\s*"?([^",\n]*)"?)?`)
	mandatoryRe  = regexp.MustCompile(`(?i)\[Parameter\([^)]*Mandatory\s*=\s*\$true`)
)

// splitParamSections splits a param block on commas that precede a [,
// without needing a lookahead (not supported by Go's RE2 engine).
func splitParamSections(block string) []string {
	parts := strings.Split(block, ",")
	var sections []string
	var cur strings.Builder
	for i, part := range parts {
		if i == 0 {
			cur.WriteString(part)
			continue
		}
		if strings.HasPrefix(strings.TrimSpace(part), "[") {
			sections = append(sections, cur.String())
			cur.Reset()
		} else {
			cur.WriteByte(',')
		}
		cur.WriteString(part)
	}
	if cur.Len() > 0 {
		sections = append(sections, cur.String())
	}
	return sections
}

func extractParams(content string) []ScriptParam {
	m := paramBlockRe.FindStringSubmatch(content)
	if m == nil {
		return nil
	}
	var params []ScriptParam
	for _, section := range splitParamSections(m[1]) {
		section = strings.TrimSpace(section)
		if section == "" {
			continue
		}
		em := paramEntryRe.FindStringSubmatch(section)
		if em == nil {
			continue
		}
		paramType, paramName, defaultVal := em[1], em[2], strings.TrimSpace(em[3])
		if strings.EqualFold(paramType, "switch") {
			continue
		}
		if strings.EqualFold(paramName, "OutputDirectory") {
			continue
		}
		mandatory := mandatoryRe.MatchString(section)
		required := mandatory || (!mandatory && defaultVal == "")

		params = append(params, ScriptParam{
			Name:     paramName,
			Label:    resolveLabel(paramName),
			Default:  defaultVal,
			Required: required,
			Password: strings.Contains(strings.ToLower(paramName), "password"),
		})
	}
	return params
}

// ── Display name conversion ──────────────────────────────────────────────────

var acronyms = map[string]bool{
	"MFA": true, "UPN": true, "SKU": true, "GPO": true,
	"DNS": true, "DHCP": true, "AD": true, "GAL": true, "OU": true,
}

func displayName(name string) string {
	name = strings.ReplaceAll(name, "-", " ")
	name = strings.ReplaceAll(name, "_", " ")
	// Insert spaces at camelCase boundaries:
	//   lower→Upper  ("getUserName" → "get User Name")
	//   Upper→Upper+Lower ("MFAUser" → "MFA User")
	runes := []rune(name)
	var b strings.Builder
	for i, r := range runes {
		if i > 0 && unicode.IsUpper(r) && runes[i-1] != ' ' {
			prevUpper := unicode.IsUpper(runes[i-1])
			nextLower := i+1 < len(runes) && unicode.IsLower(runes[i+1])
			if !prevUpper || nextLower {
				b.WriteRune(' ')
			}
		}
		b.WriteRune(r)
	}
	parts := strings.Fields(b.String())
	for i, p := range parts {
		up := strings.ToUpper(p)
		if acronyms[up] {
			parts[i] = up
		} else {
			parts[i] = capitalize(p)
		}
	}
	return strings.Join(parts, " ")
}

func capitalize(s string) string {
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + strings.ToLower(s[1:])
}

// ── Param label lookup ───────────────────────────────────────────────────────

func resolveLabel(name string) string {
	if label, ok := paramLabels[name]; ok {
		return label
	}
	words := strings.Fields(splitCamel(name))
	for i, w := range words {
		if acronyms[strings.ToUpper(w)] {
			words[i] = strings.ToUpper(w)
		}
	}
	return strings.Join(words, " ")
}

func splitCamel(s string) string {
	runes := []rune(s)
	var parts []string
	var cur strings.Builder
	for i, r := range runes {
		if i > 0 && unicode.IsUpper(r) {
			prevUpper := unicode.IsUpper(runes[i-1])
			nextLower := i+1 < len(runes) && unicode.IsLower(runes[i+1])
			if !prevUpper || nextLower {
				if cur.Len() > 0 {
					parts = append(parts, cur.String())
					cur.Reset()
				}
			}
		}
		cur.WriteRune(r)
	}
	if cur.Len() > 0 {
		parts = append(parts, cur.String())
	}
	return strings.Join(parts, " ")
}

var paramLabels = map[string]string{
	// Identity
	"Username":        "Username (e.g. jsmith)",
	"Upn":             "Email address",
	"DisplayName":     "Display name (full name)",
	"FirstName":       "First name",
	"LastName":        "Last name",
	"Password":        "Password",
	"NewPassword":     "New password",
	"Title":           "Job title (optional)",
	"Department":      "Department (optional)",

	// Groups / AD
	"GroupName":    "Group name",
	"SourceUser":   "Source account (copy groups from)",
	"TargetUser":   "Target account (copy groups to)",
	"TemplateUser": "Template account (copy groups from, optional)",
	"TargetOU":     "OU for new account (leave blank for default)",
	"DisabledOU":   "Move to OU when disabling (optional)",
	"DisabledUsersOU": "Disabled accounts OU (optional)",
	"OOOMessage":   "Out-of-office reply (optional)",

	// Computers / services
	"ComputerName": "Computer name",
	"ComputerList": "Computer(s) to check (leave blank for this machine)",
	"ServiceName":  "Service name (e.g. Spooler, wuauserv)",
	"PrinterName":  "Printer name (leave blank to clear all)",

	// Time / thresholds
	"DaysInactive":    "Days since last login (default: 90)",
	"DaysUntilExpiry": "Warn if expiring within X days (default: 30)",
	"DaysOld":         "Files older than X days (default: 365)",
	"HoursBack":       "Hours of history to search (default: 24)",
	"WaitSeconds":     "Seconds to wait after restart (default: 30)",
	"Count":           "Number of pings (default: 4)",
	"TimeoutSeconds":  "Timeout in seconds (default: 3)",

	// Network
	"Targets":    "Hosts to test (hostname, IP, or comma-separated)",
	"Port":       "Port(s) to test (e.g. 80, 443, or 80-443)",
	"PortRange":  "Port range (e.g. 1-1024 or 'common')",
	"DNSServer":  "DNS server (leave blank for system default)",
	"DHCPServer": "DHCP server address",
	"ScopeId":    "Scope ID to filter (leave blank for all)",
	"RecordType": "Record type (A, MX, CNAME, TXT, etc.)",

	// Files / disk
	"Path":             "Folder or drive to scan",
	"MinSizeMB":        "Minimum file size in MB (default: 100)",
	"Depth":            "Folder levels deep (default: 1)",
	"Recurse":          "Include subfolders (true/false)",
	"Recursive":        "Include nested groups (true/false)",
	"WarnThresholdPct": "Warn at % disk used (default: 80)",
	"CritThresholdPct": "Critical at % disk used (default: 90)",

	// Security
	"Direction":           "Direction (Inbound or Outbound)",
	"EnabledOnly":         "Enabled rules only (true/false)",
	"BruteForceThreshold": "Failed attempts before flagging (default: 10)",
	"IncludeAdminShares":  "Include hidden shares like C$ (true/false)",

	// M365
	"Sku":             "License plan",
	"LicenseIndex":    "License number (0 to skip)",
	"TargetUserEmail": "Target email address",
	"MailboxType":     "Mailbox type (All, UserMailbox, SharedMailbox)",
	"UsageLocation":   "Country code (e.g. US, GB, CA)",

	// GPO / misc
	"ReportType":       "Report format (HTML, XML, or Both)",
	"ForceChangeAtLogon": "Force password change at next login (true/false)",
	"FilterName":       "Filter by name (leave blank for all)",
	"FilterStatus":     "Filter by status (Running, Stopped, or blank for all)",
}
