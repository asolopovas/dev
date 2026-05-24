package web

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
)

type commandHandler func(context.Context, []string) error

func NewRootCommand(output io.Writer, errorOutput io.Writer, input io.Reader) *cobra.Command {
	app, appErr := NewApp(output, errorOutput)
	if appErr == nil {
		app.In = input
		app.Runner = ExecRunner{Stdout: output, Stderr: errorOutput, Stdin: input}
	}
	root := newBaseCommand(output, errorOutput, input)
	if appErr != nil {
		root.PersistentPreRunE = func(cmd *cobra.Command, args []string) error { return appErr }
		return root
	}
	configureCommands(root, app)
	return root
}

func NewAppCommand(app *App) *cobra.Command {
	root := newBaseCommand(app.Out, app.Err, app.In)
	configureCommands(root, app)
	return root
}

func Execute(args []string, output io.Writer, errorOutput io.Writer, input io.Reader) error {
	cmd := NewRootCommand(output, errorOutput, input)
	cmd.SetArgs(args)
	return cmd.Execute()
}

func newBaseCommand(output io.Writer, errorOutput io.Writer, input io.Reader) *cobra.Command {
	root := &cobra.Command{
		Use:           commandNameWeb,
		Short:         "Docker PHP development environment",
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmd.Help()
		},
	}
	root.SetOut(output)
	root.SetErr(errorOutput)
	root.SetIn(input)
	root.CompletionOptions.DisableDefaultCmd = true
	return root
}

func configureCommands(root *cobra.Command, app *App) {
	addEnvironmentCommands(root, app)
	addHostCommands(root, app)
	addShellCommands(root, app)
	addSSLCommands(root, app)
	addDatabaseCommands(root, app)
	addToolCommands(root, app)
	root.AddCommand(newCompletionCommand())
}

func appCommand(use string, short string, args cobra.PositionalArgs, run commandHandler) *cobra.Command {
	return &cobra.Command{
		Use:   use,
		Short: short,
		Args:  args,
		RunE: func(cmd *cobra.Command, args []string) error {
			return run(cmd.Context(), args)
		},
	}
}

func addEnvironmentCommands(root *cobra.Command, app *App) {
	for _, action := range []string{"up", "down", "stop", "restart"} {
		action := action
		root.AddCommand(appCommand(action+" [service]", action+" Docker services", cobra.ArbitraryArgs, func(ctx context.Context, args []string) error {
			return app.runDockerComposeAction(ctx, action, args)
		}))
	}
	var noCache bool
	build := appCommand("build [service]", "Build services", cobra.MaximumNArgs(1), func(ctx context.Context, args []string) error {
		buildArgs := append([]string{}, args...)
		if noCache {
			buildArgs = append(buildArgs, "--no-cache")
		}
		return app.buildDockerComposeServices(ctx, buildArgs)
	})
	build.Flags().BoolVar(&noCache, "no-cache", false, "Build without cache")
	root.AddCommand(build)
	root.AddCommand(appCommand("ps [service]", "Container status", cobra.ArbitraryArgs, func(ctx context.Context, args []string) error {
		return app.requireDockerThen(ctx, func() error {
			return app.dockerComposePs(ctx, args...)
		})
	}))
	root.AddCommand(appCommand("log [service]", "View service logs", cobra.ArbitraryArgs, func(ctx context.Context, args []string) error {
		return app.requireDockerThen(ctx, func() error {
			return app.dockerCompose(ctx, append([]string{"logs", "-f"}, args...)...)
		})
	}))
}

func completeSiteTypes(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
	if len(args) > 0 {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}
	var values []string
	for _, value := range siteTypeValues {
		if strings.HasPrefix(value, toComplete) {
			values = append(values, value)
		}
	}
	return values, cobra.ShellCompDirectiveNoFileComp
}

func (a *App) completeConfiguredHosts(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
	if len(args) > 0 {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}
	registry, err := LoadRegistry(a.Config.HostsJSON)
	if err != nil {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}
	values := make([]string, 0, len(registry.Hosts))
	for _, host := range registry.Hosts {
		if strings.HasPrefix(host.Name, toComplete) {
			description := host.Type
			if host.DB != "" {
				description += " " + host.DB
			}
			values = append(values, host.Name+"\t"+description)
		}
	}
	return values, cobra.ShellCompDirectiveNoFileComp
}

func addHostCommands(root *cobra.Command, app *App) {
	var hostType string
	newHost := appCommand("new-host [host]", "Create site", cobra.MaximumNArgs(1), func(ctx context.Context, args []string) error {
		if len(args) == 0 {
			return app.newHostWizard(ctx)
		}
		return app.newHost(ctx, args[0], hostType, "")
	})
	newHost.Flags().StringVarP(&hostType, "type", "t", string(SiteTypeWordPressShort), "Site type")
	_ = newHost.RegisterFlagCompletionFunc("type", completeSiteTypes)
	root.AddCommand(newHost)
	var skipConfirmation bool
	removeHost := appCommand("remove-host [host]", "Remove site", cobra.MaximumNArgs(1), func(ctx context.Context, args []string) error {
		if len(args) == 0 {
			return app.removeHostInteractive(ctx)
		}
		return app.removeHostByName(ctx, args[0], !skipConfirmation)
	})
	removeHost.Flags().BoolVarP(&skipConfirmation, "yes", "y", false, "Remove without confirmation")
	removeHost.ValidArgsFunction = app.completeConfiguredHosts
	root.AddCommand(removeHost)
	root.AddCommand(appCommand("build-webconf", "Regenerate Caddy configs", cobra.NoArgs, func(ctx context.Context, args []string) error {
		return app.rebuildWebConfiguration(ctx)
	}))
}

