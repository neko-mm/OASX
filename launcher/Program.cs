using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace OasxLauncher
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            if (args.Length == 2 && args[0] == "--verify-test-update")
            {
                try
                {
                    using (var launcher = new LauncherForm())
                        Task.Run(() => launcher.VerifyLatestPackageAsync("test"))
                            .GetAwaiter().GetResult();
                    File.WriteAllText(args[1], "OK");
                }
                catch (Exception error)
                {
                    File.WriteAllText(args[1], error.ToString());
                    Environment.ExitCode = 1;
                }
                return;
            }
            if (args.Length == 2 && args[0] == "--verify-git-update")
            {
                try
                {
                    using (var launcher = new LauncherForm())
                        launcher.VerifyGitPackage();
                    File.WriteAllText(args[1], "OK");
                }
                catch (Exception error)
                {
                    File.WriteAllText(args[1], error.ToString());
                    Environment.ExitCode = 1;
                }
                return;
            }
            if (args.Length == 2 && args[0] == "--verify-apply-handoff")
            {
                try
                {
                    LauncherForm.VerifyApplyHandoff();
                    File.WriteAllText(args[1], "OK");
                }
                catch (Exception error)
                {
                    File.WriteAllText(args[1], error.ToString());
                    Environment.ExitCode = 1;
                }
                return;
            }
            if (args.Length == 1 && args[0] == "--settings")
            {
                Application.Run(new ChannelSettingsForm());
                return;
            }
            if (args.Length == 2 && args[0] == "--wait-for-pid")
            {
                int previousPid;
                if (!int.TryParse(args[1], out previousPid) || previousPid <= 0)
                    return;
                try
                {
                    using (var previous = Process.GetProcessById(previousPid))
                    {
                        if (!previous.WaitForExit(30000)) return;
                    }
                }
                catch (ArgumentException) { /* Previous OASX already exited. */ }
                catch (InvalidOperationException) { /* Previous OASX already exited. */ }
            }
            Application.Run(new LauncherForm());
        }
    }

    internal static class UpdateChannel
    {
        private const string PreferenceFile = "oasx-update-channel.txt";

        public static string Read(string directory)
        {
            var selected = ReadFile(Path.Combine(directory, PreferenceFile));
            if (selected == "stable" || selected == "test") return selected;
            var installed = ReadFile(Path.Combine(directory, "oasx-channel.txt"));
            return installed == "test" ? "test" : "stable";
        }

        public static void Write(string directory, string channel)
        {
            if (channel != "stable" && channel != "test")
                throw new ArgumentException("无效的更新渠道。", "channel");
            var path = Path.Combine(directory, PreferenceFile);
            var temporary = path + ".tmp";
            File.WriteAllText(temporary, channel, Encoding.UTF8);
            try
            {
                if (File.Exists(path)) File.Replace(temporary, path, null);
                else File.Move(temporary, path);
            }
            finally
            {
                if (File.Exists(temporary)) File.Delete(temporary);
            }
        }

        private static string ReadFile(string path)
        {
            return File.Exists(path) ? File.ReadAllText(path).Trim('\uFEFF', ' ', '\r', '\n') : "";
        }
    }

    internal sealed class ChannelSettingsForm : Form
    {
        private readonly ComboBox _channel;

        public ChannelSettingsForm()
        {
            Text = "OASX · 更新渠道";
            ClientSize = new Size(430, 204);
            MinimumSize = MaximumSize = Size;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(13, 20, 29);
            ForeColor = Color.FromArgb(227, 236, 244);
            Font = new Font("Microsoft YaHei UI", 9F);

            var label = new Label {
                Text = "更新渠道", Location = new Point(22, 25), Size = new Size(90, 25)
            };
            _channel = new ComboBox {
                Location = new Point(118, 22), Size = new Size(280, 28),
                DropDownStyle = ComboBoxStyle.DropDownList
            };
            _channel.Items.AddRange(new object[] { "稳定版", "测试版" });
            _channel.SelectedIndex = UpdateChannel.Read(AppDomain.CurrentDomain.BaseDirectory)
                == "test" ? 1 : 0;
            var help = new Label {
                Text = "下次通过启动器打开时生效", Location = new Point(22, 64),
                Size = new Size(376, 23), ForeColor = Color.FromArgb(151, 170, 186)
            };
            var gitLabel = new Label {
                Text = "Git 程序", Location = new Point(22, 99), Size = new Size(90, 25)
            };
            var git = GitUpdate.FindOasGit(AppDomain.CurrentDomain.BaseDirectory);
            TextBox gitPath = null;
            var gitPathChanged = false;
            if (git == null)
            {
                gitPath = new TextBox {
                    Location = new Point(118, 96), Size = new Size(220, 25),
                    Text = GitUpdate.ReadConfiguredPath(AppDomain.CurrentDomain.BaseDirectory)
                };
                gitPath.TextChanged += (sender, args) => gitPathChanged = true;
                var browse = new Button {
                    Text = "浏览", Location = new Point(346, 95), Size = new Size(52, 27)
                };
                browse.Click += (sender, args) => {
                    using (var picker = new OpenFileDialog()) {
                        picker.Filter = "Git 程序 (git.exe)|git.exe";
                        picker.FileName = "git.exe";
                        if (picker.ShowDialog(this) == DialogResult.OK)
                            gitPath.Text = picker.FileName;
                    }
                };
                var gitHelp = new Label {
                    Text = "未识别到 OAS 内置 Git，可手动选择",
                    Location = new Point(118, 126), Size = new Size(280, 22),
                    ForeColor = Color.FromArgb(151, 170, 186)
                };
                Controls.AddRange(new Control[] { gitPath, browse, gitHelp });
            }
            else
            {
                Controls.Add(new Label {
                    Text = "已识别 OAS 内置 Git", Location = new Point(118, 99),
                    Size = new Size(280, 25), ForeColor = Color.FromArgb(126, 205, 225)
                });
            }
            var cancel = new Button {
                Text = "取消", Location = new Point(246, 156), Size = new Size(72, 30)
            };
            cancel.Click += (sender, args) => Close();
            var save = new Button {
                Text = "保存", Location = new Point(326, 156), Size = new Size(72, 30)
            };
            save.Click += (sender, args) => {
                try
                {
                    if (gitPathChanged && !string.IsNullOrWhiteSpace(gitPath.Text))
                        GitUpdate.WriteConfiguredPath(AppDomain.CurrentDomain.BaseDirectory,
                            gitPath.Text);
                    UpdateChannel.Write(AppDomain.CurrentDomain.BaseDirectory,
                        _channel.SelectedIndex == 1 ? "test" : "stable");
                    Close();
                }
                catch (Exception error)
                {
                    MessageBox.Show("保存失败：" + error.Message, "OASX",
                        MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            };
            Controls.AddRange(new Control[] {
                label, _channel, help, gitLabel, cancel, save
            });
        }
    }

    internal sealed class LauncherForm : Form
    {
        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr window, int attribute,
            ref int value, int size);

        private const string ReleaseApi =
            "https://api.github.com/repos/neko-mm/OASX/releases/tags/oasx-personal";
        private const string LegacyReleaseApi =
            "https://api.github.com/repos/neko-mm/OASX/releases/latest";
        private const string TestReleaseApi =
            "https://api.github.com/repos/neko-mm/OASX/releases/tags/oasx-master";
        private const string AppName = "oasx.exe";
        private readonly string _installDir = AppDomain.CurrentDomain.BaseDirectory;
        private readonly Label _status;
        private readonly Label _detail;
        private readonly ProgressBar _progress;
        private readonly Button _skip;
        private WebClient _downloadClient;
        private string _workRoot;
        private bool _finished;
        private bool _skipRequested;

        public LauncherForm()
        {
            Text = "OASX Launcher";
            ClientSize = new Size(430, 212);
            MinimumSize = MaximumSize = Size;
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            BackColor = Color.FromArgb(13, 20, 29);
            ForeColor = Color.FromArgb(227, 236, 244);
            Font = new Font("Microsoft YaHei UI", 9F);

            var accent = new Panel {
                Location = new Point(22, 27), Size = new Size(3, 31),
                BackColor = Color.FromArgb(102, 210, 223)
            };
            var title = new Label {
                Text = "OASX", Location = new Point(36, 23), Size = new Size(240, 28),
                Font = new Font("Segoe UI Semibold", 17F), ForeColor = ForeColor
            };
            var subtitle = new Label {
                Text = "启动与更新", Location = new Point(37, 52),
                Size = new Size(260, 18), Font = new Font("Segoe UI", 8F),
                ForeColor = Color.FromArgb(112, 134, 151)
            };
            _status = new Label {
                Text = "正在检查更新…", Location = new Point(24, 91),
                Size = new Size(382, 23), Font = new Font("Microsoft YaHei UI", 10F)
            };
            _detail = new Label {
                Text = "", Location = new Point(24, 117),
                Size = new Size(382, 19), ForeColor = Color.FromArgb(151, 170, 186)
            };
            _progress = new ProgressBar {
                Location = new Point(24, 150), Size = new Size(382, 4),
                Style = ProgressBarStyle.Marquee, MarqueeAnimationSpeed = 24
            };
            _skip = new Button {
                Text = "跳过并启动", Location = new Point(286, 171),
                Size = new Size(120, 29), FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(25, 37, 49),
                ForeColor = Color.FromArgb(205, 225, 235), Cursor = Cursors.Hand
            };
            _skip.FlatAppearance.BorderColor = Color.FromArgb(65, 92, 108);
            _skip.Click += (sender, args) => {
                _skipRequested = true;
                _skip.Enabled = false;
                SetStatus("已跳过更新", "正在启动现有版本…");
                if (_downloadClient != null) _downloadClient.CancelAsync();
            };
            Controls.AddRange(new Control[] {
                accent, title, subtitle, _status, _detail, _progress, _skip
            });
            Shown += async (sender, args) => await RunAsync();
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            try
            {
                var enabled = 1;
                DwmSetWindowAttribute(Handle, 20, ref enabled, sizeof(int));
            }
            catch { /* Older Windows versions keep their normal title bar. */ }
        }

        private async Task RunAsync()
        {
            try
            {
                if (IsAppRunning())
                {
                    SetStatus("OASX 已在运行", "");
                    _skip.Enabled = false;
                    await Task.Delay(1800);
                    _finished = true;
                    Close();
                    return;
                }
                var channel = UpdateChannel.Read(_installDir);
                SetStatus("正在检查更新", channel == "test" ? "测试版" : "稳定版");
                var git = channel == "test" ? GitUpdate.FindGit(_installDir) : null;
                if (git != null)
                {
                    await RunGitUpdateAsync(git);
                    return;
                }
                var release = await GetLatestReleaseAsync(channel);
                if (_finished) return;
                if (_skipRequested) { LaunchInstalled(); return; }
                var installedTag = ReadText("oasx-release.txt");
                if (ReadText("oasx-channel.txt") == channel &&
                    !IsNewer(release.Tag, installedTag))
                {
                    SetStatus("已是最新版本", installedTag);
                    await Task.Delay(500);
                    LaunchInstalled();
                    return;
                }

                SetStatus("发现新版本 " + release.Tag, "正在下载安装包…");
                _workRoot = Path.Combine(Path.GetTempPath(),
                    "oasx-update-" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(_workRoot);
                var zipPath = Path.Combine(_workRoot, "release.zip");
                using (var client = CreateClient())
                {
                    _downloadClient = client;
                    client.DownloadProgressChanged += (sender, args) => {
                        if (_finished) return;
                        _progress.Style = ProgressBarStyle.Continuous;
                        _progress.Value = Math.Max(0, Math.Min(100, args.ProgressPercentage));
                        _detail.Text = "下载中  " + args.ProgressPercentage + "%";
                    };
                    await client.DownloadFileTaskAsync(new Uri(release.DownloadUrl), zipPath);
                    _downloadClient = null;
                }
                if (_finished) return;
                if (_skipRequested) { LaunchInstalled(); return; }

                _skip.Enabled = false;
                SetStatus("正在校验安装包", "");
                if (!MatchesDigest(zipPath, release.Digest))
                    throw new InvalidDataException("安装包校验失败，已保留旧版本。");

                SetStatus("正在准备更新", "解压并检查程序文件…");
                var stageDir = Path.Combine(_workRoot, "stage");
                await Task.Run(() => ExtractSafely(zipPath, stageDir));
                if (ReadStageText(stageDir, "oasx-channel.txt") != channel ||
                    ReadStageText(stageDir, "oasx-release.txt") != release.Tag ||
                    !File.Exists(Path.Combine(stageDir, AppName)) ||
                    !File.Exists(Path.Combine(stageDir, "OASX.Launcher.exe")) ||
                    !File.Exists(Path.Combine(stageDir, "package-files.txt")))
                    throw new InvalidDataException("安装包内容不匹配，已保留旧版本。");

                var applySource = Path.Combine(stageDir, "OASX.Update.Apply.ps1");
                StartApply(applySource);
            }
            catch (Exception error)
            {
                if (_finished) return;
                if (_skipRequested) { LaunchInstalled(); return; }
                try
                {
                    File.AppendAllText(Path.Combine(_installDir, "oasx-launcher.log"),
                        DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + Environment.NewLine +
                        error + Environment.NewLine);
                }
                catch { /* Update failure must not prevent the old version starting. */ }
                SetStatus("更新未完成", SafeMessage(error));
                _progress.Style = ProgressBarStyle.Continuous;
                _progress.Value = 0;
                CleanupTemp();
                await Task.Delay(1500);
                LaunchInstalled();
            }
        }

        private async Task RunGitUpdateAsync(string git)
        {
            SetStatus("正在拉取更新", "测试版");
            LogUpdate("开始 Git 拉取");
            _workRoot = Path.Combine(Path.GetTempPath(),
                "oasx-update-" + Guid.NewGuid().ToString("N"));
            var stageDir = Path.Combine(_workRoot, "stage");
            var revision = await Task.Run(() =>
                GitUpdate.FetchAndStage(git, _installDir, stageDir));
            if (_finished) return;
            if (_skipRequested) { LaunchInstalled(); return; }
            if (revision == null)
            {
                LogUpdate("Git 已是最新版本");
                SetStatus("已是最新版本", ReadText("oasx-release.txt"));
                await Task.Delay(500);
                LaunchInstalled();
                return;
            }
            if (ReadStageText(stageDir, "oasx-channel.txt") != "test" ||
                string.IsNullOrWhiteSpace(ReadStageText(stageDir, "oasx-release.txt")) ||
                !File.Exists(Path.Combine(stageDir, AppName)) ||
                !File.Exists(Path.Combine(stageDir, "OASX.Launcher.exe")) ||
                !File.Exists(Path.Combine(stageDir, "package-files.txt")))
                throw new InvalidDataException("Git 更新内容不完整。");
            LogUpdate("Git 文件已暂存，版本 " + revision);
            SetStatus("正在安装更新", "");
            StartApply(Path.Combine(stageDir, "OASX.Update.Apply.ps1"));
        }

        private void StartApply(string applySource)
        {
            if (!File.Exists(applySource))
                throw new InvalidDataException("安装包缺少更新程序。");
            var applyTemp = Path.Combine(_workRoot, "apply.ps1");
            File.Copy(applySource, applyTemp);
            SetStatus("正在安装更新", "");
            _skip.Enabled = false;
            var psi = CreateApplyProcess(applyTemp, _installDir, _workRoot,
                Process.GetCurrentProcess().Id, false);
            LogUpdate("正在启动替换脚本");
            using (var apply = Process.Start(psi))
                LogUpdate("替换脚本已启动，进程 " + apply.Id);
            _finished = true;
            Close();
        }

        private static ProcessStartInfo CreateApplyProcess(string script,
            string installDir, string workRoot, int launcherPid, bool testMode)
        {
            var log = Path.Combine(installDir, "oasx-update.log");
            var command = "$ErrorActionPreference = 'Stop'; try { & " +
                PowerShellLiteral(script) + " -InstallDir " + PowerShellLiteral(installDir) +
                " -WorkRoot " + PowerShellLiteral(workRoot) +
                " -LauncherPid " + launcherPid + (testMode ? " -TestMode" : "") +
                " } catch { [System.IO.File]::AppendAllText(" + PowerShellLiteral(log) +
                ", (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " +
                "' | PowerShell 调用失败：' + $_.ToString() + " +
                "[Environment]::NewLine, [System.Text.Encoding]::UTF8); exit 1 }";
            return new ProcessStartInfo {
                FileName = Path.Combine(Environment.GetFolderPath(
                    Environment.SpecialFolder.System),
                    "WindowsPowerShell\\v1.0\\powershell.exe"),
                Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand " +
                    Convert.ToBase64String(Encoding.Unicode.GetBytes(command)),
                UseShellExecute = false, CreateNoWindow = true,
                WorkingDirectory = Path.GetTempPath()
            };
        }

        private static string PowerShellLiteral(string value)
        {
            return "'" + value.Replace("'", "''") + "'";
        }

        internal static void VerifyApplyHandoff()
        {
            var root = Path.Combine(Path.GetTempPath(),
                "oasx-handoff-test-" + Guid.NewGuid().ToString("N"));
            var install = Path.Combine(root, "install");
            var work = Path.Combine(root, "work");
            var stage = Path.Combine(work, "stage");
            Directory.CreateDirectory(install);
            Directory.CreateDirectory(stage);
            try
            {
                File.WriteAllText(Path.Combine(install, "oasx.exe"), "old");
                File.WriteAllText(Path.Combine(install, "OASX.Launcher.exe"), "old");
                File.WriteAllLines(Path.Combine(install, "package-files.txt"),
                    new[] { "oasx.exe", "OASX.Launcher.exe", "package-files.txt" });
                File.WriteAllText(Path.Combine(stage, "oasx.exe"), "new");
                File.WriteAllText(Path.Combine(stage, "OASX.Launcher.exe"), "new");
                File.WriteAllText(Path.Combine(stage, "oasx-channel.txt"), "test");
                File.WriteAllText(Path.Combine(stage, "oasx-release.txt"), "test-version");
                var apply = Path.Combine(stage, "OASX.Update.Apply.ps1");
                File.Copy(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,
                    "OASX.Update.Apply.ps1"), apply);
                var applyTemp = Path.Combine(work, "apply.ps1");
                File.Copy(apply, applyTemp);
                File.WriteAllLines(Path.Combine(stage, "package-files.txt"), new[] {
                    "oasx.exe", "OASX.Launcher.exe", "oasx-channel.txt",
                    "oasx-release.txt", "OASX.Update.Apply.ps1", "package-files.txt"
                });
                using (var process = Process.Start(CreateApplyProcess(applyTemp, install,
                    work, 0, true)))
                {
                    if (!process.WaitForExit(30000) || process.ExitCode != 0)
                        throw new InvalidDataException("PowerShell 更新交接测试失败：" +
                            (File.Exists(Path.Combine(install, "oasx-update.log"))
                                ? File.ReadAllText(Path.Combine(install, "oasx-update.log"))
                                : "没有产生更新日志。"));
                }
                var installed = File.ReadAllText(Path.Combine(install,
                    "oasx-release.txt")).Trim();
                var log = File.ReadAllText(Path.Combine(install, "oasx-update.log"));
                if (installed != "test-version" || !log.Contains("替换脚本开始执行"))
                    throw new InvalidDataException("PowerShell 未执行完整替换。版本：" +
                        installed + Environment.NewLine + log);
            }
            finally
            {
                if (Directory.Exists(root)) Directory.Delete(root, true);
            }
        }

        private void LogUpdate(string message)
        {
            try
            {
                File.AppendAllText(Path.Combine(_installDir, "oasx-update.log"),
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " | " + message +
                    Environment.NewLine, Encoding.UTF8);
            }
            catch { /* Logging must not interrupt the update. */ }
        }

        internal void VerifyGitPackage()
        {
            GitUpdate.VerifyAutoDetection();
            var git = GitUpdate.FindGit(_installDir);
            if (git == null) throw new InvalidDataException("找不到 git.exe。");
            var root = Path.Combine(Path.GetTempPath(),
                "oasx-verify-git-" + Guid.NewGuid().ToString("N"));
            try
            {
                var stage = Path.Combine(root, "stage");
                var revision = GitUpdate.FetchAndStage(git, _installDir, stage);
                if (revision == null ||
                    ReadStageText(stage, "oasx-channel.txt") != "test" ||
                    !File.Exists(Path.Combine(stage, AppName)) ||
                    !File.Exists(Path.Combine(stage, "OASX.Launcher.exe")))
                    throw new InvalidDataException("Git 测试包不完整。");
            }
            finally
            {
                if (Directory.Exists(root)) Directory.Delete(root, true);
            }
        }

        /// Exercises the same release, download, digest and extraction path
        /// without replacing the installed application.
        internal async Task VerifyLatestPackageAsync(string channel)
        {
            var unicodeJson = Encoding.UTF8.GetBytes("{\"name\":\"OASX 测试版\"}");
            var unicodeRelease = new JavaScriptSerializer()
                .DeserializeObject(DecodeReleaseJson(unicodeJson))
                as Dictionary<string, object>;
            if (unicodeRelease == null || ReadField(unicodeRelease, "name") != "OASX 测试版")
                throw new InvalidDataException("发布信息的 UTF-8 解码校验失败。");

            var release = await GetLatestReleaseAsync(channel);
            var root = Path.Combine(Path.GetTempPath(),
                "oasx-verify-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            try
            {
                var zip = Path.Combine(root, "release.zip");
                using (var client = CreateClient())
                    await client.DownloadFileTaskAsync(new Uri(release.DownloadUrl), zip);
                if (!MatchesDigest(zip, release.Digest))
                    throw new InvalidDataException("安装包校验失败。");
                var stage = Path.Combine(root, "stage");
                ExtractSafely(zip, stage);
                if (ReadStageText(stage, "oasx-channel.txt") != channel ||
                    ReadStageText(stage, "oasx-release.txt") != release.Tag ||
                    !File.Exists(Path.Combine(stage, AppName)) ||
                    !File.Exists(Path.Combine(stage, "OASX.Launcher.exe")) ||
                    !File.Exists(Path.Combine(stage, "package-files.txt")))
                    throw new InvalidDataException("安装包内容不匹配。");
            }
            finally
            {
                Directory.Delete(root, true);
            }
        }

        private async Task<ReleaseInfo> GetLatestReleaseAsync(string channel)
        {
            using (var client = CreateClient())
            {
                string json;
                try
                {
                    var bytes = await client.DownloadDataTaskAsync(new Uri(
                        channel == "test" ? TestReleaseApi : ReleaseApi));
                    json = DecodeReleaseJson(bytes);
                }
                catch (WebException error)
                {
                    var response = error.Response as HttpWebResponse;
                    if (channel == "test" && response != null &&
                        response.StatusCode == HttpStatusCode.NotFound)
                        throw new InvalidDataException("测试版暂未发布。");
                    if (channel != "stable" || response == null ||
                        response.StatusCode != HttpStatusCode.NotFound) throw;
                    var bytes = await client.DownloadDataTaskAsync(new Uri(LegacyReleaseApi));
                    json = DecodeReleaseJson(bytes);
                }
                var root = new JavaScriptSerializer().DeserializeObject(json)
                    as Dictionary<string, object>;
                if (root == null) throw new InvalidDataException("无法解析发布信息。");
                var tag = ReadField(root, "tag_name");
                var assets = root["assets"] as object[];
                if (assets == null) throw new InvalidDataException("发布包不存在。");
                ReleaseInfo newest = null;
                DateTime newestAt = DateTime.MinValue;
                foreach (var raw in assets)
                {
                    var asset = raw as Dictionary<string, object>;
                    if (asset == null) continue;
                    var name = ReadField(asset, "name");
                    if (channel == "test" && !name.StartsWith("oasx_test_",
                            StringComparison.OrdinalIgnoreCase)) continue;
                    if (channel == "stable" && !name.StartsWith("oasx_v",
                            StringComparison.OrdinalIgnoreCase)) continue;
                    if (!name.StartsWith("oasx_", StringComparison.OrdinalIgnoreCase) ||
                        !name.EndsWith("_windows.zip", StringComparison.OrdinalIgnoreCase))
                        continue;
                    if (channel == "test")
                    {
                        tag = name.Substring("oasx_test_".Length,
                            name.Length - "oasx_test_".Length - "_windows.zip".Length);
                        if (tag.Length != 40 || !tag.All(Uri.IsHexDigit)) continue;
                    }
                    else
                    {
                        tag = name.Substring("oasx_".Length,
                            name.Length - "oasx_".Length - "_windows.zip".Length);
                    }
                    var digest = ReadField(asset, "digest");
                    if (!digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase) ||
                        digest.Length != 71)
                        throw new InvalidDataException("发布包没有有效的 SHA-256 校验值。");
                    DateTime createdAt;
                    if (!DateTime.TryParse(ReadField(asset, "created_at"), out createdAt))
                        continue;
                    if (newest != null && createdAt <= newestAt) continue;
                    newest = new ReleaseInfo(tag,
                        ReadField(asset, "browser_download_url"), digest.Substring(7));
                    newestAt = createdAt;
                }
                if (newest != null) return newest;
                throw new InvalidDataException("未找到 Windows 发布包。");
            }
        }

        private static string DecodeReleaseJson(byte[] bytes)
        {
            return Encoding.UTF8.GetString(bytes).TrimStart('\uFEFF');
        }

        private static WebClient CreateClient()
        {
            var client = new TimedWebClient();
            client.Headers[HttpRequestHeader.UserAgent] = "OASX-Launcher";
            client.Headers[HttpRequestHeader.Accept] = "application/vnd.github+json";
            return client;
        }

        private static string ReadField(Dictionary<string, object> data, string key)
        {
            object value;
            if (!data.TryGetValue(key, out value) || value == null)
                throw new InvalidDataException("发布信息缺少 " + key);
            return value.ToString();
        }

        private static bool IsNewer(string latest, string installed)
        {
            if (latest == installed) return false;
            Version latestVersion, installedVersion;
            if (Version.TryParse(latest.TrimStart('v', 'V'), out latestVersion) &&
                Version.TryParse(installed.TrimStart('v', 'V'), out installedVersion))
                return latestVersion.CompareTo(installedVersion) > 0;
            return true;
        }

        private static bool MatchesDigest(string path, string expected)
        {
            using (var stream = File.OpenRead(path))
            using (var sha = SHA256.Create())
            {
                var actual = BitConverter.ToString(sha.ComputeHash(stream))
                    .Replace("-", "");
                return actual.Equals(expected, StringComparison.OrdinalIgnoreCase);
            }
        }

        private static void ExtractSafely(string zipPath, string stageDir)
        {
            Directory.CreateDirectory(stageDir);
            var root = Path.GetFullPath(stageDir).TrimEnd(Path.DirectorySeparatorChar) +
                Path.DirectorySeparatorChar;
            using (var archive = ZipFile.OpenRead(zipPath))
            {
                foreach (var entry in archive.Entries)
                {
                    var name = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                    var target = Path.GetFullPath(Path.Combine(stageDir, name));
                    if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidDataException("安装包包含非法路径。");
                    if (string.IsNullOrEmpty(entry.Name))
                    {
                        Directory.CreateDirectory(target);
                        continue;
                    }
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    entry.ExtractToFile(target, true);
                }
            }
        }

        private string ReadText(string name)
        {
            var path = Path.Combine(_installDir, name);
            return File.Exists(path) ? File.ReadAllText(path).Trim() : "";
        }

        private static string ReadStageText(string directory, string name)
        {
            var path = Path.Combine(directory, name);
            return File.Exists(path) ? File.ReadAllText(path).Trim() : "";
        }

        private bool IsAppRunning()
        {
            var expected = Path.GetFullPath(Path.Combine(_installDir, AppName));
            foreach (var process in Process.GetProcessesByName("oasx"))
            {
                try
                {
                    if (string.Equals(Path.GetFullPath(process.MainModule.FileName),
                            expected, StringComparison.OrdinalIgnoreCase))
                        return true;
                }
                catch { /* A different user's process can deny path inspection. */ }
                finally { process.Dispose(); }
            }
            return false;
        }

        private void SetStatus(string status, string detail)
        {
            if (_finished) return;
            _status.Text = status;
            _detail.Text = detail;
        }

        private void LaunchInstalled()
        {
            if (_finished) return;
            _finished = true;
            CleanupTemp();
            var exe = Path.Combine(_installDir, AppName);
            if (File.Exists(exe))
            {
                Process.Start(new ProcessStartInfo(exe, "--skip-parent-console") {
                    WorkingDirectory = _installDir
                });
            }
            else
            {
                MessageBox.Show("找不到 oasx.exe。请将启动器与 OASX 放在同一目录。",
                    "OASX Launcher", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            Close();
        }

        private void CleanupTemp()
        {
            if (_workRoot != null && Directory.Exists(_workRoot))
            {
                try { Directory.Delete(_workRoot, true); }
                catch { /* Windows may still be releasing the ZIP handle. */ }
            }
        }

        private static string SafeMessage(Exception error)
        {
            if (error is WebException) return "网络不可用，继续启动现有版本。";
            if (error is InvalidDataException) return error.Message;
            return "更新失败，请查看 oasx-launcher.log。";
        }

        private sealed class ReleaseInfo
        {
            public ReleaseInfo(string tag, string downloadUrl, string digest)
            {
                Tag = tag;
                DownloadUrl = downloadUrl;
                Digest = digest;
            }
            public string Tag { get; private set; }
            public string DownloadUrl { get; private set; }
            public string Digest { get; private set; }
        }

        private sealed class TimedWebClient : WebClient
        {
            protected override WebRequest GetWebRequest(Uri address)
            {
                var request = base.GetWebRequest(address);
                request.Timeout = 15000;
                var http = request as HttpWebRequest;
                if (http != null) http.ReadWriteTimeout = 30000;
                return request;
            }
        }
    }
}
