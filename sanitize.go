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
