# OASX startup launcher (Windows portable)

`OASX.Launcher.exe` lives beside `oasx.exe`. A Windows shortcut should point to
the launcher. It checks the latest stable release of `neko-mm/OASX` on every
start, then either opens the installed app or downloads the Windows ZIP,
verifies GitHub's SHA-256 digest, stages it, and hands off to a separate
PowerShell process for replacement. When GitHub is unavailable, the installed
app still starts.

The release ZIP is flat (the same layout as Flutter's `Release` directory).
`package-files.txt` lists the package-owned top-level files and directories.
Only those roots are backed up and replaced; unrelated OAS folders, configs,
and logs beside the app are left alone. A failed replacement restores the
backup. Successful launch or successful rollback removes the downloaded ZIP,
stage, and backup. If rollback itself fails, the backup is retained and its
location is shown to the user.

`master` artifacts use `oasx-channel.txt = test`, so they never overwrite
themselves with the older stable release. They display the launcher for a
moment, then start OASX. `personal` publishes a stable Windows release when
that branch is advanced after acceptance. The launcher only installs that
stable release, not a `master` test artifact.

Windows CI runs `Test-ApplyUpdate.ps1` to check successful replacement,
preservation of user configuration, cleanup, and rollback. The actual GUI and
network update flow still need testing on a Windows desktop before merging
the feature into `personal`.
