import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:process_run/shell.dart';
import 'package:oasx/modules/server/models/deploy_command.dart';
import 'package:oasx/modules/server/models/deploy_retry.dart';

void main() {
  test('recognizes the failure banner from either output stream', () {
    for (final line in [
      '|        UPDATE FAILED        |',
      'ERROR: update failed',
      '\x1b[31mUPDATE\x1b[0m FAILED',
    ]) {
      final monitor = DeployFailureMonitor()..addLine(line);
      expect(monitor.hasFailed, isTrue, reason: line);
    }
    final monitor = DeployFailureMonitor()..addLine('Receiving objects: 50%');
    expect(monitor.hasFailed, isFalse);
  });

  test('failure stops and drains a command that is waiting for input', () async {
    final command = Completer<bool>();
    final monitor = DeployFailureMonitor();
    var stops = 0;
    final result = monitor.watch(command.future, stop: () async {
      stops++;
      command.complete(false);
    });
    monitor.addLine('UPDATE FAILED');
    monitor.addLine('UPDATE FAILED');
    expect(await result, isFalse);
    expect(stops, 1);
  });

  test('successful command is not stopped', () async {
    final monitor = DeployFailureMonitor();
    var stops = 0;
    expect(await monitor.watch(Future.value(true), stop: () async {
      stops++;
    }), isTrue);
    expect(stops, 0);
  });

  test('does not retry after cleanup fails', () async {
    final runner = DeployRetryRunner();
    var attempts = 0;
    await expectLater(
      runner.run(
        attempt: (_) async {
          attempts++;
          throw StateError('previous process is still running');
        },
        onRetry: (_, __) {},
        wait: (_) async {},
      ),
      throwsStateError,
    );
    expect(attempts, 1);
  });

  test('retries at most five times after the initial failure', () async {
    final attempts = <int>[];
    final retries = <int>[];
    final delays = <int>[];
    final result = await DeployRetryRunner().run(
      attempt: (retry) async {
        attempts.add(retry);
        return false;
      },
      onRetry: (retry, _) => retries.add(retry),
      wait: (delay) async => delays.add(delay.inSeconds),
    );
    expect(result, isFalse);
    expect(attempts, [0, 1, 2, 3, 4, 5]);
    expect(retries, [1, 2, 3, 4, 5]);
    expect(delays, [3, 6, 9, 12, 15]);
  });

  test('stops retrying immediately after a successful attempt', () async {
    final attempts = <int>[];
    final result = await DeployRetryRunner().run(
      attempt: (retry) async {
        attempts.add(retry);
        return retry == 2;
      },
      onRetry: (_, __) {},
      wait: (_) async {},
    );
    expect(result, isTrue);
    expect(attempts, [0, 1, 2]);
  });

  test('waits for cleanup before starting the next attempt', () async {
    final events = <String>[];
    final result = await DeployRetryRunner().run(
      attempt: (retry) async {
        events.add('start $retry');
        if (retry == 1) return true;
        final monitor = DeployFailureMonitor();
        final command = Completer<bool>();
        final watched = monitor.watch(command.future, stop: () async {
          await Future<void>.delayed(Duration.zero);
          events.add('stopped');
          command.complete(false);
        });
        monitor.addLine('UPDATE FAILED');
        return watched;
      },
      onRetry: (_, __) => events.add('retry'),
      wait: (_) async {},
    );
    expect(result, isTrue);
    expect(events, ['start 0', 'stopped', 'retry', 'start 1']);
  });

  test('cancelling during the delay prevents another process start', () async {
    final runner = DeployRetryRunner();
    var attempts = 0;
    final result = await runner.run(
      attempt: (_) async {
        attempts++;
        return false;
      },
      onRetry: (_, __) => runner.cancel(),
      wait: (_) => Completer<void>().future,
    );
    expect(result, isFalse);
    expect(attempts, 1);
  });

  test('terminates a real waiting process after UPDATE FAILED', () async {
    final lines = ShellLinesController();
    final monitor = DeployFailureMonitor();
    final subscription = lines.stream.listen(monitor.addLine);
    final command = DeployCommand(Shell(
      stdout: lines.sink,
      stderr: lines.sink,
      verbose: false,
      runInShell: false,
    ));
    try {
      final script = Platform.isWindows
          ? 'cmd.exe /d /c "echo UPDATE FAILED & ping -n 30 127.0.0.1 >nul"'
          : 'sh -c "echo UPDATE FAILED; exec sleep 30"';
      final result = command.run(script).then((_) => true,
          onError: (Object _) => false);
      expect(await monitor.watch(result, stop: command.stop), isFalse);
      expect(monitor.hasFailed, isTrue);
      await command.stop();
    } finally {
      await command.stop();
      await subscription.cancel();
      lines.close();
    }
  }, timeout: const Timeout(Duration(seconds: 15)));
}
