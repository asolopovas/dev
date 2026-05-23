package web

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type workflowRunner struct {
	runs    []string
	outputs []string
}

func (r *workflowRunner) Run(ctx context.Context, name string, args ...string) error {
	r.runs = append(r.runs, name+" "+strings.Join(args, " "))
	return nil
}

func (r *workflowRunner) Output(ctx context.Context, name string, args ...string) ([]byte, error) {
	r.outputs = append(r.outputs, name+" "+strings.Join(args, " "))
	return []byte("ok"), nil
}

func (r *workflowRunner) Pipe(ctx context.Context, input []byte, name string, args ...string) ([]byte, error) {
	return []byte(""), nil
}

func testHostWorkflowConfig(dir string) Config {
	return Config{
		WebRoot:          filepath.Join(dir, "www"),
		ScriptDir:        dir,
		BackendConfigDir: filepath.Join(dir, "franken_php", "config"),
		BackendSitesDir:  filepath.Join(dir, "franken_php", "config", "sites"),
		HostsJSON:        filepath.Join(dir, "web-hosts.json"),
		CertsDir:         filepath.Join(dir, "franken_php", "config", "ssl"),
		ComposeFiles:     []string{filepath.Join(dir, "docker-compose.yml")},
	}
}

func TestRemoveHostByNameRejectsUnknownHost(t *testing.T) {
	dir := t.TempDir()
	app := &App{
		Config: testHostWorkflowConfig(dir),
		Out:    &bytes.Buffer{},
		Err:    &bytes.Buffer{},
		In:     strings.NewReader(""),
	}
	err := app.removeHostByName(context.Background(), "test.test", true)
	if err == nil || !strings.Contains(err.Error(), "host test.test is not configured") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestRemoveHostByNameRemovesUnconfiguredProject(t *testing.T) {
	dir := t.TempDir()
	cfg := testHostWorkflowConfig(dir)
	project := filepath.Join(cfg.WebRoot, "test.test")
	cert := filepath.Join(cfg.CertsDir, "test.test.crt")
	site := filepath.Join(cfg.BackendSitesDir, "test.test.conf")
	for _, path := range []string{project, filepath.Dir(cert), filepath.Dir(site)} {
		if err := os.MkdirAll(path, 0755); err != nil {
			t.Fatal(err)
		}
	}
	for _, path := range []string{cert, site} {
		if err := os.WriteFile(path, []byte("x"), 0644); err != nil {
			t.Fatal(err)
		}
	}
	runner := &workflowRunner{}
	app := &App{Config: cfg, Runner: runner, Out: &bytes.Buffer{}, Err: &bytes.Buffer{}, In: strings.NewReader("")}
	if err := app.removeHostByName(context.Background(), "test.test", false); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{project, cert, site} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatalf("expected %s to be removed, got %v", path, err)
		}
	}
	if len(runner.runs) == 0 || !strings.Contains(runner.runs[len(runner.runs)-1], "test.test") {
		t.Fatalf("expected host redirect removal, got %#v", runner.runs)
	}
}

func TestNewHostRejectsConfiguredHostBeforeScaffold(t *testing.T) {
	dir := t.TempDir()
	cfg := testHostWorkflowConfig(dir)
	if err := SaveRegistry(cfg.HostsJSON, Registry{Hosts: []HostEntry{{Name: "test.test", Type: "laravel", DB: "test_laravel"}}}); err != nil {
		t.Fatal(err)
	}
	runner := &workflowRunner{}
	app := &App{Config: cfg, Runner: runner, Out: &bytes.Buffer{}, Err: &bytes.Buffer{}, In: strings.NewReader("")}
	err := app.newHost(context.Background(), "test.test", "laravel", "")
	if err == nil || !strings.Contains(err.Error(), "host test.test already exists") {
		t.Fatalf("unexpected error: %v", err)
	}
	for _, run := range runner.runs {
		if strings.Contains(run, "composer") {
			t.Fatalf("unexpected scaffold command: %#v", runner.runs)
		}
	}
}
