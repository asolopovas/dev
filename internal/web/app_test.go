package web

import "testing"

func TestParseNewHostArgs(t *testing.T) {
	tests := []struct {
		name     string
		args     []string
		wantHost string
		wantType string
	}{
		{"type first", []string{"-t", "laravel", "mysite.test"}, "mysite.test", "laravel"},
		{"default type", []string{"mysite.test"}, "mysite.test", "wp"},
		{"host first", []string{"mysite.test", "-t", "laravel"}, "mysite.test", "laravel"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			host, hostType, err := parseNewHostArgs(tt.args)
			if err != nil {
				t.Fatal(err)
			}
			if host != tt.wantHost || hostType != tt.wantType {
				t.Fatalf("got %s/%s", host, hostType)
			}
		})
	}
}

func TestParseNewHostArgsErrors(t *testing.T) {
	cases := [][]string{
		{},
		{"mysite.test", "-t"},
		{"-f"},
		{"bad_host"},
	}
	for _, args := range cases {
		if _, _, err := parseNewHostArgs(args); err == nil {
			t.Fatalf("expected error for %#v", args)
		}
	}
}
