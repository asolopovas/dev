package web

import (
	"context"
	"fmt"
	"strings"
)

func (a *App) createHostDatabase(ctx context.Context, host HostEntry) error {
	if err := validateDatabaseIdentifier(host.DB); err != nil {
		return err
	}
	credential := mysqlRootCredential(a.Config)
	if credential == "" {
		return fmt.Errorf("%s is not configured", envMySQLRootCredential)
	}
	query := "CREATE USER IF NOT EXISTS '" + host.DB + "'@'%' IDENTIFIED BY '" + credential + "'; CREATE DATABASE IF NOT EXISTS `" + host.DB + "`; GRANT ALL PRIVILEGES ON `" + host.DB + "`.* TO '" + host.DB + "'@'%';"
	return a.dockerCompose(ctx, mysqlRootArgs(a.Config, "-e", query)...)
}

func (a *App) removeDatabase(ctx context.Context, db string) error {
	if db == "" {
		return nil
	}
	if err := validateDatabaseIdentifier(db); err != nil {
		return err
	}
	query := "DROP DATABASE IF EXISTS `" + db + "`; DROP USER IF EXISTS '" + db + "'@'%';"
	return a.dockerCompose(ctx, mysqlRootArgs(a.Config, "-e", query)...)
}

func (a *App) databaseExists(ctx context.Context, db string) (bool, error) {
	if err := validateDatabaseIdentifier(db); err != nil {
		return false, err
	}
	out, err := a.dockerComposeOutput(ctx, mysqlRootArgs(a.Config, "-Nse", "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='"+db+"'")...)
	if err != nil {
		return false, err
	}
	return strings.TrimSpace(string(out)) != "", nil
}

func validateDatabaseIdentifier(name string) error {
	if name == "" || dbIdentRe.MatchString(name) {
		return fmt.Errorf("invalid database identifier %q", name)
	}
	return nil
}
