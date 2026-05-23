package web

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

type App struct {
	Config Config
	Runner Runner
	Out    io.Writer
	Err    io.Writer
	In     io.Reader
}

func NewApp(out io.Writer, errw io.Writer) (*App, error) {
	return &App{
		Config: LoadConfig(),
		Runner: ExecRunner{Stdout: out, Stderr: errw, Stdin: os.Stdin},
		Out:    out,
		Err:    errw,
		In:     os.Stdin,
	}, nil
}

func (a *App) Run(args []string) error {
	cmd := "help"
	if len(args) > 0 {
		cmd = args[0]
		args = args[1:]
	}
	ctx := context.Background()
	switch cmd {
	case "up":
		return a.dcAction(ctx, "up", args)
	case "down":
		return a.dcAction(ctx, "down", args)
	case "stop":
		return a.dcAction(ctx, "stop", args)
	case "restart":
		return a.dcAction(ctx, "restart", args)
	case "build":
		return a.dcBuild(ctx, args)
	case "ps":
		return a.requireDockerThen(ctx, func() error { return a.dockerCompose(ctx, append([]string{"ps"}, args...)...) })
	case "log":
		return a.requireDockerThen(ctx, func() error { return a.dockerCompose(ctx, append([]string{"logs", "-f"}, args...)...) })
	case "new-host":
		if len(args) == 0 {
			return a.newHostWizard(ctx)
		}
		host, hostType, err := parseNewHostArgs(args)
		if err != nil {
			return err
		}
		return a.newHost(ctx, host, hostType, "")
	case "remove-host":
		if len(args) == 0 {
			return a.removeHostInteractive(ctx)
		}
		host, _, err := parseNewHostArgs(args)
		if err != nil {
			return err
		}
		if !a.confirm(fmt.Sprintf("Remove %s?", host)) {
			return nil
		}
		if err := a.removeHost(ctx, host); err != nil {
			return err
		}
		return a.buildWebconf(ctx)
	case "build-webconf":
		return a.buildWebconf(ctx)
	case "bash":
		return a.requireDockerThen(ctx, func() error { return a.dockerCompose(ctx, "exec", "franken_php", "bash") })
	case "fish":
		return a.requireDockerThen(ctx, func() error { return a.dockerCompose(ctx, "exec", "franken_php", "fish") })
	case "rootssl":
		if err := a.requireDocker(ctx); err != nil {
			return err
		}
		if err := a.sslGenerateRoot(ctx, "rootCA", "default"); err != nil {
			return err
		}
		return a.dockerCompose(ctx, "restart", "franken_php")
	case "hostssl":
		if len(args) == 0 || args[0] == "" {
			return errors.New("no hostname specified. Usage: web hostssl <hostname>")
		}
		return a.sslGenerateHost(ctx, args[0])
	case "import-rootca":
		return a.sslImportRoot(ctx, a.Config.RootCrt, "Lyntouch Root CA")
	case "mysql":
		return a.requireDockerThen(ctx, func() error {
			return a.dockerCompose(ctx, "exec", "-e", "MYSQL_PWD=secret", "mariadb", "mariadb", "-uroot")
		})
	case "db-backup":
		return a.dbBackup(ctx)
	case "db-restore":
		return a.dbRestore(ctx)
	case "redis-cli":
		return a.requireDockerThen(ctx, func() error { return a.dockerCompose(ctx, "exec", "redis", "redis-cli") })
	case "redis-flush":
		return a.requireDockerThen(ctx, func() error { return a.dockerCompose(ctx, "exec", "redis", "redis-cli", "flushall") })
	case "redis-monitor":
		return a.requireDockerThen(ctx, func() error { return a.dockerCompose(ctx, "exec", "redis", "redis-cli", "monitor") })
	case "debug":
		return a.setDebugMode(ctx, args)
	case "install":
		return a.install()
	case "dir":
		fmt.Fprintln(a.Out, a.Config.ScriptDir)
		return nil
	default:
		a.showHelp()
		return nil
	}
}

func (a *App) composeArgs(args ...string) []string {
	out := []string{"compose"}
	for _, file := range a.Config.ComposeFiles {
		out = append(out, "-f", file)
	}
	return append(out, args...)
}

func (a *App) dockerCompose(ctx context.Context, args ...string) error {
	all := a.composeArgs(args...)
	return wrapCommandError("docker", all, a.Runner.Run(ctx, "docker", all...))
}

func (a *App) dockerComposeOutput(ctx context.Context, args ...string) ([]byte, error) {
	all := a.composeArgs(args...)
	out, err := a.Runner.Output(ctx, "docker", all...)
	return out, wrapCommandError("docker", all, err)
}

func (a *App) requireDocker(ctx context.Context) error {
	if !commandExists("docker") {
		return errors.New("docker is not installed")
	}
	if _, err := a.Runner.Output(ctx, "docker", "info"); err != nil {
		return errors.New("docker daemon is not running")
	}
	return nil
}

func (a *App) requireDockerThen(ctx context.Context, fn func() error) error {
	if err := a.requireDocker(ctx); err != nil {
		return err
	}
	return fn()
}

