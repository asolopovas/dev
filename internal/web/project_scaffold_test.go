package web

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type wpScaffoldRunner struct {
	tarDir string
}

func (r *wpScaffoldRunner) Run(ctx context.Context, name string, args ...string) error {
	if name != "tar" {
		return nil
	}
	for i := 0; i < len(args)-1; i++ {
		if args[i] == "-C" {
			r.tarDir = args[i+1]
		}
	}
	path := filepath.Join(r.tarDir, "wordpress")
	if err := os.MkdirAll(path, 0755); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(path, "wp-config-sample.php"), []byte("username_here database_name_here password_here localhost"), 0644)
}

func (r *wpScaffoldRunner) Output(ctx context.Context, name string, args ...string) ([]byte, error) {
	return []byte(""), nil
}

func (r *wpScaffoldRunner) Pipe(ctx context.Context, input []byte, name string, args ...string) ([]byte, error) {
	return []byte(""), nil
}

func TestScaffoldWordPressExtractsInsideWebRoot(t *testing.T) {
	if !commandExists("curl") || !commandExists("tar") {
		t.Skip("curl and tar are required")
	}
	dir := t.TempDir()
	cfg := Config{WebRoot: filepath.Join(dir, "www"), ScriptDir: dir}
	if err := os.MkdirAll(cfg.WebRoot, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(cfg.WebRoot, "wordpress.tar.gz"), []byte("archive"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(cfg.ScriptDir, ".env"), []byte("MYSQL_ROOT_PASSWORD=secret\n"), 0644); err != nil {
		t.Fatal(err)
	}
	runner := &wpScaffoldRunner{}
	app := &App{Config: cfg, Runner: runner, Out: &bytes.Buffer{}, Err: &bytes.Buffer{}}
	if err := app.scaffoldWordPress(context.Background(), "wp.test", "wp_db"); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(runner.tarDir, cfg.WebRoot+string(os.PathSeparator)) {
		t.Fatalf("tar extracted outside web root: %s", runner.tarDir)
	}
	data, err := os.ReadFile(filepath.Join(cfg.WebRoot, "wp.test", "wp-config.php"))
	if err != nil {
		t.Fatal(err)
	}
	content := string(data)
	for _, want := range []string{"root", "wp_db", "secret", "mariadb"} {
		if !strings.Contains(content, want) {
			t.Fatalf("wp-config.php missing %q: %s", want, content)
		}
	}
}
