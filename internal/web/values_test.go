package web

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadAppValuesAppliesJSONOverrides(t *testing.T) {
	dir := t.TempDir()
	data := []byte(`{"services":{"frankenPHP":"php_runtime"},"files":{"templates":"aliases.yml"},"hosts":{"phpMyAdmin":"pma.test"}}`)
	if err := os.WriteFile(filepath.Join(dir, fileValuesOverride), data, 0644); err != nil {
		t.Fatal(err)
	}
	values := LoadAppValues(dir)
	if values.Services.FrankenPHP != "php_runtime" {
		t.Fatalf("unexpected frankenPHP service: %s", values.Services.FrankenPHP)
	}
	if values.Files.Templates != "aliases.yml" {
		t.Fatalf("unexpected templates file: %s", values.Files.Templates)
	}
	if values.Hosts.PhpMyAdmin != "pma.test" {
		t.Fatalf("unexpected phpMyAdmin host: %s", values.Hosts.PhpMyAdmin)
	}
	if values.Services.MariaDB != serviceMariaDB {
		t.Fatalf("default mariadb service was not preserved: %s", values.Services.MariaDB)
	}
}
