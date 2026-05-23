package main

import (
	"fmt"
	"os"

	"github.com/asolopovas/dev/internal/web"
)

func main() {
	if err := web.Execute(os.Args[1:], os.Stdout, os.Stderr, os.Stdin); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
