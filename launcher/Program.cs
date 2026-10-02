using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
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
        private static void Main()
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new LauncherForm());
        }
    }

    internal sealed class LauncherForm : Form
    {
        private const string ReleaseApi =
            "https://api.github.com/repos/neko-mm/OASX/releases/latest";
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
                Text = "STARTUP  /  UPDATE", Location = new Point(37, 52),
                Size = new Size(260, 18), Font = new Font("Segoe UI", 8F),
                ForeColor = Color.FromArgb(112, 134, 151)
            };
            _status = new Label {
                Text = "正在检查更新…", Location = new Point(24, 91),
                Size = new Size(382, 23), Font = new Font("Microsoft YaHei UI", 10F)
            };
            _detail = new Label {
                Text = "连接稳定版发布源", Location = new Point(24, 117),
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

        private async Task RunAsync()
        {
            try
            {
                if (IsAppRunning())
                {
                    SetStatus("OASX 已在运行", "关闭现有窗口后，重新启动才会检查更新。");
                    _skip.Enabled = false;
                    await Task.Delay(1800);
                    _finished = true;
                    Close();
                    return;
                }
                if (ReadText("oasx-channel.txt") == "test")
                {
                    SetStatus("测试版", "不检查稳定版更新，正在启动…");
                    await Task.Delay(2500);
                    LaunchInstalled();
                    return;
                }

                var release = await GetLatestReleaseAsync();
                if (_finished) return;
                if (_skipRequested) { LaunchInstalled(); return; }
                var installedTag = ReadText("oasx-release.txt");
                if (!IsNewer(release.Tag, installedTag))
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
                SetStatus("正在校验安装包", "SHA-256 完整性检查");
                if (!MatchesDigest(zipPath, release.Digest))
                    throw new InvalidDataException("安装包校验失败，已保留旧版本。");

                SetStatus("正在准备更新", "解压并检查程序文件…");
                var stageDir = Path.Combine(_workRoot, "stage");
                await Task.Run(() => ExtractSafely(zipPath, stageDir));
                if (ReadStageText(stageDir, "oasx-channel.txt") != "stable" ||
                    ReadStageText(stageDir, "oasx-release.txt") != release.Tag ||
                    !File.Exists(Path.Combine(stageDir, AppName)) ||
                    !File.Exists(Path.Combine(stageDir, "OASX.Launcher.exe")) ||
                    !File.Exists(Path.Combine(stageDir, "package-files.txt")))
                    throw new InvalidDataException("安装包内容不匹配，已保留旧版本。");

                var applySource = Path.Combine(stageDir, "OASX.Update.Apply.ps1");
                if (!File.Exists(applySource))
                    throw new InvalidDataException("安装包缺少更新程序。");
                var applyTemp = Path.Combine(_workRoot, "apply.ps1");
                File.Copy(applySource, applyTemp);
                SetStatus("正在安装更新", "即将关闭启动器并替换 OASX 文件…");
                _skip.Enabled = false;
                var psi = new ProcessStartInfo {
                    FileName = Path.Combine(Environment.GetFolderPath(
                        Environment.SpecialFolder.System),
                        "WindowsPowerShell\\v1.0\\powershell.exe"),
                    Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File " +
                        Quote(applyTemp) + " -InstallDir " + Quote(_installDir) +
                        " -WorkRoot " + Quote(_workRoot) +
                        " -LauncherPid " + Process.GetCurrentProcess().Id,
                    UseShellExecute = false, CreateNoWindow = true,
                    WorkingDirectory = Path.GetTempPath()
                };
                Process.Start(psi);
                _finished = true;
                Close();
            }
            catch (Exception error)
            {
                if (_finished) return;
                if (_skipRequested) { LaunchInstalled(); return; }
                SetStatus("更新未完成", SafeMessage(error));
                _progress.Style = ProgressBarStyle.Continuous;
                _progress.Value = 0;
                CleanupTemp();
                await Task.Delay(1500);
                LaunchInstalled();
            }
        }

        private async Task<ReleaseInfo> GetLatestReleaseAsync()
        {
            using (var client = CreateClient())
            {
                var json = await client.DownloadStringTaskAsync(new Uri(ReleaseApi));
                var root = new JavaScriptSerializer().DeserializeObject(json)
                    as Dictionary<string, object>;
                if (root == null) throw new InvalidDataException("无法解析发布信息。");
                var tag = ReadField(root, "tag_name");
                var assets = root["assets"] as object[];
                if (assets == null) throw new InvalidDataException("发布包不存在。");
                foreach (var raw in assets)
                {
                    var asset = raw as Dictionary<string, object>;
                    if (asset == null) continue;
                    var name = ReadField(asset, "name");
                    if (!name.StartsWith("oasx_", StringComparison.OrdinalIgnoreCase) ||
                        !name.EndsWith("_windows.zip", StringComparison.OrdinalIgnoreCase))
                        continue;
                    var digest = ReadField(asset, "digest");
                    if (!digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase) ||
                        digest.Length != 71)
                        throw new InvalidDataException("发布包没有有效的 SHA-256 校验值。");
                    return new ReleaseInfo(tag,
                        ReadField(asset, "browser_download_url"), digest.Substring(7));
                }
                throw new InvalidDataException("未找到 Windows 发布包。");
            }
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

        private static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        private static string SafeMessage(Exception error)
        {
            if (error is WebException) return "网络不可用，继续启动现有版本。";
            if (error is InvalidDataException) return error.Message;
            return "保留现有版本并继续启动。";
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
