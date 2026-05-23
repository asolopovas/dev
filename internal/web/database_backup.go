package web

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"path/filepath"
)

func (a *App) backupDatabases(ctx context.Context) error {
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

func (a *App) restoreDatabases(ctx context.Context) error {
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
