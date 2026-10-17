import 'package:process_run/shell.dart';

import 'package:oasx/modules/server/models/deploy_git_config.dart';

/// Runs a visible Git prefetch before the Python installer starts.
class DeployGitPrefetcher {
  /// Creates one prefetcher using the controller shell runner.
  const DeployGitPrefetcher({
    required this.rootPath,
    required this.log,
    required this.runShell,
    required this.readShell,
    required this.onAvailable,
    required this.onUnchanged,
    required this.onDisabled,
    required this.onFetched,
  });

  /// OAS root path used as the Git working directory.
  final String rootPath;

  /// Writes deployment log lines.
  final void Function(String message) log;

  /// Runs one shell command and reports whether it succeeded.
  final Future<bool> Function(String command, {bool allowFailure}) runShell;
  final Future<String?> Function(String command, {bool allowFailure}) readShell;
  final void Function() onAvailable;
  final void Function() onUnchanged;
  final void Function() onDisabled;
  final void Function() onFetched;

  /// Fetches the configured branch with progress output.
  Future<bool> prefetchRepository() async {
    try {
      final config = DeployGitConfig.read(rootPath);
      if (!config.autoUpdate) {
        onDisabled();
        return true;
      }
      final configured = await _configureRepository(config);
      if (!configured) {
        return false;
      }
      final head = await _readGit(config, [
        'rev-parse',
        '--verify',
        'HEAD',
      ], allowFailure: true);
      final remote = await _readGit(config, [
        'ls-remote',
        '--exit-code',
        'origin',
        'refs/heads/${config.branch}',
      ]);
      if (remote == null) return false;
      final revision = parseRemoteRevision(remote, config.branch);
      if (revision == null) {
        log('ERROR: 未能读取远程分支版本：${config.branch}');
        return false;
      }
      if (head?.trim() != revision) {
        onAvailable();
      } else {
        onUnchanged();
      }
      if (!await _fetchBranch(config)) return false;
      // 远程分支可能在检查与拉取之间更新。
      final fetched = await _readGit(config, [
        'rev-parse',
        '--verify',
        'FETCH_HEAD',
      ]);
      if (fetched == null) return false;
      if (head?.trim() != fetched.trim()) onAvailable();
      onFetched();
      return true;
    } catch (e) {
      log('ERROR: Failed to prepare git fetch: $e');
      return false;
    }
  }

  static String? parseRemoteRevision(String output, String branch) {
    for (final line in output.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length == 2 &&
          parts[1] == 'refs/heads/$branch' &&
          RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(parts[0])) {
        return parts[0];
      }
    }
    return null;
  }

  Future<String?> _readGit(
    DeployGitConfig config,
    List<String> arguments, {
    bool allowFailure = false,
  }) {
    final command = shellExecutableArguments(
      config.getExecutablePath(rootPath),
      arguments,
    );
    log('INFO: $command');
    return readShell(command, allowFailure: allowFailure);
  }

  Future<bool> _configureRepository(DeployGitConfig config) async {
    if (!await _runGitCommand(config, ['init'])) {
      return false;
    }
    final remoteUpdated = await _runGitCommand(config, [
      'remote',
      'set-url',
      'origin',
      config.repository,
    ], allowFailure: true);
    if (!remoteUpdated &&
        !await _runGitCommand(config, [
          'remote',
          'add',
          'origin',
          config.repository,
        ])) {
      return false;
    }
    return _configureNetwork(config);
  }

  Future<bool> _configureNetwork(DeployGitConfig config) async {
    if (config.gitProxy.isNotEmpty) {
      if (!await _runGitCommand(config, [
        'config',
        '--local',
        'http.proxy',
        config.gitProxy,
      ])) {
        return false;
      }
      if (!await _runGitCommand(config, [
        'config',
        '--local',
        'https.proxy',
        config.gitProxy,
      ])) {
        return false;
      }
    }
    if (!await _runGitCommand(config, [
      'config',
      '--local',
      'http.version',
      'HTTP/1.1',
    ])) {
      return false;
    }
    return _runGitCommand(config, [
      'config',
      '--local',
      'core.compression',
      '0',
    ]);
  }

  Future<bool> _fetchBranch(DeployGitConfig config) async {
    log(
      'INFO: ==================== PREFETCH REPOSITORY BRANCH ====================',
    );
    return _runGitCommand(config, [
      '-c',
      'http.version=HTTP/1.1',
      '-c',
      'core.compression=0',
      'fetch',
      '--progress',
      'origin',
      config.branch,
    ]);
  }

  Future<bool> _runGitCommand(
    DeployGitConfig config,
    List<String> arguments, {
    bool allowFailure = false,
  }) {
    final git = config.getExecutablePath(rootPath);
    final command = shellExecutableArguments(git, arguments);
    log('INFO: $command');
    return runShell(command, allowFailure: allowFailure);
  }
}
