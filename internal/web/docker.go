package web

import (
	"context"
	"errors"
	"fmt"
)

func (a *App) composeArgs(args ...string) []string {
	out := []string{dockerComposeSubcommand}
	for _, file := range a.Config.ComposeFiles {
		out = append(out, "-f", file)
	}
	return append(out, args...)
}

func (a *App) dockerCompose(ctx context.Context, args ...string) error {
	all := a.composeArgs(args...)
	docker := a.Config.ResolvedValues().Tools.Docker
	return wrapCommandError(docker, all, a.Runner.Run(ctx, docker, all...))
}

func (a *App) dockerComposeQuiet(ctx context.Context, args ...string) error {
	all := a.composeArgs(args...)
	docker := a.Config.ResolvedValues().Tools.Docker
	return wrapCommandError(docker, all, a.runQuiet(ctx, docker, all...))
}

func (a *App) dockerComposeOutput(ctx context.Context, args ...string) ([]byte, error) {
	all := a.composeArgs(args...)
	docker := a.Config.ResolvedValues().Tools.Docker
	out, err := a.Runner.Output(ctx, docker, all...)
	return out, wrapCommandError(docker, all, err)
}

func (a *App) requireDocker(ctx context.Context) error {
	docker := a.Config.ResolvedValues().Tools.Docker
	if !commandExists(docker) {
		return fmt.Errorf("%s is not installed", docker)
	}
	if _, err := a.Runner.Output(ctx, docker, dockerInfoSubcommand); err != nil {
		return errors.New("docker daemon is not running")
	}
	return nil
}

func (a *App) requireDockerThen(ctx context.Context, action func() error) error {
	if err := a.requireDocker(ctx); err != nil {
		return err
	}
	return action()
}

func (a *App) runDockerComposeAction(ctx context.Context, action string, services []string) error {
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
		return a.dockerCompose(ctx, "down")
	} else if err := a.dockerCompose(ctx, append([]string{action}, services...)...); err != nil {
		return err
	}
	fmt.Fprintln(a.Out)
	return a.dockerCompose(ctx, append([]string{"ps"}, services...)...)
}

func (a *App) buildDockerComposeServices(ctx context.Context, args []string) error {
	if err := a.requireDocker(ctx); err != nil {
		return err
	}
	serviceName := ""
	cacheFlag := ""
	if len(args) > 0 {
		serviceName = args[0]
	}
	if len(args) > 1 && args[1] == "--no-cache" {
		cacheFlag = args[1]
	}
	buildArgs := []string{"build"}
	if cacheFlag != "" {
		buildArgs = append(buildArgs, cacheFlag)
	}
	if serviceName != "" {
		buildArgs = append(buildArgs, serviceName)
	}
	if err := a.dockerCompose(ctx, buildArgs...); err != nil {
		return err
	}
	upArgs := []string{"up", "-d", "--remove-orphans"}
	if serviceName != "" {
		upArgs = append(upArgs, serviceName)
	}
	return a.dockerCompose(ctx, upArgs...)
}
