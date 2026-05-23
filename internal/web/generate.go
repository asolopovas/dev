package web

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func (a *App) buildWebconf(ctx context.Context) error {
	registry, err := EnsureRegistry(a.Config)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(a.Config.BackendSitesDir, 0755); err != nil {
		return err
	}
	entries, err := os.ReadDir(a.Config.BackendSitesDir)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	for _, entry := range entries {
		name := entry.Name()
		if entry.Type().IsRegular() && name != "phpmyadmin.test.conf" && name != ".gitkeep" {
			if err := os.Remove(filepath.Join(a.Config.BackendSitesDir, name)); err != nil {
				return err
			}
		}
	}
	validHosts := make([]HostEntry, 0, len(registry.Hosts))
	for _, host := range registry.Hosts {
		if ValidHostname(host.Name) {
			validHosts = append(validHosts, host)
		} else {
			fmt.Fprintf(a.Err, "Skipping invalid host entry: %s\n", host.Name)
		}
	}
	allHosts := []string{"phpmyadmin.test"}
	for _, host := range validHosts {
		allHosts = append(allHosts, host.Name)
	}
	if err := a.redirectAddBatch(ctx, allHosts); err != nil {
		return err
	}
	if _, ok := registry.Host("phpmyadmin.test"); !ok {
		if err := a.sslGenerateHost(ctx, "phpmyadmin.test"); err != nil {
			return err
		}
	}
	if err := a.writeTemplates(validHosts); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(a.Config.ScriptDir, "crontab"), []byte{}, 0644); err != nil {
		return err
	}
	for _, host := range validHosts {
		if err := a.processHost(ctx, host); err != nil {
			return err
		}
	}
	fmt.Fprintln(a.Out, "Finished building web configs. Restarting Caddy...")
	return a.dockerCompose(ctx, "restart", "franken_php")
}

func (a *App) writeTemplates(hosts []HostEntry) error {
	var b strings.Builder
	b.WriteString("services:\n")
	b.WriteString("  franken_php:\n")
	b.WriteString("    networks:\n")
	b.WriteString("      dev_network:\n")
	b.WriteString("        aliases:\n")
	for _, host := range hosts {
		b.WriteString("          - ")
		b.WriteString(host.Name)
		b.WriteByte('\n')
	}
	return os.WriteFile(filepath.Join(a.Config.ScriptDir, "templates.yml"), []byte(b.String()), 0644)
}

func (a *App) processHost(ctx context.Context, host HostEntry) error {
	fmt.Fprintf(a.Out, "Processing host: %s\n", host.Name)
	serveRoot := "/var/www/" + host.Name
	if host.Type == "wp" || host.Type == "wordpress" {
		line := fmt.Sprintf("* * * * * cd %s && php %s/wp-cron.php >/proc/self/fd/1 2>/proc/self/fd/2\n", serveRoot, serveRoot)
		f, err := os.OpenFile(filepath.Join(a.Config.ScriptDir, "crontab"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			return err
		}
		if _, err := f.WriteString(line); err != nil {
			_ = f.Close()
			return err
		}
		if err := f.Close(); err != nil {
			return err
		}
	}
	if err := a.sslGenerateHost(ctx, host.Name); err != nil {
		return err
	}
	if host.Type == "laravel" {
		serveRoot += "/public"
	}
	debugOut := filepath.Join(a.Config.WebRoot, host.Name, ".vscode")
	if err := os.MkdirAll(debugOut, 0755); err != nil {
		return err
	}
	launch, err := os.ReadFile(filepath.Join(a.Config.ScriptDir, "launch.json"))
	if err != nil {
		return err
	}
	launch = []byte(strings.ReplaceAll(string(launch), "${HOSTNAME}", host.Name))
	if err := os.WriteFile(filepath.Join(debugOut, "launch.json"), launch, 0644); err != nil {
		return err
	}
	tmpl, err := os.ReadFile(filepath.Join(a.Config.BackendConfigDir, "template.conf"))
	if err != nil {
		return err
	}
	site := strings.ReplaceAll(string(tmpl), "${APP_URL}", host.Name)
	site = strings.ReplaceAll(site, "${SERVE_ROOT}", serveRoot)
	if err := os.WriteFile(filepath.Join(a.Config.BackendSitesDir, host.Name+".conf"), []byte(site), 0644); err != nil {
		return err
	}
	exists, err := a.dbExists(ctx, host.DB)
	if err != nil {
		return err
	}
	if !exists {
		fmt.Fprintf(a.Out, "Creating missing DB: %s\n", host.DB)
		return a.dbCreate(ctx, host)
	}
	return nil
}
