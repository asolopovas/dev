package web

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func (a *App) rebuildWebConfiguration(ctx context.Context) error {
	registry, err := EnsureRegistry(a.Config)
	if err != nil {
		return err
	}
	if err := ensurePublicDir(a.Config.BackendSitesDir); err != nil {
		return err
	}
	entries, err := os.ReadDir(a.Config.BackendSitesDir)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	for _, entry := range entries {
		name := entry.Name()
		if entry.Type().IsRegular() && name != ".gitkeep" {
			if err := os.Remove(filepath.Join(a.Config.BackendSitesDir, name)); err != nil {
				return err
			}
		}
	}
	values := a.Config.ResolvedValues()
	if err := a.generateHostCertificate(ctx, values.Hosts.PhpMyAdmin); err != nil {
		return err
	}
	if err := a.writePhpMyAdminConfiguration(registry.HTTPS); err != nil {
		return err
	}
	validHosts := make([]HostEntry, 0, len(registry.Hosts))
	for _, host := range registry.Hosts {
		if ValidHostname(host.Name) {
			validHosts = append(validHosts, host)
		} else {
			fmt.Fprintf(a.Err, "Skipping invalid host entry: %s\n", host.Name)
		}
	}
	allHosts := []string{values.Hosts.PhpMyAdmin}
	for _, host := range validHosts {
		allHosts = append(allHosts, host.Name)
	}
	if err := a.addHostRedirects(ctx, allHosts); err != nil {
		return err
	}
	fmt.Fprintf(a.Out, "Rebuilding web configuration: %d hosts\n", len(validHosts))
	if err := a.writeComposeAliases(validHosts); err != nil {
		return err
	}
	if err := writePublicFile(filepath.Join(a.Config.ScriptDir, values.Files.Crontab), []byte{}); err != nil {
		return err
	}
	for _, host := range validHosts {
		if err := a.writeSiteConfiguration(ctx, host, registry.HTTPS); err != nil {
			return err
		}
	}
	fmt.Fprintln(a.Out, "Restarting Caddy")
	return a.dockerComposeQuiet(ctx, "restart", values.Services.FrankenPHP)
}

func (a *App) writeComposeAliases(hosts []HostEntry) error {
	var b strings.Builder
	b.WriteString("services:\n")
	b.WriteString("  ")
	b.WriteString(a.Config.ResolvedValues().Services.FrankenPHP)
	b.WriteString(":\n")
	b.WriteString("    networks:\n")
	b.WriteString("      dev_network:\n")
	b.WriteString("        aliases:\n")
	for _, host := range hosts {
		b.WriteString("          - ")
		b.WriteString(host.Name)
		b.WriteByte('\n')
	}
	return writePublicFile(filepath.Join(a.Config.ScriptDir, a.Config.ResolvedValues().Files.Templates), []byte(b.String()))
}

func (a *App) writePhpMyAdminConfiguration(https bool) error {
	values := a.Config.ResolvedValues()
	return writePublicFile(filepath.Join(a.Config.BackendSitesDir, values.Hosts.PhpMyAdmin+".conf"), []byte(phpMyAdminConfiguration(values, https)))
}

func phpMyAdminConfiguration(values AppValues, https bool) string {
	return fmt.Sprintf("http://%s {\n    root * %s/html\n    encode gzip\n\n    file_server\n\n    php_fastcgi %s:9000\n}\n", values.Hosts.PhpMyAdmin, values.Hosts.ContainerWebDir, values.Services.PhpMyAdmin) + phpMyAdminHTTPSBlock(values, https)
}

func renderSiteConfiguration(templateContent string, hostName string, serveRoot string, https bool) string {
	site := strings.ReplaceAll(templateContent, "${APP_URL}", hostName)
	site = strings.ReplaceAll(site, "${SERVE_ROOT}", serveRoot)
	return site + hostHTTPSBlock(hostName, serveRoot, https)
}

func phpMyAdminHTTPSBlock(values AppValues, https bool) string {
	if https {
		return fmt.Sprintf("\nhttps://%s {\n    tls /etc/caddy/ssl/%s.crt /etc/caddy/ssl/%s.key\n    root * %s/html\n    encode gzip\n\n    file_server\n\n    php_fastcgi %s:9000\n}\n", values.Hosts.PhpMyAdmin, values.Hosts.PhpMyAdmin, values.Hosts.PhpMyAdmin, values.Hosts.ContainerWebDir, values.Services.PhpMyAdmin)
	}
	return fmt.Sprintf("\nhttps://%s {\n    tls /etc/caddy/ssl/%s.crt /etc/caddy/ssl/%s.key\n    redir http://%s{uri}\n}\n", values.Hosts.PhpMyAdmin, values.Hosts.PhpMyAdmin, values.Hosts.PhpMyAdmin, values.Hosts.PhpMyAdmin)
}

func hostHTTPSBlock(hostName string, serveRoot string, https bool) string {
	if https {
		return fmt.Sprintf("\nhttps://%s {\n    tls /etc/caddy/ssl/%s.crt /etc/caddy/ssl/%s.key\n    root * %s\n    import /etc/caddy/cors.conf\n\n    php_server\n}\n", hostName, hostName, hostName, serveRoot)
	}
	return fmt.Sprintf("\nhttps://%s {\n    tls /etc/caddy/ssl/%s.crt /etc/caddy/ssl/%s.key\n    import /etc/caddy/cors.conf\n\n    redir http://%s{uri}\n}\n", hostName, hostName, hostName, hostName)
}

func (a *App) writeSiteConfiguration(ctx context.Context, host HostEntry, https bool) error {
	values := a.Config.ResolvedValues()
	serveRoot := filepath.Join(values.Hosts.ContainerWebDir, host.Name)
	siteType, err := ParseSiteType(host.Type)
	if err != nil {
		return err
	}
	if siteType.WordPress() {
		line := fmt.Sprintf("* * * * * cd %s && php %s/wp-cron.php >/proc/self/fd/1 2>/proc/self/fd/2\n", serveRoot, serveRoot)
		f, err := os.OpenFile(filepath.Join(a.Config.ScriptDir, values.Files.Crontab), os.O_APPEND|os.O_CREATE|os.O_WRONLY, publicFileMode)
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
	if err := a.generateHostCertificate(ctx, host.Name); err != nil {
		return err
	}
	if siteType.Laravel() {
		serveRoot = filepath.Join(serveRoot, "public")
	}
	debugOut := filepath.Join(a.Config.WebRoot, host.Name, ".vscode")
	if err := ensurePublicDir(debugOut); err != nil {
		return err
	}
	launch, err := os.ReadFile(filepath.Join(a.Config.ScriptDir, values.Files.Launch))
	if err != nil {
		return err
	}
	launch = []byte(strings.ReplaceAll(string(launch), "${HOSTNAME}", host.Name))
	if err := writePublicFile(filepath.Join(debugOut, values.Files.Launch), launch); err != nil {
		return err
	}
	templateContent, err := os.ReadFile(filepath.Join(a.Config.BackendConfigDir, values.Files.CaddyTemplate))
	if err != nil {
		return err
	}
	site := renderSiteConfiguration(string(templateContent), host.Name, serveRoot, https)
	if err := writePublicFile(filepath.Join(a.Config.BackendSitesDir, host.Name+".conf"), []byte(site)); err != nil {
		return err
	}
	exists, err := a.databaseExists(ctx, host.DB)
	if err != nil {
		return err
	}
	if !exists {
		fmt.Fprintf(a.Out, "Creating database: %s\n", host.DB)
		return a.createHostDatabase(ctx, host)
	}
	return nil
}
