package web

import (
	"os"
	"path/filepath"
	"strings"
)

func mysqlRootArgs(cfg Config, extra ...string) []string {
	values := cfg.ResolvedValues()
	args := []string{"exec", "-T"}
	if credential := mysqlRootCredential(cfg); credential != "" {
		args = append(args, "-e", envMySQLClientCredential+"="+credential)
	}
	args = append(args, values.Services.MariaDB, "mariadb", "-uroot")
	return append(args, extra...)
}

func mysqlRootShellArgs(cfg Config) []string {
	values := cfg.ResolvedValues()
	args := []string{"exec"}
	if credential := mysqlRootCredential(cfg); credential != "" {
		args = append(args, "-e", envMySQLClientCredential+"="+credential)
	}
	return append(args, values.Services.MariaDB, "mariadb", "-uroot")
}

func mysqlRootDumpArgs(cfg Config) []string {
	values := cfg.ResolvedValues()
	args := []string{"exec", "-T"}
	if credential := mysqlRootCredential(cfg); credential != "" {
		args = append(args, "-e", envMySQLClientCredential+"="+credential)
	}
	return append(args, values.Services.MariaDB, "mariadb-dump", "-uroot", "--all-databases")
}

func mysqlRootCredential(cfg Config) string {
	if value := readEnvValue(filepath.Join(cfg.ScriptDir, cfg.ResolvedValues().Files.Env), envMySQLRootCredential); value != "" {
		return value
	}
	return os.Getenv(envMySQLRootCredential)
}

func readEnvValue(path string, name string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	prefix := name + "="
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if value, ok := strings.CutPrefix(line, prefix); ok {
			return strings.Trim(value, "'\"")
		}
	}
	return ""
}
