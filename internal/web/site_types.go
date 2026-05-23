package web

import "fmt"

type SiteType string

const (
	SiteTypeWordPressShort SiteType = "wp"
	SiteTypeWordPress      SiteType = "wordpress"
	SiteTypeLaravel        SiteType = "laravel"
)

var siteTypeValues = []string{string(SiteTypeWordPressShort), string(SiteTypeWordPress), string(SiteTypeLaravel)}
var interactiveSiteTypeValues = []string{string(SiteTypeWordPressShort), string(SiteTypeLaravel)}

func ParseSiteType(value string) (SiteType, error) {
	siteType := SiteType(value)
	if !siteType.Valid() {
		return "", fmt.Errorf("invalid type %q. Use: wp, wordpress, or laravel", value)
	}
	return siteType, nil
}

func (t SiteType) Valid() bool {
	return t.WordPress() || t.Laravel()
}

func (t SiteType) WordPress() bool {
	return t == SiteTypeWordPressShort || t == SiteTypeWordPress
}

func (t SiteType) Laravel() bool {
	return t == SiteTypeLaravel
}

func (t SiteType) DatabaseSuffix() string {
	if t.WordPress() {
		return "_wp"
	}
	return "_db"
}

func schemeForHTTPS(enabled bool) string {
	if enabled {
		return protocolHTTPS
	}
	return protocolHTTP
}
