package web

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func hostCertificateExtensionFile(host string) string {
	return fmt.Sprintf("authorityKeyIdentifier=keyid,issuer\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment\nsubjectAltName = @alt_names\n[alt_names]\nDNS.1 = %s\nIP.1 = 127.0.0.1\n", host)
}

func (a *App) generateRootCertificate(ctx context.Context, filename string, passphrase string) error {
	if filename == "" {
		filename = "rootCA"
	}
	if passphrase == "" {
		passphrase = "default"
	}
	if err := os.MkdirAll(a.Config.CertsDir, 0755); err != nil {
		return err
	}
	key := filepath.Join(a.Config.CertsDir, filename+".key")
	crt := filepath.Join(a.Config.CertsDir, filename+".crt")
	subj := "/C=GB/ST=London/L=London/O=Lyntouch/OU=IT Department/CN=Lyntouch Self-Signed RootCA/emailAddress=info@lyntouch.com"
	if err := a.runQuiet(ctx, "openssl", "genrsa", "-des3", "-passout", "pass:"+passphrase, "-out", key, "4096"); err != nil {
		return err
	}
	if err := a.runQuiet(ctx, "openssl", "req", "-x509", "-new", "-nodes", "-passin", "pass:"+passphrase, "-key", key, "-sha256", "-days", "29200", "-subj", subj, "-out", crt); err != nil {
		return err
	}
	fmt.Fprintln(a.Out, "Root CA created successfully")
	return nil
}

func (a *App) generateHostCertificate(ctx context.Context, host string) error {
	if _, err := os.Stat(a.Config.RootCrt); err != nil {
		if os.IsNotExist(err) {
			if err := a.generateRootCertificate(ctx, "rootCA", "default"); err != nil {
				return err
			}
		} else {
			return err
		}
	}
	if _, err := os.Stat(a.Config.RootKey); err != nil {
		if os.IsNotExist(err) {
			if err := a.generateRootCertificate(ctx, "rootCA", "default"); err != nil {
				return err
			}
		} else {
			return err
		}
	}
	crt := filepath.Join(a.Config.CertsDir, host+".crt")
	key := filepath.Join(a.Config.CertsDir, host+".key")
	csr := filepath.Join(a.Config.CertsDir, host+".csr")
	subj := fmt.Sprintf("/C=GB/ST=London/L=London/O=%s/OU=IT Department/CN=Lyntouch Self-Signed Host Certificate/emailAddress=info@lyntouch.com", host)
	if _, err := os.Stat(key); os.IsNotExist(err) {
		if err := a.runQuiet(ctx, "openssl", "req", "-new", "-sha256", "-nodes", "-out", csr, "-newkey", "rsa:2048", "-subj", subj, "-keyout", key); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	if _, err := os.Stat(crt); os.IsNotExist(err) {
		if _, err := os.Stat(csr); os.IsNotExist(err) {
			if err := a.runQuiet(ctx, "openssl", "req", "-new", "-sha256", "-nodes", "-out", csr, "-newkey", "rsa:2048", "-subj", subj, "-key", key); err != nil {
				return err
			}
		} else if err != nil {
			return err
		}
		ext, err := os.CreateTemp("", "web-ssl-ext-*")
		if err != nil {
			return err
		}
		extPath := ext.Name()
		if _, err := ext.WriteString(hostCertificateExtensionFile(host)); err != nil {
			_ = ext.Close()
			_ = os.Remove(extPath)
			return err
		}
		if err := ext.Close(); err != nil {
			_ = os.Remove(extPath)
			return err
		}
		defer os.Remove(extPath)
		return a.runQuiet(ctx, "openssl", "x509", "-req", "-passin", "pass:default", "-in", csr, "-CA", a.Config.RootCrt, "-CAkey", a.Config.RootKey, "-CAcreateserial", "-out", crt, "-days", "500", "-sha256", "-extfile", extPath)
	} else if err != nil {
		return err
	}
	return nil
}

func (a *App) importRootCertificate(ctx context.Context, cert string, nick string) error {
	wsl, err := isWSL()
	if err == nil && wsl {
		return errors.New("Chrome root CA import is not supported on WSL")
	}
	if _, err := os.Stat(cert); err != nil {
		return err
	}
	der := cert + ".der"
	if err := a.runQuiet(ctx, "openssl", "x509", "-outform", "der", "-in", cert, "-out", der); err != nil {
		return err
	}
	home, _ := os.UserHomeDir()
	db := filepath.Join(home, ".pki", "nssdb")
	if _, err := os.Stat(db); os.IsNotExist(err) {
		if err := os.MkdirAll(db, 0755); err != nil {
			return err
		}
		if err := a.Runner.Run(ctx, "certutil", "-N", "-d", db); err != nil {
			return err
		}
	}
	_ = a.Runner.Run(ctx, "certutil", "-d", "sql:"+db, "-D", "-n", nick)
	if err := a.Runner.Run(ctx, "certutil", "-d", "sql:"+db, "-A", "-t", "C,,", "-n", nick, "-i", der); err != nil {
		return err
	}
	fmt.Fprintf(a.Out, "Certificate imported to Chrome/Brave with nickname: %s\n", nick)
	return nil
}

func isWSL() (bool, error) {
	b, err := os.ReadFile("/proc/version")
	if err != nil {
		return false, err
	}
	return strings.Contains(string(b), "WSL"), nil
}
