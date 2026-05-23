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
	Values           AppValues
}

func LoadConfig() Config {
	home, _ := os.UserHomeDir()
	webRoot := getenv(envWebRoot, filepath.Join(home, "www"))
	scriptDir := getenv(envScriptDir, filepath.Join(home, "www", "dev"))
	values := LoadAppValues(scriptDir)
	backendDir := getenv(envBackendDir, filepath.Join(scriptDir, values.Services.FrankenPHP))
	backendConfigDir := filepath.Join(backendDir, "config")
	backendSitesDir := filepath.Join(backendConfigDir, "sites")
	hostsJSON := getenv(envHostsJSON, filepath.Join(scriptDir, values.Files.HostsJSON))
	certsDir := filepath.Join(backendConfigDir, "ssl")
	composeFiles := []string{filepath.Join(scriptDir, values.Files.Compose)}
	templates := filepath.Join(scriptDir, values.Files.Templates)
	if b, err := os.ReadFile(templates); err == nil && strings.Contains(string(b), "  "+values.Services.FrankenPHP+":") {
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
		RootKey:          filepath.Join(certsDir, values.Certificates.RootName+".key"),
		RootCrt:          filepath.Join(certsDir, values.Certificates.RootName+".crt"),
		ComposeFiles:     composeFiles,
		Values:           values,
	}
}

func getenv(name string, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}
