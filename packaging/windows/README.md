# slim-m for Windows

The zip is a per-user install that updates itself, laid out as decision 0041 describes.
Extract it anywhere and double-click `install.cmd`.
That copies the app to `%LOCALAPPDATA%\slim-m\app-<version>\`, puts the `slim-m.exe` launcher beside it, and adds a Start menu shortcut.
Nothing outside your profile is touched and there is no elevation prompt.

Windows cannot replace a running exe, so each version lives in its own folder.
`slim-m.exe` reads the `current` file, which holds a version number, and starts that folder.
An update unpacks the next version into a new folder, rewrites `current` through a temp file and a replacing rename, and restarts through the launcher.

The previous version is kept until the new one has stayed up for 20 seconds, then older folders are removed.
If the new version fails to start three times in a row, the launcher moves `current` back to `previous` and the app says so in a banner.

A copy run straight from the extracted folder, a machine-wide copy under `Program Files` and a packaged MSIX are never modified by the updater.
The launcher itself is not replaced by updates, so a launcher fix needs another run of `install.cmd`.
The build is unsigned, so SmartScreen will warn on first run.

`launcher/` holds the launcher's source (Go).
Build it with `GOOS=windows go build -ldflags "-H=windowsgui -s -w" -o slim-m.exe ./launcher`.
