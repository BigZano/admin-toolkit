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
