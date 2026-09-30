// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

package main

import (
	"os"
	"path/filepath"
)

func main() {
	self, err := os.Executable()
	if err != nil {
		fail(err.Error())
	}
	dir, err := choose(filepath.Dir(self))
	if err != nil {
		fail(err.Error())
	}
	if err := start(filepath.Join(dir, appExecutable), dir, os.Args[1:]); err != nil {
		fail(err.Error())
	}
}
