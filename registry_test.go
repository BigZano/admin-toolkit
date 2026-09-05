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