func addShellCommands(root *cobra.Command, app *App) {
	addComposeCommands(root, app, shellCommandSpecs(app.Config))
}

func addComposeCommands(root *cobra.Command, app *App, specs []composeCommandSpec) {
	for _, spec := range specs {
		spec := spec
		root.AddCommand(dockerCommand(app, spec.Use, spec.Short, spec.Args...))
	}
}

func dockerCommand(app *App, use string, short string, composeArgs ...string) *cobra.Command {
	return appCommand(use, short, cobra.NoArgs, func(ctx context.Context, args []string) error {
		return app.requireDockerThen(ctx, func() error {
			return app.dockerCompose(ctx, composeArgs...)
		})
	})
}

func addSSLCommands(root *cobra.Command, app *App) {
	root.AddCommand(appCommand("rootssl", "Generate root CA", cobra.NoArgs, func(ctx context.Context, args []string) error {
		if err := app.requireDocker(ctx); err != nil {
			return err
		}
		values := app.Config.ResolvedValues()
		if err := app.generateRootCertificate(ctx, values.Certificates.RootName, values.Certificates.RootPassphrase); err != nil {
			return err
		}
		return app.dockerCompose(ctx, "restart", values.Services.FrankenPHP)
	}))
	hostSSL := appCommand("hostssl <host>", "Generate host SSL", cobra.ExactArgs(1), func(ctx context.Context, args []string) error {
		return app.generateHostCertificate(ctx, args[0])
	})
	hostSSL.ValidArgsFunction = app.completeConfiguredHosts
	root.AddCommand(hostSSL)
	root.AddCommand(appCommand("import-rootca", "Import root CA to Chrome", cobra.NoArgs, func(ctx context.Context, args []string) error {
		return app.importRootCertificate(ctx, app.Config.RootCrt, app.Config.ResolvedValues().Certificates.RootNickname)
	}))
}

func addDatabaseCommands(root *cobra.Command, app *App) {
	addComposeCommands(root, app, databaseCommandSpecs(app.Config))
	root.AddCommand(appCommand("db-backup", "Dump all databases to db-backup.sql.gz", cobra.NoArgs, func(ctx context.Context, args []string) error {
		return app.backupDatabases(ctx)
	}))
	root.AddCommand(appCommand("db-restore", "Restore from db-backup.sql.gz", cobra.NoArgs, func(ctx context.Context, args []string) error {
		return app.restoreDatabases(ctx)
	}))
}

func addToolCommands(root *cobra.Command, app *App) {
	addComposeCommands(root, app, redisCommandSpecs(app.Config))
	root.AddCommand(appCommand("debug [off|debug|profile]", "Set Xdebug mode", cobra.MaximumNArgs(1), func(ctx context.Context, args []string) error {
		return app.setXdebugMode(ctx, args)
	}))
	root.AddCommand(appCommand("install", "Install CLI and completions", cobra.NoArgs, func(ctx context.Context, args []string) error {
		if err := app.install(); err != nil {
			return err
		}
		return installCompletions(root)
	}))
	root.AddCommand(appCommand("dir", "Print script directory", cobra.NoArgs, func(ctx context.Context, args []string) error {
		fmt.Fprintln(app.Out, app.Config.ScriptDir)
		return nil
	}))
}

func newCompletionCommand() *cobra.Command {
	completion := &cobra.Command{
		Use:   "completion [bash|fish]",
		Short: "Generate shell completion script",
		Args: func(cmd *cobra.Command, args []string) error {
			if len(args) != 1 {
				return errors.New("expected bash or fish")
			}
			if args[0] != "bash" && args[0] != "fish" {
				return errors.New("expected bash or fish")
			}
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			switch args[0] {
			case "bash":
				return cmd.Root().GenBashCompletion(cmd.OutOrStdout())
			case "fish":
				return writeFishCompletion(cmd.Root(), cmd.OutOrStdout())
			}
			return nil
		},
	}
	completion.AddCommand(&cobra.Command{
		Use:   "install",
		Short: "Install bash and fish completions",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return installCompletions(cmd.Root())
		},
	})
	return completion
}

func installCompletions(root *cobra.Command) error {
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	fishDir := filepath.Join(home, ".config", "fish", "completions")
	bashDir := filepath.Join(home, ".local", "share", "bash-completion", "completions")
	if err := ensurePrivateDir(fishDir); err != nil {
		return err
	}
	if err := ensurePrivateDir(bashDir); err != nil {
		return err
	}
	fishFile := filepath.Join(fishDir, "web.fish")
	bashFile := filepath.Join(bashDir, "web")
	if err := removePathIfPresent(fishFile); err != nil {
		return err
	}
	if err := removePathIfPresent(bashFile); err != nil {
		return err
	}
	if err := writeFishCompletionFile(root, fishFile); err != nil {
		return err
	}
	return root.GenBashCompletionFile(bashFile)
}

func writeFishCompletionFile(root *cobra.Command, path string) error {
	var out bytes.Buffer
	if err := writeFishCompletion(root, &out); err != nil {
		return err
	}
	return writeFileAtomic(path, out.Bytes(), 0644)
}

func writeFishCompletion(root *cobra.Command, output io.Writer) error {
	var out bytes.Buffer
	if err := root.GenFishCompletion(&out, true); err != nil {
		return err
	}
	_, err := output.Write(fishCompletionWithoutComments(out.String()))
	return err
}

func fishCompletionWithoutComments(content string) []byte {
	var out strings.Builder
	for _, line := range strings.SplitAfter(content, "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		out.WriteString(line)
	}
	return []byte(strings.TrimLeft(out.String(), "\n"))
}

func removePathIfPresent(path string) error {
	if _, err := os.Lstat(path); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	return os.Remove(path)
}
