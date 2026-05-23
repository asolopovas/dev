package web

const (
	commandNameWeb = "web"

	serviceFrankenPHP = "franken_php"
	serviceMariaDB    = "mariadb"
	serviceRedis      = "redis"
	servicePhpMyAdmin = "phpmyadmin"

	hostPhpMyAdmin  = "phpmyadmin.test"
	hostLoopback    = "127.0.0.1"
	hostsFileLinux  = "/etc/hosts"
	containerWebDir = "/var/www"

	fileCompose        = "docker-compose.yml"
	fileTemplates      = "templates.yml"
	fileCrontab        = "crontab"
	fileLaunch         = "launch.json"
	fileCaddyTemplate  = "template.conf"
	fileDatabaseBackup = "db-backup.sql.gz"
	fileHostsJSON      = "web-hosts.json"
	fileEnv            = ".env"
	fileValuesOverride = "web-config.json"

	certRootName       = "rootCA"
	certRootPassphrase = "default"
	certRootNickname   = "Lyntouch Root CA"

	protocolHTTP  = "http"
	protocolHTTPS = "https"

	dockerComposeSubcommand = "compose"
	dockerInfoSubcommand    = "info"

	toolDocker   = "docker"
	toolComposer = "composer"
	toolCurl     = "curl"
	toolTar      = "tar"
	toolOpenSSL  = "openssl"
	toolCertutil = "certutil"

	wordpressArchiveFile = "wordpress.tar.gz"
	wordpressArchiveURL  = "https://en-gb.wordpress.org/latest-en_GB.tar.gz"
	wordpressExtractDir  = "wordpress"

	envMySQLRootCredential   = "MYSQL_ROOT_" + "PASSWORD"
	envMySQLClientCredential = "MYSQL_" + "PWD"
	envWebRoot               = "WEB_ROOT"
	envScriptDir             = "SCRIPT_DIR"
	envBackendDir            = "BACKEND_DIR"
	envHostsJSON             = "HOSTS_JSON"
	envWindowsHostsPath      = "WEB_WINDOWS_HOSTS_PATH"
	envXdebugMode            = "XDEBUG_MODE"
)
