package web

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestBinaryWorkflowE2EWithFakeTools(t *testing.T) {
	dir := t.TempDir()
	scriptDir := filepath.Join(dir, "dev")
	webRoot := filepath.Join(dir, "www")
	binDir := filepath.Join(dir, "bin")
	home := filepath.Join(dir, "home")
	for _, path := range []string{
		filepath.Join(scriptDir, "franken_php", "config", "sites"),
		filepath.Join(scriptDir, "franken_php", "config", "ssl"),
		webRoot,
		binDir,
		home,
	} {
		if err := os.MkdirAll(path, 0755); err != nil {
			t.Fatal(err)
		}
	}
	writeTestFile(t, filepath.Join(scriptDir, "docker-compose.yml"), "services: {}\n")
	writeTestFile(t, filepath.Join(scriptDir, "franken_php", "config", "template.conf"), "site ${APP_URL} root ${SERVE_ROOT}\n")
	writeTestFile(t, filepath.Join(scriptDir, "franken_php", "config", "sites", "phpmyadmin.test.conf"), "phpmyadmin\n")
	writeTestFile(t, filepath.Join(scriptDir, "launch.json"), "{\"name\":\"${HOSTNAME}\"}\n")
	writeTestFile(t, filepath.Join(scriptDir, ".env"), "XDEBUG_MODE=debug\n")
	createWordPressArchive(t, filepath.Join(webRoot, "wordpress.tar.gz"))
	logPath := filepath.Join(dir, "e2e.log")
	fakeHosts := filepath.Join(dir, "hosts")
	writeTestFile(t, fakeHosts, "")
	writeExecutable(t, filepath.Join(binDir, "docker"), fakeDockerScript())
	writeExecutable(t, filepath.Join(binDir, "sudo"), fakeSudoScript())
	writeExecutable(t, filepath.Join(binDir, "openssl"), fakeOpenSSLScript())
	writeExecutable(t, filepath.Join(binDir, "composer"), fakeComposerScript())
	writeExecutable(t, filepath.Join(binDir, "gum"), fakeGumScript())
	writeExecutable(t, filepath.Join(binDir, "certutil"), fakeCertutilScript())
	t.Setenv("SCRIPT_DIR", scriptDir)
	t.Setenv("WEB_ROOT", webRoot)
	t.Setenv("HOSTS_JSON", filepath.Join(scriptDir, "web-hosts.json"))
	t.Setenv("PATH", binDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("E2E_LOG", logPath)
	t.Setenv("FAKE_HOSTS", fakeHosts)
	t.Setenv("HOME", home)
	var out bytes.Buffer
	var errb bytes.Buffer
	app, err := NewApp(&out, &errb)
	if err != nil {
		t.Fatal(err)
	}
	commands := [][]string{
		{"help"},
		{"dir"},
		{"ps"},
		{"up"},
		{"stop", "redis"},
		{"restart", "franken_php"},
		{"build", "franken_php", "--no-cache"},
		{"log", "franken_php"},
		{"build-webconf"},
		{"rootssl"},
		{"hostssl", "manual.test"},
		{"import-rootca"},
		{"new-host", "e2ewp.test", "-t", "wp"},
		{"new-host", "e2elaravel.test", "-t", "laravel"},
		{"remove-host", "e2ewp.test", "--yes"},
		{"debug", "off"},
		{"mysql"},
		{"db-backup"},
		{"db-restore"},
		{"redis-cli"},
		{"redis-flush"},
		{"bash"},
		{"fish"},
		{"down"},
	}
	for _, command := range commands {
		if err := app.Run(command); err != nil {
			t.Fatalf("web %s failed: %v\nstdout:\n%s\nstderr:\n%s", strings.Join(command, " "), err, out.String(), errb.String())
		}
	}
	assertFileContains(t, filepath.Join(scriptDir, "templates.yml"), "e2elaravel.test")
	assertFileContains(t, filepath.Join(scriptDir, "franken_php", "config", "sites", "e2elaravel.test.conf"), "/var/www/e2elaravel.test/public")
	assertFileContains(t, filepath.Join(webRoot, "e2elaravel.test", ".vscode", "launch.json"), "e2elaravel.test")
	assertFileContains(t, filepath.Join(scriptDir, ".env"), "XDEBUG_MODE=off")
	if _, err := os.Stat(filepath.Join(webRoot, "e2ewp.test")); !os.IsNotExist(err) {
		t.Fatalf("removed WordPress host still exists")
	}
	if _, err := os.Stat(filepath.Join(scriptDir, "db-backup.sql.gz")); err != nil {
		t.Fatal(err)
	}
	assertFileContains(t, logPath, "composer create-project --quiet --prefer-dist laravel/laravel")
}

func writeTestFile(t *testing.T, path string, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
}

func writeExecutable(t *testing.T, path string, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0755); err != nil {
		t.Fatal(err)
	}
}

