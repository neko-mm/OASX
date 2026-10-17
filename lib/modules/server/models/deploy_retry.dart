import 'dart:async';

class DeployFailureMonitor {
  static final _updateFailed = RegExp(
    r'\bUPDATE\s+FAILED\b',
    caseSensitive: false,
  );
  static final _ansi = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');
  final _failure = Completer<void>();

  bool get hasFailed => _failure.isCompleted;
  Future<void> get failed => _failure.future;

  void addLine(String line) {
    if (_updateFailed.hasMatch(line.replaceAll(_ansi, ''))) {
      fail();
    }
  }

  void fail() {
    if (!hasFailed) _failure.complete();
  }

  Future<bool> watch(
    Future<bool> command, {
    required Future<void> Function() stop,
  }) async {
    final succeeded = await Future.any([
      command,
      failed.then((_) => false),
    ]);
    if (hasFailed) {
      await stop();
      await command.timeout(const Duration(seconds: 5));
      return false;
    }
    return succeeded;
  }
}

class DeployRetryRunner {
  DeployRetryRunner({this.maxRetries = 5});

  final int maxRetries;
  final _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  Future<bool> run({
    required Future<bool> Function(int retry) attempt,
    required void Function(int retry, Duration delay) onRetry,
    Future<void> Function(Duration)? wait,
  }) async {
    final pause = wait ?? ((Duration delay) => Future<void>.delayed(delay));
    for (var retry = 0; retry <= maxRetries; retry++) {
      if (isCancelled) return false;
      if (retry > 0) {
        final delay = Duration(seconds: retry * 3);
        onRetry(retry, delay);
        await Future.any([
          pause(delay),
          _cancelled.future,
        ]);
        if (isCancelled) return false;
      }
      if (await attempt(retry)) return true;
    }
    return false;
  }
}
