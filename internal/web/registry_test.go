package web

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRegistryAddRemoveSaveLoad(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "web-hosts.json")
	registry := Registry{Hosts: []HostEntry{}}
	if err := registry.Add(HostEntry{Name: "alpha.test", Type: "wp", DB: "alpha_wp"}); err != nil {
		t.Fatal(err)
	}
	if err := SaveRegistry(path, registry); err != nil {
		t.Fatal(err)
	}
	loaded, err := LoadRegistry(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := loaded.DB("alpha.test"); got != "alpha_wp" {
		t.Fatalf("DB() = %q", got)
	}
	loaded.Remove("alpha.test")
	if _, ok := loaded.Host("alpha.test"); ok {
		t.Fatal("host was not removed")
	}
}

func TestEnsureRegistryCreatesDefaults(t *testing.T) {
	dir := t.TempDir()
	cfg := Config{
		WebRoot:          filepath.Join(dir, "www"),
		BackendConfigDir: filepath.Join(dir, "franken_php", "config"),
		BackendSitesDir:  filepath.Join(dir, "franken_php", "config", "sites"),
		HostsJSON:        filepath.Join(dir, "web-hosts.json"),
	}
	registry, err := EnsureRegistry(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if registry.WebRoot != cfg.WebRoot {
		t.Fatalf("WebRoot = %q", registry.WebRoot)
	}
	if registry.HTTPS {
		t.Fatal("default registry should disable HTTPS")
	}
	data, err := os.ReadFile(cfg.HostsJSON)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "\"https\": false") {
		t.Fatalf("default registry missing https false\n%s", data)
	}
	if _, err := os.Stat(cfg.HostsJSON); err != nil {
		t.Fatal(err)
	}
}

func TestRegistryRejectsDuplicate(t *testing.T) {
	registry := Registry{Hosts: []HostEntry{}}
	if err := registry.Add(HostEntry{Name: "alpha.test", Type: "wp", DB: "alpha_wp"}); err != nil {
		t.Fatal(err)
	}
	if err := registry.Add(HostEntry{Name: "alpha.test", Type: "wp", DB: "alpha_wp"}); err == nil {
		t.Fatal("expected duplicate error")
	}
}
