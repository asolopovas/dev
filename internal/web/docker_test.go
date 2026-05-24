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

func TestComposePsOutputOmitsIPv6Ports(t *testing.T) {
	input := []byte("NAME                IMAGE   SERVICE       STATUS        PORTS\n" +
		"dev-franken_php-1   image   franken_php   Up 1 minute   0.0.0.0:80->80/tcp, [::]:80->80/tcp, 9000/tcp\n")
	got := string(composePsWithoutIPv6Ports(input))
	if bytes.Contains([]byte(got), []byte("[::]")) {
		t.Fatalf("ps output contains ipv6 port: %s", got)
	}
	if !bytes.Contains([]byte(got), []byte("0.0.0.0:80->80/tcp, 9000/tcp")) {
		t.Fatalf("ps output removed unexpected ports: %s", got)
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
	if len(runner.runs) != 1 {
		t.Fatalf("unexpected runs: %#v", runner.runs)
	}
	want := dockerPsCommand(cfg, "redis")
	if len(runner.outputs) != 2 || runner.outputs[1] != want {
		t.Fatalf("unexpected ps command:\nwant: %q\n got: %#v", want, runner.outputs)
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
	if len(runner.runs) != 0 {
		t.Fatalf("unexpected runs: %#v", runner.runs)
	}
	want := dockerPsCommand(cfg, "redis")
	if len(runner.outputs) != 2 || runner.outputs[1] != want {
		t.Fatalf("unexpected ps command:\nwant: %q\n got: %#v", want, runner.outputs)
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
