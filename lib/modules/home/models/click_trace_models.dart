import 'package:oasx/modules/log/log_browser_models.dart';

/// One actual tap reported by OAS, in its 1280×720 game coordinates.
class ClickTraceEntry {
  const ClickTraceEntry({
    required this.key,
    required this.date,
    required this.time,
    required this.taskName,
    required this.targetName,
    required this.x,
    required this.y,
  });

  final String key;
  final String date;
  final String time;
  final String taskName;
  final String targetName;
  final int x;
  final int y;
}

/// Extracts this scheduler run's clicks from existing script log lines.
class ClickTraceAccumulator {
  ClickTraceAccumulator({DateTime? day}) : day = day ?? DateTime.now();

  static final RegExp _runStart =
      RegExp(r'\bStart scheduler loop:|开始运行任务调度：');
  static final RegExp _taskStart = RegExp(r'Scheduler: Start task `([^`]+)`');
  static final RegExp _taskStartChinese = RegExp(r'开始任务：(.+)$');
  static final RegExp _taskCodeChinese = RegExp(r'（([^）]+)）$');
  static final RegExp _click =
      RegExp(r'\bClick\s+\(\s*(\d+),\s*(\d+)\)\s+@\s+(\S+)');
  static final RegExp _time = RegExp(r'^\d{4}-\d{2}-\d{2} (\d{2}:\d{2}:\d{2})');
  static final RegExp _date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');
  static final RegExp _fileDate = RegExp(r'(\d{4})-(\d{2})-(\d{2})');

  final DateTime day;
  final List<ClickTraceEntry> entries = [];
  String currentTask = '';
  bool hasRunStart = false;

  static bool isRunStart(ScriptLogLine line) => _runStart.hasMatch(line.text);

  static RegExpMatch? _dateMatch(ScriptLogLine line) =>
      _date.firstMatch(line.text) ?? _fileDate.firstMatch(line.fileName);

  static String? dateOf(ScriptLogLine line) {
    final match = _dateMatch(line);
    if (match == null) return null;
    return '${match.group(1)}-${match.group(2)}-${match.group(3)}';
  }

  static bool isOnDay(ScriptLogLine line, DateTime day) {
    final match = _dateMatch(line);
    if (match == null) return false;
    return int.parse(match.group(1)!) == day.year &&
        int.parse(match.group(2)!) == day.month &&
        int.parse(match.group(3)!) == day.day;
  }

  static bool isRelevantForDay(ScriptLogLine line, DateTime day) =>
      isOnDay(line, day) && isRelevant(line);

  static bool reachedDayStart(
    List<ScriptLogLine> lines,
    DateTime day, {
    required bool hasOlder,
  }) =>
      lines.isEmpty || !isOnDay(lines.first, day) || !hasOlder;

  static bool isRelevant(ScriptLogLine line) {
    final text = line.text;
    return _runStart.hasMatch(text) ||
        _taskStart.hasMatch(text) ||
        _taskStartChinese.hasMatch(text) ||
        _click.hasMatch(text);
  }

  /// Returns true when the visible click list changed.
  bool add(ScriptLogLine line) {
    if (!isOnDay(line, day)) return false;
    final text = line.text;
    if (_runStart.hasMatch(text)) {
      entries.clear();
      currentTask = '';
      hasRunStart = true;
      return true;
    }
    final englishTask = _taskStart.firstMatch(text);
    final chineseTask = _taskStartChinese.firstMatch(text);
    if (englishTask != null || chineseTask != null) {
      final label =
          englishTask?.group(1) ?? chineseTask?.group(1)?.trim() ?? '';
      currentTask = _taskCodeChinese.firstMatch(label)?.group(1) ?? label;
      return false;
    }
    final clickMatch = _click.firstMatch(text);
    if (clickMatch == null) {
      return false;
    }
    entries.add(
      ClickTraceEntry(
        key: line.key,
        date: dateOf(line) ?? '',
        time: _time.firstMatch(text)?.group(1) ?? '',
        taskName: currentTask,
        targetName: clickMatch.group(3) ?? '',
        x: int.parse(clickMatch.group(1)!),
        y: int.parse(clickMatch.group(2)!),
      ),
    );
    return true;
  }
}
