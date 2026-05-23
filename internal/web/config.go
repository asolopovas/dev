package web

import (
	"os"
	"path/filepath"
	"strings"
)

type Config struct {
	WebRoot          string
	ScriptDir        string
	BackendDir       string
	BackendConfigDir string
	BackendSitesDir  string
	HostsJSON        string
	CertsDir         string
	RootKey          string
	RootCrt          string
	ComposeFiles     []string
}

func LoadConfig() Config {
	home, _ := os.UserHomeDir()
	webRoot := getenv("WEB_ROOT", filepath.Join(home, "www"))
	scriptDir := getenv("SCRIPT_DIR", filepath.Join(home, "www", "dev"))
	backendDir := getenv("BACKEND_DIR", filepath.Join(scriptDir, "franken_php"))
	backendConfigDir := filepath.Join(backendDir, "config")
	backendSitesDir := filepath.Join(backendConfigDir, "sites")
	hostsJSON := getenv("HOSTS_JSON", filepath.Join(scriptDir, "web-hosts.json"))
	certsDir := filepath.Join(backendConfigDir, "ssl")
	composeFiles := []string{filepath.Join(scriptDir, "docker-compose.yml")}
	templates := filepath.Join(scriptDir, "templates.yml")
	if b, err := os.ReadFile(templates); err == nil && strings.Contains(string(b), "  franken_php:") {
		composeFiles = append(composeFiles, templates)
	}
	return Config{
		WebRoot:          webRoot,
		ScriptDir:        scriptDir,
		BackendDir:       backendDir,
		BackendConfigDir: backendConfigDir,
		BackendSitesDir:  backendSitesDir,
		HostsJSON:        hostsJSON,
		CertsDir:         certsDir,
		RootKey:          filepath.Join(certsDir, "rootCA.key"),
		RootCrt:          filepath.Join(certsDir, "rootCA.crt"),
		ComposeFiles:     composeFiles,
	}
}

func getenv(name string, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}
