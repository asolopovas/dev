package web

import (
	"regexp"
	"strings"
)

var knownSLDs = map[string]bool{
	"co.uk":  true,
	"gov.uk": true,
	"com.br": true,
	"co.jp":  true,
}

var dbIdentRe = regexp.MustCompile(`[^A-Za-z0-9_]`)

func ValidHostname(host string) bool {
	if host == "" || strings.HasPrefix(host, "-") || strings.Contains(host, "..") {
		return false
	}
	for _, r := range host {
		if (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '.' || r == '-' {
			continue
		}
		return false
	}
	for _, label := range strings.Split(host, ".") {
		if label == "" || strings.HasPrefix(label, "-") || strings.HasSuffix(label, "-") || len(label) > 63 {
			return false
		}
	}
	return true
}

func SanitizeDBIdentifier(input string) string {
	clean := dbIdentRe.ReplaceAllString(input, "_")
	clean = strings.TrimLeft(clean, "_")
	if clean == "" {
		clean = "db"
	}
	if clean[0] >= '0' && clean[0] <= '9' {
		clean = "db_" + clean
	}
	return clean
}

func MakeDBName(host string, hostType string) string {
	parts := strings.Split(host, ".")
	n := len(parts)
	mainDomain := host
	subDomain := ""
	if n > 1 {
		tldCount := 1
		lastTwo := parts[n-2] + "." + parts[n-1]
		if knownSLDs[lastTwo] {
			tldCount = 2
		}
		if tldCount == 1 && n >= 2 && len(parts[n-2]) <= 3 {
			tldCount = 2
		}
		idx := max(n-1-tldCount, 0)
		mainDomain = parts[idx]
		if idx > 0 {
			subDomain = strings.Join(parts[:idx], ".")
		}
	}
	dbName := mainDomain
	if subDomain != "" && subDomain != mainDomain {
		dbName = mainDomain + "_" + strings.ReplaceAll(subDomain, ".", "_")
	}
	siteType, err := ParseSiteType(hostType)
	if err != nil {
		siteType = SiteTypeLaravel
	}
	dbName += siteType.DatabaseSuffix()
	return SanitizeDBIdentifier(strings.ReplaceAll(dbName, ".", "_"))
}
