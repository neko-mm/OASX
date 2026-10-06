import 'package:oasx/modules/log/log_browser_models.dart';

class AiLogDraft {
  const AiLogDraft({
    required this.text,
    required this.partial,
    required this.lineCount,
    required this.sourceLineCount,
  });

  final String text;
  final bool partial;
  final int lineCount;
  final int sourceLineCount;
}

class AiLogAnalysis {
  static final RegExp _runStart =
      RegExp(r'Start scheduler loop:|开始运行任务调度：');
  static final RegExp _taskStart = RegExp(r'开始任务：|Scheduler: Start task');
  static final RegExp _idle =
      RegExp(r'当前没有待运行任务|No task pending');
  static final RegExp _keyEvent = RegExp(
    r'开始任务：|任务结束：|Start scheduler loop:|开始运行任务调度：|'
    r'Scheduler: (?:Start|End) task|当前没有待运行任务|No task pending|'
    r'下个任务：|战斗结果|已进行\s*\d+\s*场战斗|Get reward success|'
    r'领取.*成功|WARNING|ERROR|CRITICAL|Traceback|警告|异常|失败',
    caseSensitive: false,
  );
  static final RegExp _warning = RegExp(
    r'WARNING|ERROR|CRITICAL|Traceback|警告|异常|失败',
    caseSensitive: false,
  );
  static final RegExp _recovery =
      RegExp(r'Page arrived|到达页面|已返回|重试成功|恢复正常');
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

  static List<ScriptLogLine> _orderedLines(
      List<List<ScriptLogLine>> newestFirstPages) {
    final seen = <String>{};
    return newestFirstPages.reversed
        .expand((page) => page)
        .where((line) => seen.add(line.key))
        .toList(growable: false);
  }

  static int? _cycleStart(List<ScriptLogLine> lines) {
    var sawTaskStart = false;
    for (var index = lines.length - 1; index >= 0; index--) {
      final text = lines[index].text;
      if (_runStart.hasMatch(text)) return index;
      if (_idle.hasMatch(text) && sawTaskStart) return index + 1;
      if (_taskStart.hasMatch(text)) sawTaskStart = true;
    }
    return null;
  }

  static bool hasCycleBoundary(List<List<ScriptLogLine>> newestFirstPages) =>
      _cycleStart(_orderedLines(newestFirstPages)) != null;

  static AiLogDraft prepare(
    List<List<ScriptLogLine>> newestFirstPages, {
    bool historyIncomplete = false,
  }) {
    final lines = _orderedLines(newestFirstPages);
    final start = _cycleStart(lines);
    final runLines = lines.sublist(start ?? 0);
    final essential = <int>{};
    final context = <int>{};
    for (var index = 0; index < runLines.length; index++) {
      final text = runLines[index].text;
      if (!_keyEvent.hasMatch(text)) continue;
      essential.add(index);
      if (!_warning.hasMatch(text)) continue;
      for (var nearby = index - 2; nearby <= index + 3; nearby++) {
        if (nearby >= 0 && nearby < runLines.length) context.add(nearby);
      }
      final last = index + 60 < runLines.length
          ? index + 60
          : runLines.length - 1;
      for (var nearby = index + 4; nearby <= last; nearby++) {
        if (_taskStart.hasMatch(runLines[nearby].text)) break;
        if (_recovery.hasMatch(runLines[nearby].text)) context.add(nearby);
      }
    }
    const maxSelectedLines = 800;
    final selected = <int>{...essential};
    var shortened = false;
    if (selected.length > maxSelectedLines) {
      shortened = true;
      final ordered = selected.toList()..sort();
      selected
        ..clear()
        ..addAll(ordered.take(100))
        ..addAll(ordered.skip(ordered.length - 700));
    } else {
      final remaining = maxSelectedLines - selected.length;
      final extra = context.difference(selected).toList()..sort();
      if (extra.length > remaining) shortened = true;
      selected.addAll(extra.reversed.take(remaining));
    }
    final orderedSelected = selected.toList()..sort();
    final safe = <String>[];
    for (final index in orderedSelected) {
      final original = runLines[index].text;
      if (_sensitiveLine.hasMatch(original)) continue;
      var text = original;
      text = text.replaceAll(_email, '[邮箱]');
      text = text.replaceAll(_url, '[网址]');
      text = text.replaceAll(_windowsPath, '[本地路径]');
      text = text.replaceAll(_unixPath, '[本地路径]');
      text = text.replaceAll(_ipv4, '[地址]');
      if (text.trim().isNotEmpty) safe.add(text);
    }
    return AiLogDraft(
      text: safe.join('\n'),
      partial: start == null || historyIncomplete || shortened,
      lineCount: safe.length,
      sourceLineCount: runLines.length,
    );
  }

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
