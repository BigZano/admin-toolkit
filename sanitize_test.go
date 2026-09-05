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
		{"strips U+001F boundary", "a\x1fb", "ab"},
		{"keeps U+0020 boundary", "a b", "a b"},
		{"keeps U+007E before DEL", "a~b", "a~b"},
		{"strips DEL", "a\x7fb", "ab"},
		{"strips C1 control NEL", "ab", "ab"},
		{"strips U+009F boundary", "a\u009fb", "ab"},
		{"keeps U+00A0 boundary", "a\u00a0b", "a\u00a0b"},
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
