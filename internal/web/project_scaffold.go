package web

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func (a *App) scaffoldWordPress(ctx context.Context, host string, dbName string) error {
	archive := filepath.Join(a.Config.WebRoot, "wordpress.tar.gz")
	path := filepath.Join(a.Config.WebRoot, host)
	if _, err := os.Stat(path); err == nil {
		return fmt.Errorf("WordPress %s already exists", path)
	} else if !os.IsNotExist(err) {
		return err
	}
	if !commandExists("curl") {
		return fmt.Errorf("curl is not installed")
	}
	if !commandExists("tar") {
		return fmt.Errorf("tar is not installed")
	}
	fmt.Fprintf(a.Out, "Creating WordPress project: %s\n", path)
	if _, err := os.Stat(archive); os.IsNotExist(err) {
		if err := a.Runner.Run(ctx, "curl", "-fsSL", "https://en-gb.wordpress.org/latest-en_GB.tar.gz", "-o", archive); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	if err := os.MkdirAll(a.Config.WebRoot, 0755); err != nil {
		return err
	}
	tmp, err := os.MkdirTemp(a.Config.WebRoot, ".web-wordpress-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	if err := a.Runner.Run(ctx, "tar", "-xzf", archive, "-C", tmp); err != nil {
		return err
	}
	if err := os.MkdirAll(path, 0755); err != nil {
		return err
	}
	entries, err := os.ReadDir(filepath.Join(tmp, "wordpress"))
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if err := os.Rename(filepath.Join(tmp, "wordpress", entry.Name()), filepath.Join(path, entry.Name())); err != nil {
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
	content = strings.ReplaceAll(content, "password_here", "secret")
	content = strings.ReplaceAll(content, "localhost", "mariadb")
	return os.WriteFile(conf, []byte(content), 0644)
}

func (a *App) scaffoldLaravel(ctx context.Context, host string, dbName string, scheme string) error {
	path := filepath.Join(a.Config.WebRoot, host)
	if _, err := os.Stat(path); err == nil {
		return fmt.Errorf("Laravel project %s already exists", path)
	} else if !os.IsNotExist(err) {
		return err
	}
	fmt.Fprintf(a.Out, "Creating Laravel project: %s\n", path)
	if err := a.runQuiet(ctx, "composer", "create-project", "--quiet", "--prefer-dist", "laravel/laravel", path); err != nil {
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
			lines[i] = "DB_HOST=mariadb"
		case strings.HasPrefix(line, "# DB_PORT="):
			lines[i] = "DB_PORT=3306"
		case strings.HasPrefix(line, "# DB_DATABASE="):
			lines[i] = "DB_DATABASE=" + dbName
		case strings.HasPrefix(line, "# DB_USERNAME="):
			lines[i] = "DB_USERNAME=" + dbName
		case strings.HasPrefix(line, "# DB_PASSWORD="):
			lines[i] = "DB_PASSWORD=secret"
		}
	}
	return os.WriteFile(envPath, []byte(strings.Join(lines, "\n")), 0644)
}