func assertFileContains(t *testing.T, path string, want string) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), want) {
		t.Fatalf("%s missing %q\n%s", path, want, string(data))
	}
}

func createWordPressArchive(t *testing.T, path string) {
	t.Helper()
	file, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	gz := gzip.NewWriter(file)
	tw := tar.NewWriter(gz)
	content := []byte("define( 'DB_NAME', 'database_name_here' );\ndefine( 'DB_USER', 'username_here' );\ndefine( 'DB_PASSWORD', 'password_here' );\ndefine( 'DB_HOST', 'localhost' );\n")
	if err := tw.WriteHeader(&tar.Header{Name: "wordpress/wp-config-sample.php", Mode: 0644, Size: int64(len(content))}); err != nil {
		t.Fatal(err)
	}
	if _, err := tw.Write(content); err != nil {
		t.Fatal(err)
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gz.Close(); err != nil {
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
}

func fakeDockerScript() string {
	return `#!/usr/bin/env bash
set -euo pipefail
printf 'docker %s\n' "$*" >>"$E2E_LOG"
if [[ "${1:-}" == info ]]; then exit 0; fi
if [[ "${1:-}" == compose ]]; then
  shift
  while [[ $# -gt 0 ]]; do
    if [[ "${1:-}" == -f ]]; then shift 2; continue; fi
    break
  done
  case "${1:-}" in
    ps) printf 'NAME STATUS\nfranken_php running\n' ;;
    logs) printf 'logs\n' ;;
    exec)
      if printf '%s\n' "$*" | grep -q mariadb-dump; then printf 'SQL-DUMP\n'; fi
      ;;
  esac
fi
`
}

func fakeSudoScript() string {
	return `#!/usr/bin/env bash
set -euo pipefail
printf 'sudo %s\n' "$*" >>"$E2E_LOG"
if [[ "${1:-}" == tee ]]; then cat >>"$FAKE_HOSTS"; exit 0; fi
if [[ "${1:-}" == sed ]]; then exit 0; fi
"$@"
`
}

func fakeOpenSSLScript() string {
	return `#!/usr/bin/env bash
set -euo pipefail
printf 'openssl %s\n' "$*" >>"$E2E_LOG"
prev=""
for arg in "$@"; do
  if [[ "$prev" == -out || "$prev" == -keyout ]]; then mkdir -p "$(dirname "$arg")"; printf 'fake\n' >"$arg"; fi
  prev="$arg"
done
`
}

func fakeComposerScript() string {
	return `#!/usr/bin/env bash
set -euo pipefail
printf 'composer %s\n' "$*" >>"$E2E_LOG"
path="${@: -1}"
mkdir -p "$path"
printf 'APP_URL=http://localhost\nDB_CONNECTION=sqlite\n# DB_HOST=127.0.0.1\n# DB_PORT=3306\n# DB_DATABASE=laravel\n# DB_USERNAME=root\n# DB_PASSWORD=\n' >"$path/.env"
`
}

func fakeGumScript() string {
	return `#!/usr/bin/env bash
set -euo pipefail
printf 'gum %s\n' "$*" >>"$E2E_LOG"
case "${1:-}" in
  confirm) exit 0 ;;
  choose) shift; for arg in "$@"; do [[ "$arg" == --* ]] && continue; printf '%s\n' "$arg"; exit 0; done ;;
  input) printf 'input.test\n' ;;
esac
`
}

func fakeCertutilScript() string {
	return `#!/usr/bin/env bash
set -euo pipefail
printf 'certutil %s\n' "$*" >>"$E2E_LOG"
`
}
