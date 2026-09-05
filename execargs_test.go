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
