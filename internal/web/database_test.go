package web

import "testing"

func TestValidateDatabaseIdentifier(t *testing.T) {
	valid := []string{"example_wp", "3oak_wp", "_legacy"}
	invalid := []string{"", "bad-name", "bad.name", "bad name"}
	for _, name := range valid {
		if err := validateDatabaseIdentifier(name); err != nil {
			t.Fatalf("expected %q to be valid: %v", name, err)
		}
	}
	for _, name := range invalid {
		if err := validateDatabaseIdentifier(name); err == nil {
			t.Fatalf("expected %q to be invalid", name)
		}
	}
}
