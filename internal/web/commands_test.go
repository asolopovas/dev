package web

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCobraHelpAndCompletions(t *testing.T) {
	var out bytes.Buffer
	var errb bytes.Buffer
	if err := Execute([]string{"help"}, &out, &errb, strings.NewReader("")); err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"new-host", "build-webconf", "completion"} {
		if !strings.Contains(out.String(), want) {
			t.Fatalf("help missing %q\n%s", want, out.String())
		}
	}
	out.Reset()
	if err := Execute([]string{"completion", "fish"}, &out, &errb, strings.NewReader("")); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "complete -c web") {
		t.Fatalf("fish completion was not generated")
	}
	out.Reset()
	if err := Execute([]string{"completion", "bash"}, &out, &errb, strings.NewReader("")); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "__start_web") {
		t.Fatalf("bash completion was not generated")
	}
}

func TestCompletionInstallWritesBashAndFish(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	var out bytes.Buffer
	var errb bytes.Buffer
	if err := Execute([]string{"completion", "install"}, &out, &errb, strings.NewReader("")); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{
		filepath.Join(home, ".config", "fish", "completions", "web.fish"),
		filepath.Join(home, ".local", "share", "bash-completion", "completions", "web"),
	} {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Contains(data, []byte("web")) {
			t.Fatalf("completion %s does not contain web", path)
		}
	}
}
