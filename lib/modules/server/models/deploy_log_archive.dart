import 'dart:io';

class DeployLogArchive {
  File? file;
  IOSink? _sink;
  final _fallback = StringBuffer();
  String? error;

  Future<void> open(String root) async {
    await close();
    _fallback.clear();
    error = null;
    try {
      final directory = Directory('$root/log/oasx-deploy');
      await directory.create(recursive: true);
      file = File(
        '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.log',
      );
      _sink = file!.openWrite();
      _sink!.done.catchError((Object e) {
        error = '$e';
      });
    } catch (e) {
      file = null;
      error = '$e';
    }
  }

  void add(String line) {
    final record = '${DateTime.now().toIso8601String()} | $line';
    _fallback.writeln(record);
    if (error == null) _sink?.writeln(record);
  }

  Future<String> read() async {
    try {
      await _sink?.flush();
      if (error == null && file != null) return await file!.readAsString();
    } catch (e) {
      error = '$e';
    }
    return _fallback.toString();
  }

  Future<void> close() async {
    try {
      await _sink?.close();
    } catch (_) {
      // 日志写入失败不应阻断启动或重试。
    }
    _sink = null;
  }
}
