package web

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestWriteTemplates(t *testing.T) {
	dir := t.TempDir()
	app := &App{Config: Config{ScriptDir: dir}, Out: &bytes.Buffer{}, Err: &bytes.Buffer{}}
	if err := app.writeComposeAliases([]HostEntry{{Name: "bar.test"}, {Name: "foo.test"}}); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(dir, "templates.yml"))
	if err != nil {
		t.Fatal(err)
	}
	content := string(data)
	for _, want := range []string{"services:", "aliases:", "          - bar.test", "          - foo.test"} {
		if !strings.Contains(content, want) {
			t.Fatalf("templates.yml missing %q\n%s", want, content)
		}
	}
}

func TestSSLExtFile(t *testing.T) {
	content := hostCertificateExtensionFile("myhost.test")
	for _, want := range []string{"DNS.1 = myhost.test", "IP.1 = 127.0.0.1", "subjectAltName"} {
		if !strings.Contains(content, want) {
			t.Fatalf("hostCertificateExtensionFile missing %q", want)
		}
	}
}

func TestWriteSiteConfigurationSkipsCertificateGenerationWhenHTTPSDisabled(t *testing.T) {
	dir := t.TempDir()
	cfg := siteConfigTestConfig(t, dir)
	runner := &workflowRunner{}
	app := &App{Config: cfg, Runner: runner, Out: &bytes.Buffer{}, Err: &bytes.Buffer{}}
	if err := app.writeSiteConfiguration(context.Background(), HostEntry{Name: "plain.test", Type: "laravel", DB: "plain_db"}, false); err != nil {
		t.Fatal(err)
	}
	for _, output := range runner.outputs {
		if strings.HasPrefix(output, "openssl ") {
			t.Fatalf("unexpected certificate generation: %#v", runner.outputs)
		}
	}
	data, err := os.ReadFile(filepath.Join(cfg.BackendSitesDir, "plain.test.conf"))
	if err != nil {
		t.Fatal(err)
	}
	content := string(data)
	for _, want := range []string{"tls internal", "redir http://plain.test{uri}"} {
		if !strings.Contains(content, want) {
			t.Fatalf("config missing %q\n%s", want, content)
		}
	}
	if strings.Contains(content, "/etc/caddy/ssl/plain.test") {
		t.Fatalf("http mode should not reference generated certificate files\n%s", content)
	}
}

func TestWriteSiteConfigurationGeneratesCertificatesWhenHTTPSEnabled(t *testing.T) {
	dir := t.TempDir()
	cfg := siteConfigTestConfig(t, dir)
	runner := &workflowRunner{}
	app := &App{Config: cfg, Runner: runner, Out: &bytes.Buffer{}, Err: &bytes.Buffer{}}
	if err := app.writeSiteConfiguration(context.Background(), HostEntry{Name: "secure.test", Type: "wp", DB: "secure_db"}, true); err != nil {
		t.Fatal(err)
	}
	generated := false
	for _, output := range runner.outputs {
		if strings.HasPrefix(output, "openssl ") {
			generated = true
		}
	}
	if !generated {
		t.Fatalf("expected certificate generation: %#v", runner.outputs)
	}
	data, err := os.ReadFile(filepath.Join(cfg.BackendSitesDir, "secure.test.conf"))
	if err != nil {
		t.Fatal(err)
	}
	content := string(data)
	for _, want := range []string{"tls /etc/caddy/ssl/secure.test.crt /etc/caddy/ssl/secure.test.key", "https://secure.test", "php_server"} {
		if !strings.Contains(content, want) {
			t.Fatalf("config missing %q\n%s", want, content)
		}
	}
}

func siteConfigTestConfig(t *testing.T, dir string) Config {
	t.Helper()
	cfg := testHostWorkflowConfig(dir)
	cfg.RootKey = filepath.Join(cfg.CertsDir, "rootCA.key")
	cfg.RootCrt = filepath.Join(cfg.CertsDir, "rootCA.crt")
	for _, path := range []string{cfg.WebRoot, cfg.BackendConfigDir, cfg.BackendSitesDir, cfg.CertsDir} {
		if err := os.MkdirAll(path, 0755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(cfg.BackendConfigDir, "template.conf"), []byte("http://${APP_URL} {\n    root * ${SERVE_ROOT}\n    import /etc/caddy/cors.conf\n\n    php_server\n}\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(cfg.ScriptDir, "launch.json"), []byte("{}\n"), 0644); err != nil {
		t.Fatal(err)
	}
	return cfg
}
