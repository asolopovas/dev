package web

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func (a *App) scaffoldWordPress(ctx context.Context, host string, dbName string) error {
	values := a.Config.ResolvedValues()
	archive := filepath.Join(a.Config.WebRoot, values.WordPress.ArchiveFile)
	path := filepath.Join(a.Config.WebRoot, host)
	if _, err := os.Stat(path); err == nil {
		return fmt.Errorf("wordpress %s already exists", path)
	} else if !os.IsNotExist(err) {
		return err
	}
	if !commandExists(values.Tools.Curl) {
		return fmt.Errorf("%s is not installed", values.Tools.Curl)
	}
	if !commandExists(values.Tools.Tar) {
		return fmt.Errorf("%s is not installed", values.Tools.Tar)
	}
	fmt.Fprintf(a.Out, "Creating WordPress project: %s\n", path)
	if _, err := os.Stat(archive); os.IsNotExist(err) {
		if err := a.Runner.Run(ctx, values.Tools.Curl, "-fsSL", values.WordPress.ArchiveURL, "-o", archive); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	if err := ensurePublicDir(a.Config.WebRoot); err != nil {
		return err
	}
	tmp, err := os.MkdirTemp(a.Config.WebRoot, ".web-wordpress-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	if err := a.Runner.Run(ctx, values.Tools.Tar, "-xzf", archive, "-C", tmp); err != nil {
		return err
	}
	if err := ensurePublicDir(path); err != nil {
		return err
	}
	entries, err := os.ReadDir(filepath.Join(tmp, values.WordPress.ExtractDir))
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if err := os.Rename(filepath.Join(tmp, values.WordPress.ExtractDir, entry.Name()), filepath.Join(path, entry.Name())); err != nil {
			return err
		}
	}
	conf := filepath.Join(path, "wp-config.php")
	if _, err := os.Stat(conf); os.IsNotExist(err) {
		if err := os.Rename(filepath.Join(path, "wp-config-sample.php"), conf); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	data, err := os.ReadFile(conf)
	if err != nil {
		return err
	}
	content := string(data)
	content = strings.ReplaceAll(content, "username_here", "root")
	content = strings.ReplaceAll(content, "database_name_here", dbName)
	credential := mysqlRootCredential(a.Config)
	if credential == "" {
		return fmt.Errorf("%s is not configured", envMySQLRootCredential)
	}
	content = strings.ReplaceAll(content, "password_here", credential)
	content = strings.ReplaceAll(content, "localhost", values.Services.MariaDB)
	return writePublicFile(conf, []byte(content))
}

func (a *App) scaffoldLaravel(ctx context.Context, host string, dbName string, scheme string) error {
	path := filepath.Join(a.Config.WebRoot, host)
	if _, err := os.Stat(path); err == nil {
		return fmt.Errorf("laravel project %s already exists", path)
	} else if !os.IsNotExist(err) {
		return err
	}
	fmt.Fprintf(a.Out, "Creating Laravel project: %s\n", path)
	values := a.Config.ResolvedValues()
	if err := a.runQuiet(ctx, values.Tools.Composer, "create-project", "--quiet", "--prefer-dist", "laravel/laravel", path); err != nil {
		return err
	}
	envPath := filepath.Join(path, ".env")
	data, err := os.ReadFile(envPath)
	if err != nil {
		return err
	}
	lines := strings.Split(string(data), "\n")
	for i, line := range lines {
		switch {
		case strings.HasPrefix(line, "APP_URL="):
			lines[i] = "APP_URL=" + scheme + "://" + host
		case strings.HasPrefix(line, "DB_CONNECTION="):
			lines[i] = "DB_CONNECTION=mysql"
		case strings.HasPrefix(line, "# DB_HOST="):
			lines[i] = "DB_HOST=" + values.Services.MariaDB
		case strings.HasPrefix(line, "# DB_PORT="):
			lines[i] = "DB_PORT=3306"
		case strings.HasPrefix(line, "# DB_DATABASE="):
			lines[i] = "DB_DATABASE=" + dbName
		case strings.HasPrefix(line, "# DB_USERNAME="):
			lines[i] = "DB_USERNAME=" + dbName
		case strings.HasPrefix(line, "# DB_PASSWORD="):
			credential := mysqlRootCredential(a.Config)
			if credential == "" {
				return fmt.Errorf("%s is not configured", envMySQLRootCredential)
			}
			lines[i] = "DB_PASSWORD=" + credential
		}
	}
	return writePrivateFile(envPath, []byte(strings.Join(lines, "\n")))
}
