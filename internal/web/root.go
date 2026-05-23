package web

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"
)

func NewRootCommand(out io.Writer, errw io.Writer, in io.Reader) *cobra.Command {
	app, appErr := NewApp(out, errw)
	if appErr == nil {
		app.In = in
		app.Runner = ExecRunner{Stdout: out, Stderr: errw, Stdin: in}
	}
	root := &cobra.Command{
		Use:           "web",
		Short:         "Docker PHP development environment",
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmd.Help()
		},
	}
	root.SetOut(out)
	root.SetErr(errw)
	root.SetIn(in)
	root.CompletionOptions.DisableDefaultCmd = true
	if appErr != nil {
		root.PersistentPreRunE = func(cmd *cobra.Command, args []string) error { return appErr }
		return root
	}
	addEnvironmentCommands(root, app)
	addHostCommands(root, app)
	addShellCommands(root, app)
	addSSLCommands(root, app)
	addDatabaseCommands(root, app)
	addToolCommands(root, app)
	root.AddCommand(newCompletionCommand())
	return root
}

func Execute(args []string, out io.Writer, errw io.Writer, in io.Reader) error {
	cmd := NewRootCommand(out, errw, in)
	cmd.SetArgs(args)
	return cmd.Execute()
}

func addEnvironmentCommands(root *cobra.Command, app *App) {
	for _, action := range []string{"up", "down", "stop", "restart"} {
		action := action
		root.AddCommand(&cobra.Command{
			Use:   action + " [service]",
			Short: action + " Docker services",
			Args:  cobra.ArbitraryArgs,
			RunE: func(cmd *cobra.Command, args []string) error {
				return app.dcAction(context.Background(), action, args)
			},
		})
	}
	var noCache bool
	build := &cobra.Command{
		Use:   "build [service]",
		Short: "Build services",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			buildArgs := append([]string{}, args...)
			if noCache {
				buildArgs = append(buildArgs, "--no-cache")
			}
			return app.dcBuild(context.Background(), buildArgs)
		},
	}
	build.Flags().BoolVar(&noCache, "no-cache", false, "Build without cache")
	root.AddCommand(build)
	root.AddCommand(&cobra.Command{
		Use:   "ps [service]",
		Short: "Container status",
		Args:  cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.requireDockerThen(context.Background(), func() error { return app.dockerCompose(context.Background(), append([]string{"ps"}, args...)...) })
		},
	})
	root.AddCommand(&cobra.Command{
		Use:   "log <service>",
		Short: "View service logs",
		Args:  cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.requireDockerThen(context.Background(), func() error {
				return app.dockerCompose(context.Background(), append([]string{"logs", "-f"}, args...)...)
			})
		},
	})
}

func addHostCommands(root *cobra.Command, app *App) {
	var hostType string
	newHost := &cobra.Command{
		Use:   "new-host [host]",
		Short: "Create site",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			if len(args) == 0 {
				return app.newHostWizard(context.Background())
			}
			return app.newHost(context.Background(), args[0], hostType, "")
		},
	}
	newHost.Flags().StringVarP(&hostType, "type", "t", "wp", "Site type")
	root.AddCommand(newHost)
	root.AddCommand(&cobra.Command{
		Use:   "remove-host [host]",
		Short: "Remove site",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			if len(args) == 0 {
				return app.removeHostInteractive(context.Background())
			}
			if !app.confirm(fmt.Sprintf("Remove %s?", args[0])) {
				return nil
			}
			if err := app.removeHost(context.Background(), args[0]); err != nil {
				return err
			}
			return app.buildWebconf(context.Background())
		},
	})
	root.AddCommand(&cobra.Command{
		Use:   "build-webconf",
		Short: "Regenerate Caddy configs",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.buildWebconf(context.Background())
		},
	})
}

