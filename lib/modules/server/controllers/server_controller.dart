import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:process_run/shell.dart';

import 'package:oasx/api/api_client.dart';
import 'package:oasx/modules/common/models/storage_key.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/log/log_mixin.dart';
import 'package:oasx/modules/server/models/deploy_command.dart';
import 'package:oasx/modules/server/models/deploy_git_prefetcher.dart';
import 'package:oasx/modules/server/models/deploy_python_config.dart';
import 'package:oasx/modules/server/models/deploy_retry.dart';
import 'package:oasx/modules/server/models/deploy_progress.dart';
import 'package:oasx/modules/server/models/deploy_log_archive.dart';
import 'package:oasx/modules/settings/controllers/settings_controller.dart';
import 'package:oasx/service/locale_service.dart';
import 'package:oasx/service/oas_git_locator.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/translation/i18n_content.dart';

class DeployLogEntry {
  const DeployLogEntry(this.time, this.line);

  final DateTime time;
  final String line;
}

class ServerController extends GetxController with LogMixin {
  @override
  int get maxLines => 1000;

  final rootPathServer = ''.obs;
  final rootPathAuthenticated = true.obs;
  final showDeploy = true.obs;
  final deployContent = ''.obs;
  final autoLoginAfterDeploy = false.obs;
  final isDeployLoading = false.obs;
  final deployPhase = I18n.homeDeployPreparing.obs;
  final deployRetryCount = 0.obs;
  final deployLogEntries = <DeployLogEntry>[].obs;
  final deployProgress = DeployProgress().obs;
  final _deployArchive = DeployLogArchive();
  bool _recordingDeploy = false;
  static const maxDeployRetries = 5;
  DeployFailureMonitor? _failureMonitor;
  DeployRetryRunner? _retryRunner;
  DeployCommand? _activeCommand;
  Future<bool>? _deployment;
  final _storage = GetStorage();
  Shell? shell;
  var shellController = ShellLinesController();
  var shellErrorController = ShellLinesController();

  @override
  void addLog(String log) {
    _failureMonitor?.addLine(log);
    _recordDeploymentLine(log);
    super.addLog(log);
    deployLogEntries.add(DeployLogEntry(DateTime.now(), log));
    if (deployLogEntries.length > 200) {
      deployLogEntries.removeRange(0, deployLogEntries.length - 200);
    }
  }

  void _recordDeploymentLine(String log) {
    if (!_recordingDeploy) return;
    _deployArchive.add(log);
    if (deployProgress.value.consume(log)) deployProgress.refresh();
  }

  void _progress(void Function(DeployProgress progress) change) {
    change(deployProgress.value);
    deployProgress.refresh();
  }

  Future<String> readCompleteDeployLog() => _deployArchive.read();

  String get deployStatusText {
    final phase = deployPhase.value.tr;
    if (deployRetryCount.value == 0 ||
        deployPhase.value == I18n.homeDeployFailed) {
      return phase;
    }
    return '$phase · ${I18n.homeDeployRetryCount.trParams({'count': '${deployRetryCount.value}', 'total': '$maxDeployRetries'})}';
  }

  @override
  void upsertLog(String log, bool Function(String log) shouldReplace) {
    final index = deployLogEntries.lastIndexWhere(
      (entry) => shouldReplace(entry.line),
    );
    final lastBefore = deployLogEntries.isEmpty ? null : deployLogEntries.last;
    super.upsertLog(log, shouldReplace);
    final appendedBySuper =
        deployLogEntries.isNotEmpty &&
        !identical(deployLogEntries.last, lastBefore);
    if (index >= 0 && !appendedBySuper) {
      _recordDeploymentLine(log);
      deployLogEntries.removeAt(index);
      deployLogEntries.add(DeployLogEntry(DateTime.now(), log));
    } else if (index < 0 && !appendedBySuper) {
      _recordDeploymentLine(log);
      deployLogEntries.add(DeployLogEntry(DateTime.now(), log));
    }
  }

  @override
  void clearLog() {
    super.clearLog();
    deployLogEntries.clear();
  }

