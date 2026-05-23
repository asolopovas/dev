package web

import (
	"io"
	"os"
)

type App struct {
	Config Config
	Runner Runner
	Out    io.Writer
	Err    io.Writer
	In     io.Reader
}

func NewApp(output io.Writer, errorOutput io.Writer) (*App, error) {
	return &App{
		Config: LoadConfig(),
		Runner: ExecRunner{Stdout: output, Stderr: errorOutput, Stdin: os.Stdin},
		Out:    output,
		Err:    errorOutput,
		In:     os.Stdin,
	}, nil
}

func (a *App) Run(args []string) error {
	cmd := NewAppCommand(a)
	cmd.SetArgs(args)
	return cmd.Execute()
}