func addShellCommands(root *cobra.Command, app *App) {
	root.AddCommand(&cobra.Command{
		Use:   "bash",
		Short: "Container Bash",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.requireDockerThen(context.Background(), func() error { return app.dockerCompose(context.Background(), "exec", "franken_php", "bash") })
		},
	})
	root.AddCommand(&cobra.Command{
		Use:   "fish",
		Short: "Container Fish",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.requireDockerThen(context.Background(), func() error { return app.dockerCompose(context.Background(), "exec", "franken_php", "fish") })
		},
	})
}

func addSSLCommands(root *cobra.Command, app *App) {
	root.AddCommand(&cobra.Command{
		Use:   "rootssl",
		Short: "Generate root CA",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			if err := app.requireDocker(context.Background()); err != nil {
				return err
			}
			if err := app.sslGenerateRoot(context.Background(), "rootCA", "default"); err != nil {
				return err
			}
			return app.dockerCompose(context.Background(), "restart", "franken_php")
		},
	})
	root.AddCommand(&cobra.Command{
		Use:   "hostssl <host>",
		Short: "Generate host SSL",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.sslGenerateHost(context.Background(), args[0])
		},
	})
	root.AddCommand(&cobra.Command{
		Use:   "import-rootca",
		Short: "Import root CA to Chrome",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.sslImportRoot(context.Background(), app.Config.RootCrt, "Lyntouch Root CA")
		},
	})
}

func addDatabaseCommands(root *cobra.Command, app *App) {
	root.AddCommand(&cobra.Command{
		Use:   "mysql",
		Short: "MySQL client as root",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.requireDockerThen(context.Background(), func() error {
				return app.dockerCompose(context.Background(), "exec", "-e", "MYSQL_PWD=secret", "mariadb", "mariadb", "-uroot")
			})
		},
	})
	root.AddCommand(&cobra.Command{
		Use:   "db-backup",
		Short: "Dump all databases to db-backup.sql.gz",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.dbBackup(context.Background())
		},
	})
	root.AddCommand(&cobra.Command{
		Use:   "db-restore",
		Short: "Restore from db-backup.sql.gz",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.dbRestore(context.Background())
		},
	})
}

func addToolCommands(root *cobra.Command, app *App) {
	root.AddCommand(&cobra.Command{
		Use:   "redis-cli",
		Short: "Redis CLI shell",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.requireDockerThen(context.Background(), func() error { return app.dockerCompose(context.Background(), "exec", "redis", "redis-cli") })
		},
	})
	root.AddCommand(&cobra.Command{
		Use:   "redis-flush",
		Short: "Flush Redis",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.requireDockerThen(context.Background(), func() error { return app.dockerCompose(context.Background(), "exec", "redis", "redis-cli", "flushall") })
		},
	})
	root.AddCommand(&cobra.Command{
		Use:   "redis-monitor",
		Short: "Monitor Redis",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.requireDockerThen(context.Background(), func() error { return app.dockerCompose(context.Background(), "exec", "redis", "redis-cli", "monitor") })
		},
	})
	root.AddCommand(&cobra.Command{
		Use:   "debug [off|debug|profile]",
		Short: "Set Xdebug mode",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return app.setDebugMode(context.Background(), args)
		},
	})
	root.AddCommand(&cobra.Command{
		Use:   "install",
		Short: "Create CLI symlinks and completions",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			if err := app.install(); err != nil {
				return err
			}
			return installCompletions(cmd.Root())
		},
	})
	root.AddCommand(&cobra.Command{
		Use:   "dir",
		Short: "Print script directory",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Fprintln(app.Out, app.Config.ScriptDir)
			return nil
		},
	})
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
				return cmd.Root().GenFishCompletion(cmd.OutOrStdout(), true)
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
	if err := os.MkdirAll(fishDir, 0755); err != nil {
		return err
	}
	if err := os.MkdirAll(bashDir, 0755); err != nil {
		return err
	}
	if err := root.GenFishCompletionFile(filepath.Join(fishDir, "web.fish"), true); err != nil {
		return err
	}
	return root.GenBashCompletionFile(filepath.Join(bashDir, "web"))
}
