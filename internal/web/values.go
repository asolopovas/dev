package web

import (
	"encoding/json"
	"os"
	"path/filepath"
)

type AppValues struct {
	Services     ServiceValues     `json:"services"`
	Files        FileValues        `json:"files"`
	Hosts        HostValues        `json:"hosts"`
	Certificates CertificateValues `json:"certificates"`
	Tools        ToolValues        `json:"tools"`
	WordPress    WordPressValues   `json:"wordpress"`
}

type ServiceValues struct {
	FrankenPHP string `json:"frankenPHP"`
	MariaDB    string `json:"mariadb"`
	Redis      string `json:"redis"`
	PhpMyAdmin string `json:"phpMyAdmin"`
}

type FileValues struct {
	Compose        string `json:"compose"`
	Templates      string `json:"templates"`
	Crontab        string `json:"crontab"`
	Launch         string `json:"launch"`
	CaddyTemplate  string `json:"caddyTemplate"`
	DatabaseBackup string `json:"databaseBackup"`
	HostsJSON      string `json:"hostsJSON"`
	Env            string `json:"env"`
}

type HostValues struct {
	PhpMyAdmin      string `json:"phpMyAdmin"`
	Loopback        string `json:"loopback"`
	LinuxHostsFile  string `json:"linuxHostsFile"`
	ContainerWebDir string `json:"containerWebDir"`
}

type CertificateValues struct {
	RootName       string `json:"rootName"`
	RootPassphrase string `json:"rootPassphrase"`
	RootNickname   string `json:"rootNickname"`
}

type ToolValues struct {
	Docker   string `json:"docker"`
	Composer string `json:"composer"`
	Curl     string `json:"curl"`
	Tar      string `json:"tar"`
	OpenSSL  string `json:"openssl"`
	Certutil string `json:"certutil"`
}

type WordPressValues struct {
	ArchiveFile string `json:"archiveFile"`
	ArchiveURL  string `json:"archiveURL"`
	ExtractDir  string `json:"extractDir"`
}

func DefaultAppValues() AppValues {
	return AppValues{
		Services: ServiceValues{
			FrankenPHP: serviceFrankenPHP,
			MariaDB:    serviceMariaDB,
			Redis:      serviceRedis,
			PhpMyAdmin: servicePhpMyAdmin,
		},
		Files: FileValues{
			Compose:        fileCompose,
			Templates:      fileTemplates,
			Crontab:        fileCrontab,
			Launch:         fileLaunch,
			CaddyTemplate:  fileCaddyTemplate,
			DatabaseBackup: fileDatabaseBackup,
			HostsJSON:      fileHostsJSON,
			Env:            fileEnv,
		},
		Hosts: HostValues{
			PhpMyAdmin:      hostPhpMyAdmin,
			Loopback:        hostLoopback,
			LinuxHostsFile:  hostsFileLinux,
			ContainerWebDir: containerWebDir,
		},
		Certificates: CertificateValues{
			RootName:       certRootName,
			RootPassphrase: certRootPassphrase,
			RootNickname:   certRootNickname,
		},
		Tools: ToolValues{
			Docker:   toolDocker,
			Composer: toolComposer,
			Curl:     toolCurl,
			Tar:      toolTar,
			OpenSSL:  toolOpenSSL,
			Certutil: toolCertutil,
		},
		WordPress: WordPressValues{
			ArchiveFile: wordpressArchiveFile,
			ArchiveURL:  wordpressArchiveURL,
			ExtractDir:  wordpressExtractDir,
		},
	}
}

func LoadAppValues(scriptDir string) AppValues {
	values := DefaultAppValues()
	path := filepath.Join(scriptDir, fileValuesOverride)
	data, err := os.ReadFile(path)
	if err != nil {
		return values
	}
	var overrides AppValues
	if json.Unmarshal(data, &overrides) != nil {
		return values
	}
	values.merge(overrides)
	return values
}

func (v *AppValues) merge(other AppValues) {
	mergeString(&v.Services.FrankenPHP, other.Services.FrankenPHP)
	mergeString(&v.Services.MariaDB, other.Services.MariaDB)
	mergeString(&v.Services.Redis, other.Services.Redis)
	mergeString(&v.Services.PhpMyAdmin, other.Services.PhpMyAdmin)
	mergeString(&v.Files.Compose, other.Files.Compose)
	mergeString(&v.Files.Templates, other.Files.Templates)
	mergeString(&v.Files.Crontab, other.Files.Crontab)
	mergeString(&v.Files.Launch, other.Files.Launch)
	mergeString(&v.Files.CaddyTemplate, other.Files.CaddyTemplate)
	mergeString(&v.Files.DatabaseBackup, other.Files.DatabaseBackup)
	mergeString(&v.Files.HostsJSON, other.Files.HostsJSON)
	mergeString(&v.Files.Env, other.Files.Env)
	mergeString(&v.Hosts.PhpMyAdmin, other.Hosts.PhpMyAdmin)
	mergeString(&v.Hosts.Loopback, other.Hosts.Loopback)
	mergeString(&v.Hosts.LinuxHostsFile, other.Hosts.LinuxHostsFile)
	mergeString(&v.Hosts.ContainerWebDir, other.Hosts.ContainerWebDir)
	mergeString(&v.Certificates.RootName, other.Certificates.RootName)
	mergeString(&v.Certificates.RootPassphrase, other.Certificates.RootPassphrase)
	mergeString(&v.Certificates.RootNickname, other.Certificates.RootNickname)
	mergeString(&v.Tools.Docker, other.Tools.Docker)
	mergeString(&v.Tools.Composer, other.Tools.Composer)
	mergeString(&v.Tools.Curl, other.Tools.Curl)
	mergeString(&v.Tools.Tar, other.Tools.Tar)
	mergeString(&v.Tools.OpenSSL, other.Tools.OpenSSL)
	mergeString(&v.Tools.Certutil, other.Tools.Certutil)
	mergeString(&v.WordPress.ArchiveFile, other.WordPress.ArchiveFile)
	mergeString(&v.WordPress.ArchiveURL, other.WordPress.ArchiveURL)
	mergeString(&v.WordPress.ExtractDir, other.WordPress.ExtractDir)
}

func mergeString(target *string, value string) {
	if value != "" {
		*target = value
	}
}
