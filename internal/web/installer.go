package web

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
)

func (a *App) install() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	dest := "/usr/local/bin/web"
	if err := a.installSystemBinary(exe, dest); err != nil {
		return err
	}
	if err := ensureLocalWebUsesSystem(dest); err != nil {
		return err
	}
	fmt.Fprintf(a.Out, "Installed: web -> %s\n", dest)
	return nil
}

func (a *App) installSystemBinary(source string, dest string) error {
	if sameFile(source, dest) {
		return nil
	}
	ctx := context.Background()
	installArgs := []string{"-m", "0755", source, dest}
	if canInstallWithoutSudo(dest) {
		if err := a.Runner.Run(ctx, "install", installArgs...); err == nil {
			return nil
		}
	}
	if !commandExists("sudo") {
		return fmt.Errorf("installing %s requires elevated permissions and sudo is not installed", dest)
	}
	if askpass := findAskpass(); askpass != "" {
		sudoArgs := append([]string{"-A", "install"}, installArgs...)
		if os.Getenv("SUDO_ASKPASS") != "" {
			return wrapCommandError("sudo", sudoArgs, a.Runner.Run(ctx, "sudo", sudoArgs...))
		}
		envArgs := append([]string{"SUDO_ASKPASS=" + askpass, "sudo"}, sudoArgs...)
		return wrapCommandError("env", envArgs, a.Runner.Run(ctx, "env", envArgs...))
	}
	sudoArgs := append([]string{"-n", "install"}, installArgs...)
	if err := a.Runner.Run(ctx, "sudo", sudoArgs...); err == nil {
		return nil
	}
	return fmt.Errorf("installing %s requires elevated permissions and no askpass helper was found", dest)
}

func canInstallWithoutSudo(dest string) bool {
	const writeAccess = 2
	if os.Geteuid() == 0 {
		return true
	}
	if err := syscall.Access(dest, writeAccess); err == nil {
		return true
	} else if errors.Is(err, syscall.ENOENT) {
		return syscall.Access(filepath.Dir(dest), writeAccess) == nil
	}
	return false
}

func sameFile(a string, b string) bool {
	ai, err := os.Stat(a)
	if err != nil {
		return false
	}
	bi, err := os.Stat(b)
	if err != nil {
		return false
	}
	return os.SameFile(ai, bi)
}

func ensureLocalWebUsesSystem(dest string) error {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}
	local := filepath.Join(home, ".local", "bin", "web")
	if _, err := os.Lstat(local); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	if sameFile(local, dest) {
		return nil
	}
	if err := os.Remove(local); err != nil {
		return err
	}
	return os.Symlink(dest, local)
}

func findAskpass() string {
	if askpass := os.Getenv("SUDO_ASKPASS"); askpass != "" {
		return askpass
	}
	if askpass := os.Getenv("SSH_ASKPASS"); askpass != "" {
		return askpass
	}
	if askpass := os.Getenv("GIT_ASKPASS"); askpass != "" {
		return askpass
	}
	for _, candidate := range []string{"askpass", "ssh-askpass", "ksshaskpass", "lxqt-openssh-askpass", "gnome-ssh-askpass", "x11-ssh-askpass"} {
		if path, err := exec.LookPath(candidate); err == nil {
			return path
		}
	}
	for _, path := range []string{"/usr/lib/ssh/ssh-askpass", "/usr/libexec/ssh-askpass", "/usr/bin/ssh-askpass", "/usr/bin/gnome-ssh-askpass"} {
		if st, err := os.Stat(path); err == nil && !st.IsDir() && st.Mode()&0111 != 0 {
			return path
		}
	}
	return ""
}
