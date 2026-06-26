package main

import "github.com/charmbracelet/lipgloss"

const (
	clrBorder  = "#2d8659"
	clrAccent  = "#ff6b35"
	clrGold    = "#c9a961"
	clrText    = "#e2e8f0"
	clrDim     = "#7a8a7f"
	clrGreen   = "#39d353"
	clrError   = "#d93a2b"
	clrPanel   = "#0f1a14"
	clrCursor  = "#c9a961"
)

var (
	panelSt = lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color(clrBorder))

	titleSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrGold)).
		Bold(true)

	selectedSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrPanel)).
		Background(lipgloss.Color(clrGreen)).
		Bold(true)

	normalSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrText))

	dimSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrDim))

	accentSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrAccent))

	labelSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrBorder)).
		Bold(true)

	requiredSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrError))

	successSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrGreen))

	errorSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrError))

	runningSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrGold))

	modalSt = lipgloss.NewStyle().
		Border(lipgloss.ThickBorder()).
		BorderForeground(lipgloss.Color(clrAccent)).
		Background(lipgloss.Color(clrPanel)).
		Padding(1, 2)

	modalTitleSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrGold)).
		Bold(true).
		Background(lipgloss.Color(clrPanel))

	footerSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrDim))

	hrSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrBorder))

	inputActiveSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrGreen))

	scriptNameSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrGold)).
		Bold(true)

	scriptDescSt = lipgloss.NewStyle().
		Foreground(lipgloss.Color(clrDim))
)
