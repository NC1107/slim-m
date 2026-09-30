// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

package main

import (
	"fmt"
	"os"
	"path/filepath"
)

func main() {
	if len(os.Args) == 2 && os.Args[1] == selftestFlag {
		fmt.Print(selftestMarker)
		return
	}
	self, err := os.Executable()
	if err != nil {
		fail(err.Error())
	}
	root := locate(self)
	restoreLauncher(root, self)
	dir, err := choose(root)
	if err != nil {
		fail(err.Error())
	}
	if settled(root) {
		_ = realSwapper().swapLauncher(root, filepath.Join(root, launcherName))
	}
	if err := start(filepath.Join(dir, appExecutable), dir, os.Args[1:]); err != nil {
		fail(err.Error())
	}
}
