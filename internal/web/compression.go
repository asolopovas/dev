package web

import (
	"bytes"
	"compress/gzip"
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

func gzipData(w io.Writer, data []byte) error {
	gz := gzip.NewWriter(w)
	if _, err := gz.Write(data); err != nil {
		_ = gz.Close()
		return err
	}
	return gz.Close()
}

func gunzipFile(path string) ([]byte, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	gz, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	defer gz.Close()
	return io.ReadAll(gz)
}

func (a *App) setXdebugMode(ctx context.Context, args []string) error {
	if err := a.requireDocker(ctx); err != nil {
		return err
	}
	mode := ""
	if len(args) > 0 {
		mode = args[0]
	}
	if mode == "" {
		mode = a.choose("Xdebug mode:", "off", "debug", "profile")
	}
	if mode != "off" && mode != "debug" && mode != "profile" {
		return fmt.Errorf("invalid Xdebug mode %q", mode)
	}
	path := filepath.Join(a.Config.ScriptDir, ".env")
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	lines := strings.Split(string(data), "\n")
	found := false
	for i, line := range lines {
		if strings.HasPrefix(line, "XDEBUG_MODE=") {
			lines[i] = "XDEBUG_MODE=" + mode
			found = true
		}
	}
	if !found {
		lines = append(lines, "XDEBUG_MODE="+mode)
	}
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\n")), 0644); err != nil {
		return err
	}
	return a.dockerCompose(ctx, "up", "-d", "--remove-orphans", "franken_php")
}
