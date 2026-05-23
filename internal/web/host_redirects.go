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
		path = windowsHostsFilePath()
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
		if err := a.runWindowsHostMappingForHosts(ctx, "add", pending); err != nil {
			return err
		}
		missing := make([]string, 0)
		for _, host := range pending {
			if !a.hostRedirectExists(host) {
				missing = append(missing, host)
			}
		}
		if len(missing) > 0 {
			return fmt.Errorf("failed to add Windows host mappings: %s", strings.Join(missing, " "))
		}
		return nil
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
	wsl, _ := isWSL()
	if wsl {
		if err := a.runWindowsHostMappingForHosts(ctx, "remove", []string{host}); err != nil {
			return err
		}
		if a.hostRedirectExists(host) {
			return fmt.Errorf("failed to remove Windows host mapping: %s", host)
		}
		return nil
	}
	return a.Runner.Run(ctx, "bash", "-lc", "grep -q '"+shellQuote(host)+"' /etc/hosts 2>/dev/null && sudo sed -i '/"+strings.ReplaceAll(host, ".", "\\.")+"/d' /etc/hosts || true")
}

func windowsHostsFilePath() string {
	if path := os.Getenv("WEB_WINDOWS_HOSTS_PATH"); path != "" {
		return path
	}
	return "/mnt/c/Windows/System32/drivers/etc/hosts"
}

func (a *App) runWindowsHostMappingForHosts(ctx context.Context, action string, hosts []string) error {
	if len(hosts) == 0 {
		return nil
	}
	var command string
	switch action {
	case "add":
		command = windowsHostsAddCommand(hosts)
	case "remove":
		command = windowsHostsRemoveCommand(hosts)
	default:
		return fmt.Errorf("unsupported host mapping action %s", action)
	}
	return a.runElevatedPowerShell(ctx, command)
}

func windowsHostsAddCommand(hosts []string) string {
	parts := []string{}
	for _, host := range hosts {
		if host == "" {
			continue
		}
		pattern := `^\s*127\.0\.0\.1(?:\s+\S+)*\s+` + regexp.QuoteMeta(host) + `(?:\s|$)`
		line := "127.0.0.1 " + host
		parts = append(parts, "if (-not (Select-String -LiteralPath $hostsPath -Pattern "+powerShellQuote(pattern)+" -Quiet)) { Add-Content -LiteralPath $hostsPath -Value "+powerShellQuote(line)+" }")
	}
	return windowsHostsWritableCommand(strings.Join(parts, "; "))
}

func windowsHostsRemoveCommand(hosts []string) string {
	quoted := make([]string, 0, len(hosts))
	for _, host := range hosts {
		if host != "" {
			quoted = append(quoted, powerShellQuote(host))
		}
	}
	operation := "$names = @(" + strings.Join(quoted, ", ") + "); $content = Get-Content -LiteralPath $hostsPath -ErrorAction Stop; $updated = foreach ($line in $content) { $trim = $line.Trim(); if ($trim -eq '' -or $trim.StartsWith('#')) { $line; continue }; $parts = $trim -split '\\s+'; if ($parts.Length -gt 1 -and $parts[0] -eq '127.0.0.1') { $remaining = @($parts | Where-Object { $names -notcontains $_ }); if ($remaining.Length -gt 1) { $remaining -join ' ' } } else { $line } }; Set-Content -LiteralPath $hostsPath -Value $updated -Encoding ASCII"
	return windowsHostsWritableCommand(operation)
}

func windowsHostsWritableCommand(operation string) string {
	return "$hostsPath = Join-Path $env:SystemRoot 'System32\\drivers\\etc\\hosts'; $hostsItem = Get-Item -LiteralPath $hostsPath; $hostsWasReadOnly = $hostsItem.IsReadOnly; try { if ($hostsWasReadOnly) { $hostsItem.IsReadOnly = $false }; " + operation + " } finally { if ($hostsWasReadOnly) { (Get-Item -LiteralPath $hostsPath).IsReadOnly = $true } }"
}

func (a *App) runElevatedPowerShell(ctx context.Context, command string) error {
	script := "$cmd = " + powerShellQuote(command) + "; $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); if ($isAdmin) { Invoke-Expression $cmd } else { $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd)); $p = Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -Wait -PassThru -ArgumentList @('-NoProfile', '-EncodedCommand', $encoded); if ($p.ExitCode -ne 0) { exit $p.ExitCode } }"
	return a.Runner.Run(ctx, powerShellExecutable(), "-NoProfile", "-Command", "& { "+script+" }")
}

func powerShellExecutable() string {
	if commandExists("powershell.exe") {
		return "powershell.exe"
	}
	return "pwsh.exe"
}

func powerShellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}

type ioDiscard struct{}

func (ioDiscard) Write(p []byte) (int, error) {
	return len(p), nil
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}
