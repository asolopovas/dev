package web

import (
	"bytes"
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
