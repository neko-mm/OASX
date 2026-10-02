# OASX startup launcher (Windows portable)

`OASX.Launcher.exe` lives beside `oasx.exe`. A Windows shortcut should point to
the launcher. On every start it checks the selected update channel: stable
uses the rolling `oasx-personal` release (falling back to the previous latest
stable release until that channel is first published), and test uses the rolling `oasx-master`
prerelease built from `master`. It then opens the installed app or downloads the Windows ZIP,
verifies GitHub's SHA-256 digest, stages it, and hands off to a separate
PowerShell process for replacement. When GitHub is unavailable, the installed
app still starts.

The release ZIP is flat (the same layout as Flutter's `Release` directory).
`package-files.txt` lists the package-owned top-level files and directories.
Only those roots are backed up and replaced; unrelated OAS folders, configs,
and logs beside the app are left alone. A failed replacement restores the
backup. Successful launch or successful rollback removes the downloaded ZIP,
stage, and backup. The replacement also includes the launcher executable;
the apply script starts the new launcher, which then starts OASX. If rollback
itself fails, the backup is retained and its location is shown to the user.

`master` packages use `oasx-channel.txt = test`. `personal` packages use
`oasx-channel.txt = stable`. That marker selects the initial channel;
`oasx-update-channel.txt` stores a user override outside the package manifest.
The channel can be changed from OASX Settings → Update channel, which opens
`OASX.Launcher.exe --settings`. The change takes effect on the next launcher
start. Existing launchers do not know the test channel, so a one-time manual
installation of a new test package is required to enter this update flow.

Windows CI runs `Test-ApplyUpdate.ps1` to check successful replacement,
preservation of user configuration, cleanup, and rollback. The actual GUI and
network update flow still need testing on a Windows desktop before merging
the feature into `personal`.
