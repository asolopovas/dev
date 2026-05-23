package web

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
)

type Runner interface {
	Run(ctx context.Context, name string, args ...string) error
	Output(ctx context.Context, name string, args ...string) ([]byte, error)
	Pipe(ctx context.Context, input []byte, name string, args ...string) ([]byte, error)
}

type ExecRunner struct {
	Stdout io.Writer
	Stderr io.Writer
	Stdin  io.Reader
}

func (r ExecRunner) Run(ctx context.Context, name string, args ...string) error {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdout = r.Stdout
	cmd.Stderr = r.Stderr
	cmd.Stdin = r.Stdin
	return cmd.Run()
}

func (r ExecRunner) Output(ctx context.Context, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stderr = r.Stderr
	return cmd.Output()
}

func (r ExecRunner) Pipe(ctx context.Context, input []byte, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdin = bytes.NewReader(input)
	cmd.Stderr = r.Stderr
	return cmd.Output()
}

func commandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func writeFileAtomic(path string, data []byte, mode os.FileMode) error {
	file, err := os.CreateTemp(filepathDir(path), ".tmp-*")
	if err != nil {
		return err
	}
	tmp := file.Name()
	ok := false
	defer func() {
		if !ok {
			_ = os.Remove(tmp)
		}
	}()
	if _, err := file.Write(data); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Chmod(mode); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		return err
	}
	ok = true
	return nil
}

func filepathDir(path string) string {
	dir := "."
	for i := len(path) - 1; i >= 0; i-- {
		if path[i] == os.PathSeparator {
			if i == 0 {
				return string(os.PathSeparator)
			}
			return path[:i]
		}
	}
	return dir
}

func wrapCommandError(name string, args []string, err error) error {
	if err == nil {
		return nil
	}
	return fmt.Errorf("%s %v failed: %w", name, args, err)
}
