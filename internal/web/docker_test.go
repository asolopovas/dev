package web

import (
	"bytes"
	"context"
	"testing"
)

func TestComposePsTableFormatOmitsCommandAndCreatedColumns(t *testing.T) {
	for _, column := range []string{"{{.Command}}", "{{.RunningFor}}"} {
		if bytes.Contains([]byte(composePsTableFormat), []byte(column)) {
			t.Fatalf("ps format includes %s", column)
		}
	}
}

func TestRunDockerComposeActionUsesPsFormatWithoutCommandColumn(t *testing.T) {
	dir := t.TempDir()
	cfg := dockerPsTestConfig(dir)
	runner := &workflowRunner{}
	app := &App{Config: cfg, Runner: runner, Out: &bytes.Buffer{}, Err: &bytes.Buffer{}}
	if err := app.runDockerComposeAction(context.Background(), "up", []string{"redis"}); err != nil {
		t.Fatal(err)
	}
	if len(runner.runs) != 2 {
		t.Fatalf("unexpected runs: %#v", runner.runs)
	}
	want := dockerPsCommand(cfg, "redis")
	if runner.runs[1] != want {
		t.Fatalf("unexpected ps command:\nwant: %q\n got: %q", want, runner.runs[1])
	}
}

func TestPsCommandUsesPsFormatWithoutCommandColumn(t *testing.T) {
	dir := t.TempDir()
	cfg := dockerPsTestConfig(dir)
	runner := &workflowRunner{}
	app := &App{Config: cfg, Runner: runner, Out: &bytes.Buffer{}, Err: &bytes.Buffer{}}
	if err := app.Run([]string{"ps", "redis"}); err != nil {
		t.Fatal(err)
	}
	if len(runner.runs) != 1 {
		t.Fatalf("unexpected runs: %#v", runner.runs)
	}
	want := dockerPsCommand(cfg, "redis")
	if runner.runs[0] != want {
		t.Fatalf("unexpected ps command:\nwant: %q\n got: %q", want, runner.runs[0])
	}
}

func dockerPsTestConfig(dir string) Config {
	cfg := testHostWorkflowConfig(dir)
	cfg.Values = DefaultAppValues()
	cfg.Values.Tools.Docker = "sh"
	return cfg
}

func dockerPsCommand(cfg Config, service string) string {
	return "sh compose -f " + cfg.ComposeFiles[0] + " ps --format " + composePsTableFormat + " " + service
}
