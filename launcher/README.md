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

## Windows 实机验证

关闭 OASX 后运行 `OASX.Launcher.exe`，启动完成后查看同目录的
`oasx-release.txt`：内容应变为测试版发布包对应的提交编号。若启动器提示
「更新未完成」，请查看同目录的 `oasx-launcher.log`；里面记录了具体异常。
修改更新渠道后，要在下一次通过启动器打开时才会检查新渠道。

## Git 测试版更新

云构建会把 `master` 编译后的 Windows 文件自动发布到 `oasx-bin-test` 分支，
无需手动下载或上传 ZIP。测试版启动器优先用 Git 拉取该分支，缓存放在当前
Windows 用户的本地应用数据目录；后续拉取复用缓存。启动器设置中的「Git 程序」
可选择 OAS 自带的 `toolkit/Git/mingw64/bin/git.exe`。未配置且系统路径中也找不到
Git 时，测试版暂时沿用原来的 ZIP 更新方式。稳定版目前仍使用原来的发布包，
等测试版实机验证通过后再切换。

拉取内容先复制到临时目录，沿用原有的文件替换、失败回滚和重启流程。
`oasx-git-path.txt` 保存用户选择的 Git 路径，更新时不会覆盖。
