package web

import (
	"context"
	"strings"
)

func (a *App) createHostDatabase(ctx context.Context, host HostEntry) error {
	query := "CREATE USER IF NOT EXISTS '" + host.DB + "'@'%' IDENTIFIED BY 'secret'; CREATE DATABASE IF NOT EXISTS `" + host.DB + "`; GRANT ALL PRIVILEGES ON `" + host.DB + "`.* TO '" + host.DB + "'@'%';"
	return a.dockerCompose(ctx, "exec", "-T", "-e", "MYSQL_PWD=secret", "mariadb", "mariadb", "-uroot", "-e", query)
}

func (a *App) removeDatabase(ctx context.Context, db string) error {
	if db == "" {
		return nil
	}
	query := "DROP DATABASE IF EXISTS `" + db + "`; DROP USER IF EXISTS '" + db + "'@'%';"
	return a.dockerCompose(ctx, "exec", "-T", "-e", "MYSQL_PWD=secret", "mariadb", "mariadb", "-uroot", "-e", query)
}

func (a *App) databaseExists(ctx context.Context, db string) (bool, error) {
	out, err := a.dockerComposeOutput(ctx, "exec", "-T", "-e", "MYSQL_PWD=secret", "mariadb", "mariadb", "-uroot", "-Nse", "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='"+db+"'")
	if err != nil {
		return false, err
	}
	return strings.TrimSpace(string(out)) != "", nil
}
