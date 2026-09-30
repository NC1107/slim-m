// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

//go:build !windows

package main

import (
	"fmt"
	"os"
	"os/exec"
)

// start exists so the package builds and tests on the CI and dev hosts that
// are not Windows.
func start(exe, dir string, args []string) error {
	cmd := exec.Command(exe, args...)
	cmd.Dir = dir
	return cmd.Start()
}

func fail(message string) {
	fmt.Fprintln(os.Stderr, message)
	os.Exit(1)
}
