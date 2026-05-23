package web

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
)

func (a *App) hostRedirectExists(host string) bool {
	wsl, _ := isWSL()
	path := "/etc/hosts"
	if wsl {
		path = "/mnt/c/Windows/System32/drivers/etc/hosts"
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	escaped := regexp.QuoteMeta(host)
	if wsl {
		re := regexp.MustCompile(`(?m)^\s*127\.0\.0\.1.*` + escaped + `(?:\s+|$)`)
		return re.Match(data)
	}
	re := regexp.MustCompile(`(?m)^[^#]*\s` + escaped + `(?:\s|$)`)
	return re.Match(data)
}

func (a *App) addHostRedirect(ctx context.Context, host string) error {
	if a.hostRedirectExists(host) {
		return nil
	}
	return a.addHostRedirects(ctx, []string{host})
}

func (a *App) addHostRedirects(ctx context.Context, hosts []string) error {
	pending := make([]string, 0, len(hosts))
	for _, host := range hosts {
		if host != "" && !a.hostRedirectExists(host) {
			pending = append(pending, host)
		}
	}
	if len(pending) == 0 {
		return nil
	}
	fmt.Fprintf(a.Out, "Adding host redirections: %s\n", strings.Join(pending, " "))
	wsl, _ := isWSL()
	if wsl {
		return a.runHostMappingCmdletForHosts(ctx, "New-HostnameMapping", pending)
	}
	var b strings.Builder
	for _, host := range pending {
		b.WriteString("127.0.0.1 ")
		b.WriteString(host)
		b.WriteByte('\n')
	}
	cmd := exec.CommandContext(ctx, "sudo", "tee", "-a", "/etc/hosts")
	cmd.Stdin = strings.NewReader(b.String())
	cmd.Stdout = ioDiscard{}
	cmd.Stderr = a.Err
	return cmd.Run()
}

func (a *App) removeHostRedirect(ctx context.Context, host string) error {
	fmt.Fprintf(a.Out, "Removing host redirection for %q\n", host)
	wsl, _ := isWSL()
	if wsl {
		return a.runHostMappingCmdletForHosts(ctx, "Remove-HostnameMapping", []string{host})
	}
	return a.Runner.Run(ctx, "bash", "-lc", "grep -q '"+shellQuote(host)+"' /etc/hosts 2>/dev/null && sudo sed -i '/"+strings.ReplaceAll(host, ".", "\\.")+"/d' /etc/hosts || true")
}

func (a *App) runHostMappingCmdletForHosts(ctx context.Context, cmdlet string, hosts []string) error {
	if len(hosts) == 0 {
		return nil
	}
	ps := "powershell.exe"
	if commandExists("pwsh.exe") {
		ps = "pwsh.exe"
	}
	parts := []string{"Import-Module Hosts -ErrorAction Stop"}
	for _, host := range hosts {
		parts = append(parts, cmdlet+" '"+strings.ReplaceAll(host, "'", "''")+"'")
	}
	psCmd := strings.Join(parts, "; ")
	return a.Runner.Run(ctx, ps, "-NoProfile", "-Command", "& { "+psCmd+" }")
}

type ioDiscard struct{}

func (ioDiscard) Write(p []byte) (int, error) {
	return len(p), nil
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}
