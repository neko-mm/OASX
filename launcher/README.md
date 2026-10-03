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
Windows 用户的本地应用数据目录；后续拉取复用缓存。OASX 会把已配置的 OAS
根目录同步给启动器，启动器自动使用其中的 `toolkit/Git/mingw64/bin/git.exe`。
未识别到时会沿用旧的 Git 路径或系统 Git；都找不到则使用 ZIP 更新。
稳定版目前仍使用原来的发布包，
等测试版实机验证通过后再切换。

拉取内容先复制到临时目录，沿用原有的文件替换、失败回滚和重启流程。
`oasx-oas-root.txt` 保存当前 OAS 根目录，更新时不会覆盖；旧版手选的
`oasx-git-path.txt` 仍可作为备用路径。
启动器与替换脚本的交接记录写入 `oasx-update.log`；如果窗口关闭后程序未重新打开，
先查看该日志最后几行，区分 Git 拉取、文件替换和重启失败。
PowerShell 交接通过编码命令传递路径和参数；脚本启动失败也会写入同一日志。
Windows 云构建会用与正式更新相同的交接命令完成一次测试替换。
