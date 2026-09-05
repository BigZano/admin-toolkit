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
