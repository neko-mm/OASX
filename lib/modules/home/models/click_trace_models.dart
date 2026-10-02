import 'package:oasx/modules/log/log_browser_models.dart';

/// One actual tap reported by OAS, in its 1280×720 game coordinates.
class ClickTraceEntry {
  const ClickTraceEntry({
    required this.key,
    required this.time,
    required this.taskName,
    required this.targetName,
    required this.x,
    required this.y,
  });

  final String key;
  final String time;
  final String taskName;
  final String targetName;
  final int x;
  final int y;
}

/// Extracts this scheduler run's clicks from existing script log lines.
class ClickTraceAccumulator {
  static final RegExp _runStart = RegExp(r'\bStart scheduler loop:');
  static final RegExp _taskStart =
      RegExp(r'Scheduler: Start task `([^`]+)`');
  static final RegExp _click =
      RegExp(r'\bClick\s+\(\s*(\d+),\s*(\d+)\)\s+@\s+(\S+)');
  static final RegExp _time = RegExp(r'^\d{4}-\d{2}-\d{2} (\d{2}:\d{2}:\d{2})');

  final List<ClickTraceEntry> entries = [];
  String currentTask = '';
  bool hasRunStart = false;

  static bool isRunStart(ScriptLogLine line) =>
      _runStart.hasMatch(line.text);

  static bool isRelevant(ScriptLogLine line) {
    final text = line.text;
    return _runStart.hasMatch(text) ||
        _taskStart.hasMatch(text) ||
        _click.hasMatch(text);
  }

  /// Returns true when the visible click list changed.
  bool add(ScriptLogLine line) {
    final text = line.text;
    if (_runStart.hasMatch(text)) {
      entries.clear();
      currentTask = '';
      hasRunStart = true;
      return true;
    }
    final taskMatch = _taskStart.firstMatch(text);
    if (taskMatch != null) {
      currentTask = taskMatch.group(1) ?? '';
      return false;
    }
    final clickMatch = _click.firstMatch(text);
    if (clickMatch == null) {
      return false;
    }
    entries.add(
      ClickTraceEntry(
        key: line.key,
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
