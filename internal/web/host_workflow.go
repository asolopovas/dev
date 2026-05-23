package web

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func parseNewHostArgs(args []string) (string, string, error) {
	host := ""
	hostType := "wp"
	for i := 0; i < len(args); {
		arg := args[i]
		switch arg {
		case "-t", "--type":
			if i+1 >= len(args) || args[i+1] == "" {
				return "", "", fmt.Errorf("option %s requires a value (wp or laravel)", arg)
			}
			hostType = args[i+1]
			i += 2
		case "":
			i++
		default:
			if strings.HasPrefix(arg, "-") {
				return "", "", fmt.Errorf("unknown option %q", arg)
			}
			if host != "" {
				return "", "", fmt.Errorf("unexpected argument %q", arg)
			}
			host = arg
			i++
		}
	}
	if host == "" {
		return "", "", errors.New("no hostname specified. Usage: web new-host <hostname> -t <wp|laravel>")
	}
	if !ValidHostname(host) {
		return "", "", fmt.Errorf("invalid hostname %q. Use a hostname like example.test", host)
	}
	return host, hostType, nil
}

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

func (a *App) removeHost(ctx context.Context, host string) error {
	if host == "" {
		return errors.New("no hostname specified. Usage: web remove-host <hostname>")
	}
	registry, err := EnsureRegistry(a.Config)
	if err != nil {
		return err
	}
	if db := registry.DB(host); db != "" {
		if err := a.removeDatabase(ctx, db); err != nil {
			return err
		}
	}
	if err := os.RemoveAll(filepath.Join(a.Config.WebRoot, host)); err != nil {
		return err
	}
	for _, ext := range []string{"key", "crt", "csr"} {
		_ = os.Remove(filepath.Join(a.Config.CertsDir, host+"."+ext))
	}
	if err := a.removeHostRedirect(ctx, host); err != nil {
		return err
	}
	registry.Remove(host)
	return SaveRegistry(a.Config.HostsJSON, registry)
}

func (a *App) removeHostInteractive(ctx context.Context) error {
	registry, err := EnsureRegistry(a.Config)
	if err != nil {
		return err
	}
	if len(registry.Hosts) == 0 {
		return errors.New("no hosts configured")
	}
	if !commandExists("gum") {
		return errors.New("interactive remove-host requires gum or a hostname argument")
	}
	var names []string
	for _, host := range registry.Hosts {
		names = append(names, host.Name)
	}
	out, err := a.Runner.Output(ctx, "gum", append([]string{"choose", "--no-limit", "--header=Select hosts to remove (space to toggle, enter to confirm)"}, names...)...)
	if err != nil {
		return err
	}
	selected := strings.Fields(string(out))
	if len(selected) == 0 {
		return errors.New("no hosts selected")
	}
	for _, host := range selected {
		if err := a.removeHost(ctx, host); err != nil {
			return err
		}
	}
	return a.rebuildWebConfiguration(ctx)
}
