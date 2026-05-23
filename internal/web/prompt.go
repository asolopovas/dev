package web

import (
	"bufio"
	"context"
	"fmt"
	"slices"
	"strings"
)

func (a *App) prompt(label string, value string) string {
	if commandExists("gum") {
		args := []string{"input", "--prompt", label + ": "}
		if value != "" {
			args = append(args, "--value", value)
		}
		out, err := a.Runner.Output(context.Background(), "gum", args...)
		if err == nil {
			return strings.TrimSpace(string(out))
		}
	}
	fmt.Fprintf(a.Out, "%s", label)
	if value != "" {
		fmt.Fprintf(a.Out, " [%s]", value)
	}
	fmt.Fprint(a.Out, ": ")
	scanner := bufio.NewScanner(a.In)
	if scanner.Scan() {
		v := strings.TrimSpace(scanner.Text())
		if v != "" {
			return v
		}
	}
	return value
}

func (a *App) choose(prompt string, choices ...string) string {
	if commandExists("gum") {
		args := append([]string{"choose", "--header=" + prompt}, choices...)
		out, err := a.Runner.Output(context.Background(), "gum", args...)
		if err == nil {
			return strings.TrimSpace(string(out))
		}
	}
	for i, choice := range choices {
		fmt.Fprintf(a.Out, "%d) %s\n", i+1, choice)
	}
	v := a.prompt(prompt, choices[0])
	if slices.Contains(choices, v) {
		return v
	}
	return choices[0]
}

func (a *App) confirm(message string) bool {
	if commandExists("gum") {
		return a.Runner.Run(context.Background(), "gum", "confirm", message) == nil
	}
	fmt.Fprintf(a.Out, "%s [y/N]: ", message)
	scanner := bufio.NewScanner(a.In)
	if scanner.Scan() {
		v := strings.ToLower(strings.TrimSpace(scanner.Text()))
		return v == "y" || v == "yes"
	}
	return false
}
