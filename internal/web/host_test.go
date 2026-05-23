package web

import "testing"

func TestMakeDBName(t *testing.T) {
	tests := []struct {
		host     string
		hostType string
		want     string
	}{
		{"example.test", "wp", "example_wp"},
		{"sub.example.test", "laravel", "example_sub_db"},
		{"example.co.uk", "wp", "example_wp"},
		{"3oak.test", "wp", "db_3oak_wp"},
		{"db2.3oak.test", "laravel", "db_3oak_db2_db"},
		{"localhost", "wp", "localhost_wp"},
		{"a.b.example.test", "laravel", "example_a_b_db"},
		{"site.test", "wordpress", "site_wp"},
	}
	for _, tt := range tests {
		t.Run(tt.host+"/"+tt.hostType, func(t *testing.T) {
			if got := MakeDBName(tt.host, tt.hostType); got != tt.want {
				t.Fatalf("MakeDBName() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestSanitizeDBIdentifier(t *testing.T) {
	tests := map[string]string{
		"my-site.name": "my_site_name",
		"__test":       "test",
		"":             "db",
		"9lives":       "db_9lives",
	}
	for input, want := range tests {
		if got := SanitizeDBIdentifier(input); got != want {
			t.Fatalf("SanitizeDBIdentifier(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestValidHostname(t *testing.T) {
	valid := []string{"example.test", "sub.example.test", "localhost", "a-b.test"}
	invalid := []string{"", "-bad.test", "bad-.test", "bad_host", "bad..test"}
	for _, host := range valid {
		if !ValidHostname(host) {
			t.Fatalf("expected %q to be valid", host)
		}
	}
	for _, host := range invalid {
		if ValidHostname(host) {
			t.Fatalf("expected %q to be invalid", host)
		}
	}
}