func (a *App) dcAction(ctx context.Context, action string, services []string) error {
	if err := a.requireDocker(ctx); err != nil {
		return err
	}
	if action == "down" && len(services) > 0 {
		return errors.New("down operates on the entire stack. Use `web stop <service>` instead")
	}
	if action == "up" {
		if err := a.dockerCompose(ctx, append([]string{"up", "-d", "--remove-orphans"}, services...)...); err != nil {
			return err
		}
	} else if action == "down" {
		if err := a.dockerCompose(ctx, "down"); err != nil {
			return err
		}
		return nil
	} else if err := a.dockerCompose(ctx, append([]string{action}, services...)...); err != nil {
		return err
	}
	fmt.Fprintln(a.Out)
	return a.dockerCompose(ctx, append([]string{"ps"}, services...)...)
}

func (a *App) dcBuild(ctx context.Context, args []string) error {
	if err := a.requireDocker(ctx); err != nil {
		return err
	}
	svc := ""
	cache := ""
	if len(args) > 0 {
		svc = args[0]
	}
	if len(args) > 1 && args[1] == "--no-cache" {
		cache = args[1]
	}
	buildArgs := []string{"build"}
	if cache != "" {
		buildArgs = append(buildArgs, cache)
	}
	if svc != "" {
		buildArgs = append(buildArgs, svc)
	}
	if err := a.dockerCompose(ctx, buildArgs...); err != nil {
		return err
	}
	upArgs := []string{"up", "-d", "--remove-orphans"}
	if svc != "" {
		upArgs = append(upArgs, svc)
	}
	return a.dockerCompose(ctx, upArgs...)
}

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
	for _, choice := range choices {
		if v == choice {
			return v
		}
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
	if err := a.redirectAdd(ctx, host); err != nil {
		return err
	}
	if err := a.buildWebconf(ctx); err != nil {
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
		if err := a.dbRemove(ctx, db); err != nil {
			return err
		}
	}
	if err := os.RemoveAll(filepath.Join(a.Config.WebRoot, host)); err != nil {
		return err
	}
	for _, ext := range []string{"key", "crt", "csr"} {
		_ = os.Remove(filepath.Join(a.Config.CertsDir, host+"."+ext))
	}
	if err := a.redirectRemove(ctx, host); err != nil {
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
	return a.buildWebconf(ctx)
}

func (a *App) showHelp() {
	fmt.Fprint(a.Out, `web - Docker PHP development environment

Usage: web <command> [options]

Environment:
  up [service]                  Start Docker services
  down                          Stop and remove services
  stop [service]                Stop services
  restart [service]             Restart services
  build [service] [--no-cache]  Build services
  ps [service]                  Container status
  log <service>                 View service logs

Hosts:
  new-host [host] [-t type]     Create site
  remove-host [host]            Remove site
  build-webconf                 Regenerate Caddy configs

Shell:
  bash                          Container Bash
  fish                          Container Fish

SSL:
  rootssl                       Generate root CA
  hostssl <host>                Generate host SSL
  import-rootca                 Import root CA to Chrome

Database:
  mysql                         MySQL client as root
  db-backup                     Dump all databases to db-backup.sql.gz
  db-restore                    Restore from db-backup.sql.gz

Tools:
  redis-cli                     Redis CLI shell
  redis-flush                   Flush Redis
  redis-monitor                 Monitor Redis
  debug [off|debug|profile]     Set Xdebug mode
  install                       Create CLI symlinks
  dir                           Print script directory
`)
}

func (a *App) dbBackup(ctx context.Context) error {
	if err := a.requireDocker(ctx); err != nil {
		return err
	}
	out, err := a.dockerComposeOutput(ctx, "exec", "-T", "-e", "MYSQL_PWD=secret", "mariadb", "mariadb-dump", "-uroot", "--all-databases")
	if err != nil {
		return err
	}
	var gz bytes.Buffer
	if err := gzipData(&gz, out); err != nil {
		return err
	}
	path := filepath.Join(a.Config.ScriptDir, "db-backup.sql.gz")
	if err := os.WriteFile(path, gz.Bytes(), 0644); err != nil {
		return err
	}
	fmt.Fprintf(a.Out, "Backed up to %s\n", path)
	return nil
}

func (a *App) dbRestore(ctx context.Context) error {
	if err := a.requireDocker(ctx); err != nil {
		return err
	}
	path := filepath.Join(a.Config.ScriptDir, "db-backup.sql.gz")
	data, err := gunzipFile(path)
	if err != nil {
		return err
	}
	args := a.composeArgs("exec", "-T", "-e", "MYSQL_PWD=secret", "mariadb", "mariadb", "-uroot")
	out, err := a.Runner.Pipe(ctx, data, "docker", args...)
	if len(out) > 0 {
		_, _ = a.Out.Write(out)
	}
	if err != nil {
		return err
	}
	fmt.Fprintln(a.Out, "Restore complete")
	return nil
}

func (a *App) install() error {
	home, _ := os.UserHomeDir()
	bin := filepath.Join(home, ".local", "bin")
	if err := os.MkdirAll(bin, 0755); err != nil {
		return err
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	_ = os.Remove(filepath.Join(bin, "web"))
	return os.Symlink(exe, filepath.Join(bin, "web"))
}