  /// Tracks whether taskkill already reported that pythonw.exe is absent.
  var _pythonwNotRunningLogged = false;

  @override
  void onInit() {
    rootPathServer.value =
        _storage.read(StorageKey.rootPathServer.name) ??
        'Please set OAS root path';
    autoLoginAfterDeploy.value =
        _storage.read(StorageKey.autoLoginAfterDeploy.name) ?? false;
    shell = getShell;
    shellController.stream.listen(
      (event) => addLog(!event.contains('INFO') ? 'INFO: $event' : event),
    );
    shellErrorController.stream.listen(_addShellErrorLine);
    rootPathAuthenticated.value = authenticatePath(rootPathServer.value);
    if (rootPathAuthenticated.value) {
      readDeploy();
    }
    super.onInit();
  }

  @override
  void onClose() {
    _retryRunner?.cancel();
    _failureMonitor?.fail();
    unawaited(_stopActiveCommand().catchError((Object _) {}));
    unawaited(_deployArchive.close());
    super.onClose();
  }

  void updateRootPathServer(String value) {
    rootPathAuthenticated.value = authenticatePath(value);
    rootPathServer.value = value;
    OasGitLocator.sync(rootPathAuthenticated.value ? value : null);
    shell = getShell;
    Get.find<SettingsController>().storage.write(
      StorageKey.rootPathServer.name,
      rootPathServer.value,
    );
    if (rootPathAuthenticated.value) {
      readDeploy();
    }
  }

  bool authenticatePath(String root) {
    root.replaceAll('\\', '/');
    try {
      final rootDir = Directory(root);
      if (!rootDir.existsSync()) {
        return false;
      }
      final deploy = File('${rootDir.path}/config/deploy.yaml');
      if (!deploy.existsSync()) {
        return false;
      }
      final pythonConfig = DeployPythonConfig.read(rootDir.path);
      final python = File(pythonConfig.getPythonPath(rootDir.path));
      if (!python.existsSync()) {
        return false;
      }
      final git = File('${rootDir.path}/toolkit/Git/mingw64/bin/git.exe');
      if (!git.existsSync()) {
        return false;
      }
      final installer = File('${rootDir.path}/deploy/installer.py');
      if (!installer.existsSync()) {
        return false;
      }
    } catch (e) {
      printError(info: e.toString());
      return false;
    }
    return true;
  }

