package web

import (
	"encoding/json"
	"fmt"
	"os"
)

type Registry struct {
	Output   string      `json:"output"`
	Template string      `json:"template"`
	WebRoot  string      `json:"WEB_ROOT"`
	HTTPS    bool        `json:"https"`
	Hosts    []HostEntry `json:"hosts"`
}

type HostEntry struct {
	Name string `json:"name"`
	Type string `json:"type"`
	DB   string `json:"db"`
}

func DefaultRegistry(cfg Config) Registry {
	return Registry{
		Output:   cfg.BackendSitesDir,
		Template: cfg.BackendConfigDir + string(os.PathSeparator) + cfg.ResolvedValues().Files.CaddyTemplate,
		WebRoot:  cfg.WebRoot,
		Hosts:    []HostEntry{},
	}
}

func LoadRegistry(path string) (Registry, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Registry{}, err
	}
	var registry Registry
	if err := json.Unmarshal(data, &registry); err != nil {
		return Registry{}, err
	}
	if registry.Hosts == nil {
		registry.Hosts = []HostEntry{}
	}
	return registry, nil
}

func EnsureRegistry(cfg Config) (Registry, error) {
	registry, err := LoadRegistry(cfg.HostsJSON)
	if err == nil {
		return registry, nil
	}
	if !os.IsNotExist(err) {
		return Registry{}, err
	}
	registry = DefaultRegistry(cfg)
	if err := SaveRegistry(cfg.HostsJSON, registry); err != nil {
		return Registry{}, err
	}
	return registry, nil
}

func SaveRegistry(path string, registry Registry) error {
	data, err := json.MarshalIndent(registry, "", "    ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return writeFileAtomic(path, data, 0644)
}

func (r Registry) Host(name string) (HostEntry, bool) {
	for _, host := range r.Hosts {
		if host.Name == name {
			return host, true
		}
	}
	return HostEntry{}, false
}

func (r Registry) DB(name string) string {
	host, ok := r.Host(name)
	if !ok {
		return ""
	}
	return host.DB
}

func (r *Registry) Add(host HostEntry) error {
	if !ValidHostname(host.Name) {
		return fmt.Errorf("invalid hostname %q", host.Name)
	}
	if _, ok := r.Host(host.Name); ok {
		return fmt.Errorf("host %s already exists", host.Name)
	}
	r.Hosts = append(r.Hosts, host)
	return nil
}

func (r *Registry) Remove(name string) {
	out := r.Hosts[:0]
	for _, host := range r.Hosts {
		if host.Name != name {
			out = append(out, host)
		}
	}
	r.Hosts = out
}
