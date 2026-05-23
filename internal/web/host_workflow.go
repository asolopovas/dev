package web

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func (a *App) newHostWizard(ctx context.Context) error {
	host := a.prompt("Hostname", "")
	hostType := a.choose("Site type:", "wp", "laravel")
	db := a.prompt("Database name", MakeDBName(host, hostType))
	fmt.Fprintf(a.Out, "\nHostname:   %s\nType:       %s\nDatabase:   %s\n\n", host, hostType, db)
	if !a.confirm("Proceed?") {
		return nil
	}
	return a.newHost(ctx, host, hostType, db)
}

func (a *App) newHost(ctx context.Context, host string, hostType string, dbName string) error {
	if err := a.requireDocker(ctx); err != nil {
		return err
	}
	if !ValidHostname(host) {
		return fmt.Errorf("invalid hostname %q. Use a hostname like example.test", host)
	}
	if dbName == "" {
		dbName = MakeDBName(host, hostType)
	}
	switch hostType {
	case "wp", "wordpress":
		if err := a.scaffoldWordPress(ctx, host, dbName); err != nil {
			return err
		}
	case "laravel":
		if err := a.scaffoldLaravel(ctx, host, dbName); err != nil {
			return err
		}
	default:
		return fmt.Errorf("invalid type %q. Use: wp, wordpress, or laravel", hostType)
	}
	registry, err := EnsureRegistry(a.Config)
	if err != nil {
		return err
	}
	if err := registry.Add(HostEntry{Name: host, Type: hostType, DB: dbName}); err != nil {
		return err
	}
	if err := SaveRegistry(a.Config.HostsJSON, registry); err != nil {
		return err
	}
	if err := a.addHostRedirect(ctx, host); err != nil {
		return err
	}
	if err := a.rebuildWebConfiguration(ctx); err != nil {
		return err
	}
	if hostType == "laravel" {
		return a.dockerCompose(ctx, "exec", "-T", "franken_php", "php", "/var/www/"+host+"/artisan", "migrate", "--force")
	}
	return nil
}

func (a *App) removeHostByName(ctx context.Context, name string, askConfirmation bool) error {
	if name == "" {
		return errors.New("no hostname specified. Usage: web remove-host <hostname>")
	}
	if !ValidHostname(name) {
		return fmt.Errorf("invalid hostname %q. Use a hostname like example.test", name)
	}
	registry, err := EnsureRegistry(a.Config)
	if err != nil {
		return err
	}
	host, ok := registry.Host(name)
	if !ok {
		return fmt.Errorf("host %s is not configured", name)
	}
	if askConfirmation && !a.confirm(fmt.Sprintf("Remove %s?", name)) {
		return nil
	}
	return a.removeConfiguredHosts(ctx, registry, []HostEntry{host})
}

func (a *App) removeHostInteractive(ctx context.Context) error {
	registry, err := EnsureRegistry(a.Config)
	if err != nil {
		return err
	}
	if len(registry.Hosts) == 0 {
		return errors.New("no hosts configured")
	}
	if !commandExists("gum") || !interactiveInput(a.In) {
		return errors.New("run web remove-host <hostname> or web remove-host <hostname> --yes")
	}
	var names []string
	for _, host := range registry.Hosts {
		names = append(names, host.Name)
	}
	out, err := a.Runner.Output(ctx, "gum", append([]string{"choose", "--no-limit", "--header=Select hosts to remove (space to toggle, enter to confirm)"}, names...)...)
	if err != nil {
		return err
	}
	selectedNames := strings.Fields(string(out))
	if len(selectedNames) == 0 {
		return errors.New("no hosts selected")
	}
	selectedHosts := make([]HostEntry, 0, len(selectedNames))
	for _, name := range selectedNames {
		host, ok := registry.Host(name)
		if !ok {
			return fmt.Errorf("host %s is not configured", name)
		}
		selectedHosts = append(selectedHosts, host)
	}
	return a.removeConfiguredHosts(ctx, registry, selectedHosts)
}

func (a *App) removeConfiguredHosts(ctx context.Context, registry Registry, hosts []HostEntry) error {
	for _, host := range hosts {
		if err := a.removeHostResources(ctx, host); err != nil {
			return err
		}
		registry.Remove(host.Name)
	}
	if err := SaveRegistry(a.Config.HostsJSON, registry); err != nil {
		return err
	}
	return a.rebuildWebConfiguration(ctx)
}

func (a *App) removeHostResources(ctx context.Context, host HostEntry) error {
	if host.DB != "" {
		if err := a.removeDatabase(ctx, host.DB); err != nil {
			return err
		}
	}
	if err := os.RemoveAll(filepath.Join(a.Config.WebRoot, host.Name)); err != nil {
		return err
	}
	for _, ext := range []string{"key", "crt", "csr"} {
		_ = os.Remove(filepath.Join(a.Config.CertsDir, host.Name+"."+ext))
	}
	return a.removeHostRedirect(ctx, host.Name)
}