  void readDeploy() {
    final filePath = '${rootPathServer.value}\\config\\deploy.yaml';
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        deployContent.value = file.readAsStringSync();
      } else {
        deployContent.value = 'File not found';
      }
    } catch (e) {
      deployContent.value = 'Error reading file: $e';
    }
  }

  void writeDeploy(String value) {
    final filePath = '${rootPathServer.value}\\config\\deploy.yaml';
    deployContent.value = value;
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        file.writeAsStringSync(deployContent.value);
      } else {
        deployContent.value = 'File not found';
      }
    } catch (e) {
      deployContent.value = 'Error writing file: $e';
    }
  }

  /// Imports one YAML file into the current OAS deploy config path.
  bool importDeployFile(String sourcePath) {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      return false;
    }
    if (!sourcePath.toLowerCase().endsWith('.yaml')) {
      return false;
    }
    final targetPath = '${rootPathServer.value}\\config\\deploy.yaml';
    try {
      source.copySync(targetPath);
      readDeploy();
      return true;
    } catch (e) {
      deployContent.value = 'Error importing file: $e';
      return false;
    }
  }

  /// Exports the saved deploy.yaml file to a user-selected path.
  bool exportDeployFile(String targetPath) {
    if (targetPath.trim().isEmpty) {
      return false;
    }
    final sourcePath = '${rootPathServer.value}\\config\\deploy.yaml';
    final normalizedTarget = targetPath.toLowerCase().endsWith('.yaml')
        ? targetPath
        : '$targetPath.yaml';
    try {
      final source = File(sourcePath);
      if (!source.existsSync()) {
        return false;
      }
      source.copySync(normalizedTarget);
      return true;
    } catch (e) {
      deployContent.value = 'Error exporting file: $e';
      return false;
    }
  }

  String get pathGit => '${rootPathServer.value}\\toolkit\\Git\\mingw64\\bin';
  String get pathPython => '${rootPathServer.value}\\toolkit';
  String get pathAdb =>
      '${rootPathServer.value}\\toolkit\\Lib\\site-packages\\adbutils\\binaries';
  String get pathScripts => '${rootPathServer.value}\\toolkit\\Scripts';
  String get pathSeparator => Platform.isWindows ? ';' : ':';
  Map<String, String> get pathPATH => {
    'PATH': [
      rootPathServer.value,
      pathGit,
      pathPython,
      pathAdb,
      pathScripts,
    ].join(pathSeparator),
  };

  Shell get getShell => Shell(
    workingDirectory: rootPathServer.value,
    runInShell: true,
    environment: pathPATH,
    stdout: shellController.sink,
    stderr: shellErrorController.sink,
    verbose: false,
  );

  /// Runs one shell command and records failures with the requested severity.
  Future<bool> runShell(
    String command, {
    bool allowFailure = false,
    bool ignorePythonwNotRunning = false,
    void Function(List<ProcessResult> results)? onResult,
  }) async {
    if (ignorePythonwNotRunning) {
      _pythonwNotRunningLogged = false;
    }
    final active = DeployCommand(getShell);
    _activeCommand = active;
    shell = active.shell;
    Future<bool> execute() async {
      try {
        final results = await active.run(command);
        onResult?.call(results);
        return true;
      } on ShellException catch (e) {
        if (ignorePythonwNotRunning && _isPythonwNotRunningException(e)) {
          if (!_pythonwNotRunningLogged) {
            addLog('WARNING: pythonw.exe is not running, skip taskkill');
          }
          return true;
        }
        _addShellExceptionLog(e, allowFailure: allowFailure);
        return false;
      }
    }

    final result = execute();
    final monitor = _failureMonitor;
    return monitor == null ? result : monitor.watch(result, stop: active.stop);
  }

  Future<void> _stopActiveCommand() async {
    await _activeCommand?.stop();
  }

  /// Adds a shell exception using info or error severity.
  void _addShellExceptionLog(
    ShellException exception, {
    required bool allowFailure,
  }) {
    final prefix = allowFailure ? 'INFO' : 'ERROR';
    addLog('$prefix: ${exception.toString()}');
  }

  /// Detects the taskkill exit code used when pythonw.exe is absent.
  bool _isPythonwNotRunningException(ShellException exception) {
    final lower = exception.message.toLowerCase();
    return exception.result?.exitCode == 128 &&
        lower.contains('taskkill') &&
        lower.contains('pythonw.exe');
  }

  void _addShellErrorLine(String line) {
    final lower = line.toLowerCase();
    final expectedTaskKillOutput = _isExpectedTaskKillOutput(lower);
    if (expectedTaskKillOutput) {
      _pythonwNotRunningLogged = true;
      final message = line.replaceFirst(
        RegExp(r'^\s*ERROR:\s*', caseSensitive: false),
        '',
      );
      addLog('WARNING: $message');
      return;
    }
    if (_isGitProgressLine(lower)) {
      upsertLog('INFO: $line', _isGitProgressLog);
      return;
    }
    final isError = lower.contains('fatal:') || lower.contains('error:');
    addLog('${isError ? 'ERROR' : 'INFO'}: $line');
  }

  /// Detects taskkill output when no pythonw.exe process is running.
  bool _isExpectedTaskKillOutput(String lowerLine) {
    return lowerLine.contains('pythonw.exe') &&
        (lowerLine.contains('not found') || lowerLine.contains('没有找到'));
  }

  bool _isGitProgressLine(String lowerLine) {
    return lowerLine.startsWith('remote: enumerating objects:') ||
        lowerLine.startsWith('remote: counting objects:') ||
        lowerLine.startsWith('remote: compressing objects:') ||
        lowerLine.startsWith('receiving objects:') ||
        lowerLine.startsWith('resolving deltas:') ||
        lowerLine.startsWith('updating files:');
  }

  bool _isGitProgressLog(String log) {
    return _isGitProgressLine(log.replaceFirst('INFO: ', '').toLowerCase());
  }

  Future<bool> prefetchRepository() async {
    final prefetcher = DeployGitPrefetcher(
      rootPath: rootPathServer.value,
      log: addLog,
      runShell: runShell,
      readShell: _readShell,
      onAvailable: () => _progress((progress) => progress.updateAvailable()),
      onUnchanged: () => _progress((progress) => progress.noUpdate()),
      onDisabled: () =>
          _progress((progress) => progress.noUpdate(disabled: true)),
      onFetched: () => _progress((progress) => progress.fetched()),
    );
    return prefetcher.prefetchRepository();
  }

  Future<String?> _readShell(
    String command, {
    bool allowFailure = false,
  }) async {
    String? output;
    final succeeded = await runShell(
      command,
      allowFailure: allowFailure,
      onResult: (results) =>
          output = results.map((result) => '${result.stdout}').join('\n'),
    );
    return succeeded ? output : null;
  }

  Future<bool> run({bool killAllPythonw = true}) {
    return _deployment ??= _runWithRetries(
      killAllPythonw: killAllPythonw,
    ).whenComplete(() => _deployment = null);
  }

  Future<bool> _runWithRetries({required bool killAllPythonw}) async {
    isDeployLoading.value = true;
    deployRetryCount.value = 0;
    deployPhase.value = I18n.homeDeployPreparing;
    final runner = DeployRetryRunner(maxRetries: maxDeployRetries);
    _retryRunner = runner;
    try {
      await _stopActiveCommand();
      if (Get.isRegistered<SettingsController>()) {
        await Get.find<SettingsController>().killServer(
          showTip: false,
          resetDashboardToDisconnected: false,
        );
      }
      clearLog();
      await _deployArchive.open(rootPathServer.value);
      _recordingDeploy = true;
      deployProgress.value = DeployProgress();
      final succeeded = await runner.run(
        attempt: (retry) async {
          _progress((progress) => progress.beginAttempt(retry));
          addLog('INFO: 开始 OAS 启动尝试（自动重试 $retry / $maxDeployRetries）');
          _failureMonitor = DeployFailureMonitor();
          final started = await _runDeployAttempt(
            killAllPythonw: killAllPythonw && retry == 0,
          );
          if (!started) {
            _progress((progress) {
              if (![
                ...progress.startup,
                ...progress.update,
              ].any((stage) => stage.status == DeployStageStatus.failed)) {
                progress.failed('本次尝试未成功，请查看完整日志了解原因');
              }
            });
            await _stopActiveCommand();
          }
          return started;
        },
        onRetry: (retry, delay) {
          deployRetryCount.value = retry;
          deployPhase.value = I18n.homeDeployRetrying;
          _progress((progress) => progress.retrying(retry, delay));
          addLog(
            'WARNING: ${I18n.homeDeployRetryDelay.trParams({'count': '$retry', 'total': '$maxDeployRetries', 'seconds': '${delay.inSeconds}'})}',
          );
        },
      );
      if (!succeeded && !runner.isCancelled) {
        deployPhase.value = I18n.homeDeployFailed;
        addLog('ERROR: ${I18n.homeDeployFailed.tr}');
      }
      return succeeded;
    } catch (e) {
      deployPhase.value = I18n.homeDeployFailed;
      addLog('ERROR: OAS 启动失败：$e');
      _progress((progress) => progress.failed('启动过程发生异常，请查看完整日志'));
      try {
        await _stopActiveCommand();
      } catch (stopError) {
        addLog('ERROR: $stopError');
      }
      return false;
    } finally {
      _failureMonitor = null;
      _retryRunner = null;
      _recordingDeploy = false;
      await _deployArchive.close();
      isDeployLoading.value = false;
    }
  }

  Future<bool> _runDeployAttempt({required bool killAllPythonw}) async {
    deployPhase.value = I18n.homeDeployPreparing;
    await runShell('echo OAS working directory: ');
    await runShell('cd');
    if (killAllPythonw) {
      await runShell(
        'taskkill /f /t /im pythonw.exe',
        ignorePythonwNotRunning: true,
      );
    }
    deployPhase.value = I18n.homeDeployUpdating;
    _progress((progress) => progress.checkingUpdate());
    if (!await prefetchRepository() || _failureMonitor!.hasFailed) {
      _progress(
        (progress) => progress.failed('检查或拉取更新失败，请查看完整日志', duringUpdate: true),
      );
      return false;
    }
    final pythonConfig = DeployPythonConfig.read(rootPathServer.value);
    deployPhase.value = I18n.homeDeployInstalling;
    _progress((progress) => progress.installing());
    final installed = await runShell(
      shellExecutableArguments(
        pythonConfig.getPythonPath(rootPathServer.value),
        ['-m', 'deploy.installer'],
      ),
    );
    if (!installed || _failureMonitor!.hasFailed) return false;

    deployPhase.value = I18n.homeDeployStarting;
    _progress((progress) => progress.startingService());
    final serverRun = runShell(
      shellExecutableArguments(
        pythonConfig.getPythonwPath(rootPathServer.value),
        ['server.py'],
      ),
    );
    final monitor = _failureMonitor!;
    var serverExited = false;
    final exited = serverRun.then((_) {
      serverExited = true;
      return false;
    });
    final storedAddress = _storage.read<String>(StorageKey.address.name) ?? '';
    final address = storedAddress.isEmpty ? ApiClient().address : storedAddress;
    deployPhase.value = I18n.homeDeployConnecting;
    _progress((progress) => progress.connecting());
    final connected = await Future.any([
      _tryConnect(
        address,
        retries: 60,
        retryDelay: const Duration(milliseconds: 500),
        loginAfterConnected: _resolveAutoLoginAfterDeploy(),
        shouldStop: () => monitor.hasFailed || serverExited,
      ),
      exited,
      monitor.failed.then((_) => false),
    ]);
    if (!connected) {
      _progress(
        (progress) => progress.failed(
          serverExited ? 'OAS 后台服务提前退出，请查看完整日志' : '等待 OAS 服务连接超时，请查看完整日志',
          duringUpdate: false,
        ),
      );
      monitor.fail();
      await _stopActiveCommand();
      await serverRun;
    } else {
      _progress((progress) => progress.connected());
    }
    return connected;
  }

  bool _resolveAutoLoginAfterDeploy() {
    if (Get.isRegistered<SettingsController>()) {
      final value = Get.find<SettingsController>().autoLoginAfterDeploy.value;
      autoLoginAfterDeploy.value = value;
      return value;
    }
    final value = _storage.read(StorageKey.autoLoginAfterDeploy.name) ?? false;
    autoLoginAfterDeploy.value = value;
    return value;
  }

  Future<bool> _tryConnect(
    String rawAddress, {
    int retries = 1,
    Duration retryDelay = const Duration(milliseconds: 500),
    bool loginAfterConnected = true,
    bool Function()? shouldStop,
  }) async {
    final address =
        rawAddress.startsWith('http://') || rawAddress.startsWith('https://')
        ? rawAddress
        : 'http://$rawAddress';
    ApiClient().setAddress(address);

    for (int i = 0; i < retries; i++) {
      if (shouldStop?.call() ?? false) return false;
      final connected = await ApiClient().testAddress();
      if (shouldStop?.call() ?? false) return false;
      if (connected) {
        if (!loginAfterConnected) return true;
        try {
          if (Get.isRegistered<HomeDashboardController>()) {
            await Get.find<HomeDashboardController>()
                .refreshAfterExternalConnected();
          } else if (Get.isRegistered<ScriptService>()) {
            await Get.find<ScriptService>().reloadFromServer();
          }
        } catch (_) {
          // Keep navigation behavior even if dashboard refresh fails here.
        }
        if (Get.isRegistered<LocaleService>()) {
          try {
            await Get.find<LocaleService>().refreshTransFromRemote();
          } catch (_) {}
        }
        Get.offAllNamed('/home');
        return true;
      }
      if (i < retries - 1) {
        await Future.delayed(retryDelay);
      }
    }
    return false;
  }
}
