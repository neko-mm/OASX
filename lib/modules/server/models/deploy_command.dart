import 'dart:async';
import 'dart:io';

import 'package:process_run/shell.dart';

class DeployCommand {
  DeployCommand(this.shell);

  final Shell shell;
  Process? _process;
  Future<void>? _stopping;
  bool _finished = false;

  Future<List<ProcessResult>> run(String command) async {
    try {
      return await shell.run(command, onProcess: (process) => _process = process);
    } finally {
      _finished = true;
    }
  }

  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    if (_finished) return;
    final process = _process;
    try {
      if (process != null) {
        if (Platform.isWindows) {
          final result = await Process.run('taskkill', [
            '/f', '/t', '/pid', '${process.pid}',
          ]).timeout(const Duration(seconds: 5));
          if (result.exitCode != 0 && result.exitCode != 128) {
            throw StateError('无法结束上次 OAS 启动进程：${result.stderr}');
          }
        } else {
          process.kill();
        }
      }
    } finally {
      shell.kill();
    }
    if (process != null) {
      await process.exitCode.timeout(const Duration(seconds: 5));
    }
  }
}
