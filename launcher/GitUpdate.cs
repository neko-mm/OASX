using System;
using System.Diagnostics;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace OasxLauncher
{
    internal static class GitUpdate
    {
        private const string Repository = "https://github.com/neko-mm/OASX.git";
        private const string TestBranch = "oasx-bin-test";
        private const string PreferenceFile = "oasx-git-path.txt";
        private const string OasRootFile = "oasx-oas-root.txt";
        internal const string RevisionFile = "oasx-git-revision.txt";

        internal static string ReadConfiguredPath(string installDir)
        {
            var file = Path.Combine(installDir, PreferenceFile);
            return File.Exists(file) ? File.ReadAllText(file).Trim('\uFEFF', ' ', '\r', '\n', '"') : "";
        }

        internal static void WriteConfiguredPath(string installDir, string path)
        {
            path = path.Trim().Trim('"');
            if (!IsCompleteGit(path))
                throw new InvalidDataException("请选择完整安装的 Git 程序。");
            var file = Path.Combine(installDir, PreferenceFile);
            var temporary = file + ".tmp";
            File.WriteAllText(temporary, path, Encoding.UTF8);
            try
            {
                if (File.Exists(file)) File.Replace(temporary, file, null);
                else File.Move(temporary, file);
            }
            finally
            {
                if (File.Exists(temporary)) File.Delete(temporary);
            }
        }

        internal static string FindGit(string installDir)
        {
            var oasGit = FindOasGit(installDir);
            if (oasGit != null) return oasGit;
            var configured = ReadConfiguredPath(installDir);
            if (IsCompleteGit(configured)) return configured;
            foreach (var directory in (Environment.GetEnvironmentVariable("PATH") ?? "")
                .Split(new[] { Path.PathSeparator }, StringSplitOptions.RemoveEmptyEntries))
            {
                try
                {
                    var candidate = Path.Combine(directory.Trim('"'), "git.exe");
                    if (IsCompleteGit(candidate)) return candidate;
                }
                catch (ArgumentException) { }
            }
            return null;
        }

        internal static string FindOasGit(string installDir)
        {
            var file = Path.Combine(installDir, OasRootFile);
            if (!File.Exists(file)) return null;
            var root = File.ReadAllText(file).Trim('\uFEFF', ' ', '\r', '\n', '"');
            if (string.IsNullOrWhiteSpace(root)) return null;
            try
            {
                var candidate = Path.Combine(root, "toolkit", "Git", "mingw64",
                    "bin", "git.exe");
                return IsCompleteGit(candidate) ? candidate : null;
            }
            catch (ArgumentException) { return null; }
        }

        private static bool IsCompleteGit(string git)
        {
            if (!File.Exists(git) ||
                !string.Equals(Path.GetFileName(git), "git.exe",
                    StringComparison.OrdinalIgnoreCase)) return false;
            var directory = Path.GetDirectoryName(git);
            return File.Exists(Path.Combine(directory, "sh.exe")) ||
                File.Exists(Path.GetFullPath(Path.Combine(directory, "..", "usr", "bin", "sh.exe"))) ||
                File.Exists(Path.GetFullPath(Path.Combine(directory, "..", "..", "usr", "bin", "sh.exe")));
        }

        internal static void VerifyAutoDetection()
        {
            var install = Path.Combine(Path.GetTempPath(),
                "oasx-git-detect-" + Guid.NewGuid().ToString("N"));
            try
            {
                var root = Path.Combine(install, "OAS");
                var git = Path.Combine(root, "toolkit", "Git", "mingw64", "bin", "git.exe");
                Directory.CreateDirectory(Path.GetDirectoryName(git));
                File.WriteAllText(git, "");
                File.WriteAllText(Path.Combine(install, OasRootFile), root);
                if (FindOasGit(install) != null)
                    throw new InvalidDataException("缺少 sh.exe 的 Git 不应被自动选择。");
                var shell = Path.Combine(root, "toolkit", "Git", "usr", "bin", "sh.exe");
                Directory.CreateDirectory(Path.GetDirectoryName(shell));
                File.WriteAllText(shell, "");
                if (FindOasGit(install) != git || FindGit(install) != git)
                    throw new InvalidDataException("无法从 OAS 根目录识别 Git。");
                File.Delete(shell);
                if (FindOasGit(install) != null)
                    throw new InvalidDataException("OAS Git 缺少运行组件后仍返回旧路径。");
                var fullGit = Path.Combine(install, "FullGit", "cmd", "git.exe");
                var fullShell = Path.Combine(install, "FullGit", "usr", "bin", "sh.exe");
                Directory.CreateDirectory(Path.GetDirectoryName(fullGit));
                Directory.CreateDirectory(Path.GetDirectoryName(fullShell));
                File.WriteAllText(fullGit, "");
                File.WriteAllText(fullShell, "");
                WriteConfiguredPath(install, fullGit);
                if (FindGit(install) != fullGit)
                    throw new InvalidDataException("未选用手动指定的完整 Git。");
            }
            finally
            {
                if (Directory.Exists(install)) Directory.Delete(install, true);
            }
        }

        internal static string FetchAndStage(string git, string installDir, string stageDir)
        {
            var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var identity = Path.GetFullPath(installDir).ToLowerInvariant();
            string cacheKey;
            using (var sha = SHA256.Create())
                cacheKey = BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(identity)))
                    .Replace("-", "").Substring(0, 16);
            var cache = Path.Combine(local, "OASX", "git-cache", cacheKey, "test");
            using (var mutex = new Mutex(false, "Local\\OASX-Git-" + cacheKey))
            {
                var acquired = false;
                try
                {
                    try { acquired = mutex.WaitOne(10000); }
                    catch (AbandonedMutexException) { acquired = true; }
                    if (!acquired)
                        throw new InvalidDataException("另一个启动器正在更新，请稍后再试。");
                    return FetchAndStageLocked(git, installDir, stageDir, cache);
                }
                finally { if (acquired) mutex.ReleaseMutex(); }
            }
        }

        private static string FetchAndStageLocked(string git, string installDir,
            string stageDir, string cache)
        {
            var gitDirectory = Path.Combine(cache, ".git");
            ResetCacheIfLocked(cache);
            Directory.CreateDirectory(Path.GetDirectoryName(cache));
            try
            {
                if (!Directory.Exists(gitDirectory))
                {
                    if (Directory.Exists(cache)) Directory.Delete(cache, true);
                    Run(git, "clone --quiet --depth 1 --single-branch --branch " + TestBranch +
                        " " + Quote(Repository) + " " + Quote(cache), true,
                        () => { if (Directory.Exists(cache)) Directory.Delete(cache, true); });
                }
                else
                {
                    Run(git, "-C " + Quote(cache) + " fetch --quiet --depth 1 origin " + TestBranch,
                        true);
                    Run(git, "-C " + Quote(cache) + " reset --quiet --hard FETCH_HEAD");
                }
                var revision = Run(git, "-C " + Quote(cache) + " rev-parse HEAD").Trim();
                if (revision.Length != 40 || !revision.All(Uri.IsHexDigit))
                    throw new InvalidDataException("Git 版本号无效。");
                if (File.Exists(Path.Combine(installDir, RevisionFile)) &&
                    File.ReadAllText(Path.Combine(installDir, RevisionFile)).Trim() == revision &&
                    File.ReadAllText(Path.Combine(installDir, "oasx-channel.txt")).Trim() == "test")
                    return null;

                Directory.CreateDirectory(stageDir);
                foreach (var file in Directory.GetFiles(cache))
                    File.Copy(file, Path.Combine(stageDir, Path.GetFileName(file)), true);
                foreach (var directory in Directory.GetDirectories(cache))
                {
                    if (Path.GetFileName(directory) == ".git") continue;
                    CopyDirectory(directory, Path.Combine(stageDir, Path.GetFileName(directory)));
                }
                File.WriteAllText(Path.Combine(stageDir, RevisionFile), revision, Encoding.UTF8);
                File.AppendAllText(Path.Combine(stageDir, "package-files.txt"),
                    Environment.NewLine + RevisionFile + Environment.NewLine, Encoding.UTF8);
                return revision;
            }
            catch
            {
                try { if (Directory.Exists(cache)) Directory.Delete(cache, true); }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
                throw;
            }
        }

        private static void ResetCacheIfLocked(string cache)
        {
            var gitDirectory = Path.Combine(cache, ".git");
            if (Directory.Exists(gitDirectory) &&
                Directory.GetFiles(gitDirectory, "*.lock").Length > 0)
                Directory.Delete(cache, true);
        }

        internal static void VerifyCacheRecovery()
        {
            var cache = Path.Combine(Path.GetTempPath(),
                "oasx-git-cache-check-" + Guid.NewGuid().ToString("N"));
            try
            {
                Directory.CreateDirectory(Path.Combine(cache, ".git"));
                File.WriteAllText(Path.Combine(cache, ".git", "shallow.lock"), "");
                ResetCacheIfLocked(cache);
                if (Directory.Exists(cache))
                    throw new InvalidDataException("旧 Git 锁未清理。");
            }
            finally { if (Directory.Exists(cache)) Directory.Delete(cache, true); }
        }

        private static void CopyDirectory(string source, string target)
        {
            Directory.CreateDirectory(target);
            foreach (var file in Directory.GetFiles(source))
                File.Copy(file, Path.Combine(target, Path.GetFileName(file)), true);
            foreach (var directory in Directory.GetDirectories(source))
                CopyDirectory(directory, Path.Combine(target, Path.GetFileName(directory)));
        }

        private static string Run(string git, string args, bool network = false,
            Action beforeDirectRetry = null)
        {
            return RunWithFallback(direct => RunOnce(git, args, direct), network,
                beforeDirectRetry);
        }

        private static string RunWithFallback(Func<bool, string> command,
            bool network, Action beforeDirectRetry = null)
        {
            try { return command(false); }
            catch (InvalidDataException error)
            {
                if (!network || !IsDeadLocalProxy(error.Message)) throw;
                beforeDirectRetry?.Invoke();
                try { return command(true); }
                catch (Exception directError)
                {
                    throw new InvalidDataException(
                        "本机代理不可用，已尝试直连；直连失败：" + directError.Message,
                        directError);
                }
            }
        }

        private static bool IsDeadLocalProxy(string message)
        {
            var local = message.IndexOf("127.0.0.1", StringComparison.OrdinalIgnoreCase) >= 0 ||
                message.IndexOf("localhost", StringComparison.OrdinalIgnoreCase) >= 0 ||
                message.IndexOf("::1", StringComparison.OrdinalIgnoreCase) >= 0;
            var refused = message.IndexOf("Connection refused", StringComparison.OrdinalIgnoreCase) >= 0 ||
                message.IndexOf("Failed to connect", StringComparison.OrdinalIgnoreCase) >= 0 ||
                message.IndexOf("Could not connect to proxy", StringComparison.OrdinalIgnoreCase) >= 0;
            return local && refused;
        }

        private static ProcessStartInfo CreateGitStartInfo(string git, string args,
            bool direct)
        {
            var proxy = direct
                ? "-c http.proxy= -c https.proxy= -c http.https://github.com/.proxy= " +
                  "-c remote.origin.proxy= "
                : "";
            var info = new ProcessStartInfo {
                FileName = git,
                Arguments = "-c credential.helper= -c core.askPass= " + proxy + args,
                UseShellExecute = false,
                CreateNoWindow = true, RedirectStandardOutput = true,
                RedirectStandardError = true, WorkingDirectory = Path.GetTempPath()
            };
            info.EnvironmentVariables["GIT_TERMINAL_PROMPT"] = "0";
            if (direct)
            {
                foreach (var name in new[] { "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
                    "http_proxy", "https_proxy", "all_proxy" })
                    info.EnvironmentVariables.Remove(name);
            }
            return info;
        }

        private static string RunOnce(string git, string args, bool direct)
        {
            using (var process = new Process())
            {
                var output = new StringBuilder();
                var error = new StringBuilder();
                process.StartInfo = CreateGitStartInfo(git, args, direct);
                process.OutputDataReceived += (sender, line) => {
                    if (line.Data != null) output.AppendLine(line.Data);
                };
                process.ErrorDataReceived += (sender, line) => {
                    if (line.Data != null) error.AppendLine(line.Data);
                };
                process.Start();
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
                if (!process.WaitForExit(120000))
                {
                    StopProcessTree(process);
                    throw new InvalidDataException("Git 拉取超时。");
                }
                process.WaitForExit();
                if (process.ExitCode != 0)
                    throw new InvalidDataException("Git 拉取失败：" + error.ToString().Trim());
                return output.ToString();
            }
        }

        private static void StopProcessTree(Process process)
        {
            try
            {
                using (var taskkill = Process.Start(new ProcessStartInfo {
                    FileName = Path.Combine(Environment.GetFolderPath(
                        Environment.SpecialFolder.System), "taskkill.exe"),
                    Arguments = "/T /F /PID " + process.Id,
                    UseShellExecute = false, CreateNoWindow = true
                }))
                    taskkill.WaitForExit(10000);
            }
            catch (Exception) { }
            try
            {
                if (!process.HasExited) process.Kill();
                process.WaitForExit(5000);
            }
            catch (InvalidOperationException) { }
        }

        internal static void VerifyProxyFallback()
        {
            var calls = new List<bool>();
            var cleaned = false;
            var result = RunWithFallback(direct => {
                calls.Add(direct);
                if (!direct) throw new InvalidDataException(
                    "Git 拉取失败：Failed to connect to 127.0.0.1 port 7890: Connection refused");
                return "OK";
            }, true, () => cleaned = true);
            if (result != "OK" || !cleaned || calls.Count != 2 ||
                calls[0] || !calls[1])
                throw new InvalidDataException("本机代理失败后未正确直连。 ");

            calls.Clear();
            try
            {
                RunWithFallback(direct => {
                    calls.Add(direct);
                    throw new InvalidDataException("Git 拉取失败：认证失败");
                }, true);
                throw new InvalidDataException("非代理故障被错误重试。");
            }
            catch (InvalidDataException error)
            {
                if (error.Message != "Git 拉取失败：认证失败" || calls.Count != 1)
                    throw;
            }

            var original = Environment.GetEnvironmentVariable("HTTPS_PROXY");
            try
            {
                Environment.SetEnvironmentVariable("HTTPS_PROXY", "http://127.0.0.1:7890");
                var info = CreateGitStartInfo("git.exe", "fetch origin", true);
                if (info.EnvironmentVariables["HTTPS_PROXY"] != null ||
                    !info.Arguments.Contains("-c http.proxy=") ||
                    !info.Arguments.Contains("-c remote.origin.proxy=") ||
                    !info.Arguments.Contains("-c credential.helper="))
                    throw new InvalidDataException("直连重试仍使用代理设置。");
            }
            finally { Environment.SetEnvironmentVariable("HTTPS_PROXY", original); }
        }

        private static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }
    }
}
