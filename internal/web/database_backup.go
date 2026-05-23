package web

import (
	"bytes"
	"context"
	"fmt"
	"path/filepath"
)

func (a *App) backupDatabases(ctx context.Context) error {
	if err := a.requireDocker(ctx); err != nil {
		return err
	}
	out, err := a.dockerComposeOutput(ctx, mysqlRootDumpArgs(a.Config)...)
	if err != nil {
		return err
	}
	var gz bytes.Buffer
	if err := gzipData(&gz, out); err != nil {
		return err
	}
	path := filepath.Join(a.Config.ScriptDir, a.Config.ResolvedValues().Files.DatabaseBackup)
	if err := writePrivateFile(path, gz.Bytes()); err != nil {
		return err
	}
	fmt.Fprintf(a.Out, "Backed up to %s\n", path)
	return nil
}

func (a *App) restoreDatabases(ctx context.Context) error {
	if err := a.requireDocker(ctx); err != nil {
		return err
	}
	path := filepath.Join(a.Config.ScriptDir, a.Config.ResolvedValues().Files.DatabaseBackup)
	data, err := gunzipFile(path)
	if err != nil {
		return err
	}
	args := a.composeArgs(mysqlRootArgs(a.Config)...)
	out, err := a.Runner.Pipe(ctx, data, a.Config.ResolvedValues().Tools.Docker, args...)
	if len(out) > 0 {
		_, _ = a.Out.Write(out)
	}
	if err != nil {
		return err
	}
	fmt.Fprintln(a.Out, "Restore complete")
	return nil
}
