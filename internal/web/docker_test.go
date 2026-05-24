package web

import (
	"bytes"
	"context"
	"testing"
)

func TestRunDockerComposeActionUsesPsFormatWithoutCommandColumn(t *testing.T) {
	dir := t.TempDir()
	cfg := testHostWorkflowConfig(dir)
	cfg.Values = DefaultAppValues()
	cfg.Values.Tools.Docker = "sh"
	runner := &workflowRunner{}
	app := &App{Config: cfg, Runner: runner, Out: &bytes.Buffer{}, Err: &bytes.Buffer{}}
	if err := app.runDockerComposeAction(context.Background(), "up", []string{"redis"}); err != nil {
		t.Fatal(err)
	}
	if len(runner.runs) != 2 {
		t.Fatalf("unexpected runs: %#v", runner.runs)
	}
	want := "sh compose -f " + cfg.ComposeFiles[0] + " ps --format " + composePsTableFormat + " redis"
	if runner.runs[1] != want {
		t.Fatalf("unexpected ps command:\nwant: %q\n got: %q", want, runner.runs[1])
	}
}
