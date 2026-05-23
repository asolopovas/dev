package web

import (
	"bytes"
	"context"
	"path/filepath"
	"strings"
	"testing"
)

func TestRemoveHostByNameRejectsUnknownHost(t *testing.T) {
	dir := t.TempDir()
	app := &App{
		Config: Config{
			WebRoot:          filepath.Join(dir, "www"),
			ScriptDir:        dir,
			BackendConfigDir: filepath.Join(dir, "franken_php", "config"),
			BackendSitesDir:  filepath.Join(dir, "franken_php", "config", "sites"),
			HostsJSON:        filepath.Join(dir, "web-hosts.json"),
			CertsDir:         filepath.Join(dir, "franken_php", "config", "ssl"),
		},
		Out: &bytes.Buffer{},
		Err: &bytes.Buffer{},
		In:  strings.NewReader(""),
	}
	err := app.removeHostByName(context.Background(), "test.test", true)
	if err == nil || !strings.Contains(err.Error(), "host test.test is not configured") {
		t.Fatalf("unexpected error: %v", err)
	}
}
