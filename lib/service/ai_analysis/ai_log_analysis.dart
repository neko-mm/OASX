import 'package:oasx/modules/log/log_browser_models.dart';

/// Only text from the most recent scheduler run may be prepared for upload.
class AiLogDraft {
  const AiLogDraft({
    required this.text,
    required this.partial,
    required this.lineCount,
  });

  final String text;
  final bool partial;
  final int lineCount;
}

class AiLogAnalysis {
  static final RegExp _runStart =
      RegExp(r'Start scheduler loop:|开始运行任务调度：');
  static final RegExp _sensitiveLine = RegExp(
    r'password|passwd|token|secret|api.?key|authorization|cookie|账号|昵称|用户名|用户ID|登录凭证|角色名|玩家名|\bUID\b|\bOCR\b|识别文字|识别结果',
    caseSensitive: false,
  );
  static final RegExp _email =
      RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}');
  static final RegExp _url = RegExp(r'https?://\S+', caseSensitive: false);
  static final RegExp _windowsPath = RegExp(r'[A-Za-z]:[\\/]\S+');
  static final RegExp _unixPath = RegExp(r'/(?:Users|home|var|tmp)/\S+');
  static final RegExp _ipv4 =
      RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b');

  /// Pages are supplied newest first, while lines within each page are oldest first.
  static AiLogDraft prepare(List<List<ScriptLogLine>> newestFirstPages) {
    final seen = <String>{};
    final lines = newestFirstPages.reversed
        .expand((page) => page)
        .where((line) => seen.add(line.key))
        .toList(growable: false);
    final start = lines.lastIndexWhere((line) => _runStart.hasMatch(line.text));
    final runLines = start >= 0 ? lines.sublist(start) : lines;
    const maxLines = 240;
    final truncated = runLines.length > maxLines;
    final recent = truncated
        ? runLines.sublist(runLines.length - maxLines)
        : runLines;
    final safe = <String>[];
    for (final line in recent) {
      if (_sensitiveLine.hasMatch(line.text)) continue;
      // Replacement is sequential: each stage sees the previous stage's output.
      var text = line.text;
      text = text.replaceAll(_email, '[邮箱]');
      text = text.replaceAll(_url, '[网址]');
      text = text.replaceAll(_windowsPath, '[本地路径]');
      text = text.replaceAll(_unixPath, '[本地路径]');
      text = text.replaceAll(_ipv4, '[地址]');
      if (text.trim().isNotEmpty) safe.add(text);
    }
    return AiLogDraft(
      text: safe.join('\n'),
      partial: start < 0 || truncated,
      lineCount: safe.length,
    );
  }

  /// Deterministic, offline triage; the model never decides whether OAS runs.
  static String localSummary(String text, {required bool partial}) {
    if (text.trim().isEmpty) return '没有可分析的日志';
    if (RegExp(r'ERROR|CRITICAL|Traceback|错误|异常').hasMatch(text)) {
      return '日志中有错误信息，可用 AI 进一步分析。';
    }
    if (RegExp(r'No task pending|没有待运行任务').hasMatch(text)) {
      return '任务队列已空，本轮按调度逻辑结束。';
    }
    if (RegExp(r'WARNING|警告').hasMatch(text)) {
      return '日志中有警告，尚不能判断是否影响任务。';
    }
    return partial ? '只取得部分日志，暂不能判断任务结果。' : '未发现明确错误。';
  }
}
