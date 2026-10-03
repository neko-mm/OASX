import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/home/models/click_trace_models.dart';
import 'package:oasx/modules/log/log_browser_models.dart';

ScriptLogLine logLine(int lineNo, String text, {String day = '2026-10-02'}) =>
    ScriptLogLine(
      fileName: '${day}_oas.txt',
      lineNo: lineNo,
      offset: lineNo * 100,
      byteLength: text.length,
      text: text,
      lineTruncated: false,
    );

void main() {
  test('collects actual click coordinates under each task', () {
    final trace = ClickTraceAccumulator(day: DateTime(2026, 10, 2));
    final lines = [
      logLine(1, '2026-10-02 10:00:00 | INFO | Start scheduler loop: oas'),
      logLine(2, '2026-10-02 10:00:01 | INFO | Scheduler: Start task `TrueOrochi`'),
      logLine(3, '2026-10-02 10:00:02 | INFO | [0.10s] Click ( 389,   35) @ GB_BUFF_1'),
      logLine(4, '2026-10-02 10:00:03 | INFO | Scheduler: Start task `DailyTrifles`'),
      logLine(5, '2026-10-02 10:00:04 | INFO | [0.05s] Click ( 773,  364) @ GB_CLOSE_RED'),
    ];
    for (final line in lines) {
      trace.add(line);
    }

    expect(trace.entries, hasLength(2));
    expect(trace.entries.first.taskName, 'TrueOrochi');
    expect(trace.entries.first.x, 389);
    expect(trace.entries.first.y, 35);
    expect(trace.entries.first.targetName, 'GB_BUFF_1');
    expect(trace.entries.last.taskName, 'DailyTrifles');
    expect(trace.entries.last.date, '2026-10-02');
    expect(trace.entries.last.time, '10:00:04');
  });

  test('a new scheduler run drops the previous run and its task label', () {
    final trace = ClickTraceAccumulator(day: DateTime(2026, 10, 2));
    trace.add(logLine(1, 'Start scheduler loop: oas'));
    trace.add(logLine(2, 'Scheduler: Start task `TrueOrochi`'));
    trace.add(logLine(3, 'Click ( 100, 200) @ OLD'));
    trace.add(logLine(4, 'Start scheduler loop: oas'));
    trace.add(logLine(5, 'Click ( 300, 400) @ NEW'));

    expect(trace.entries, hasLength(1));
    expect(trace.entries.single.x, 300);
    expect(trace.entries.single.date, '2026-10-02');
    expect(trace.entries.single.taskName, isEmpty);
  });

  test('ignores lines that are not actual click logs', () {
    final trace = ClickTraceAccumulator(day: DateTime(2026, 10, 2));
    final line = logLine(1, '2026-10-02 10:00:02 | INFO | Click image not found');
    expect(ClickTraceAccumulator.isRelevant(line), isFalse);
    expect(trace.add(line), isFalse);
    expect(trace.entries, isEmpty);
  });

  test('only keeps clicks from the selected day when one run crosses midnight', () {
    final trace = ClickTraceAccumulator(day: DateTime(2026, 10, 3));
    final yesterday = logLine(1, 'Click ( 100, 200) @ OLD', day: '2026-10-02');
    final today = logLine(1, 'Click ( 300, 400) @ NEW', day: '2026-10-03');

    expect(
      ClickTraceAccumulator.isRelevantForDay(yesterday, trace.day),
      isFalse,
    );
    expect(trace.add(yesterday), isFalse);
    expect(ClickTraceAccumulator.isRelevantForDay(today, trace.day), isTrue);
    expect(trace.add(today), isTrue);
    expect(trace.entries.single.x, 300);
    expect(trace.entries.single.date, '2026-10-03');
  });

  test('history loading stops after reaching yesterday\'s log lines', () {
    final day = DateTime(2026, 10, 3);
    final mixedPage = [
      logLine(100, 'Click ( 100, 200) @ OLD', day: '2026-10-02'),
      logLine(1, 'Click ( 300, 400) @ NEW', day: '2026-10-03'),
    ];
    expect(
      ClickTraceAccumulator.reachedDayStart(
        mixedPage,
        day,
        hasOlder: true,
      ),
      isTrue,
    );
  });

  test('uses the log timestamp when a file contains an older click', () {
    final line = logLine(
      1,
      '2026-10-02 23:59:59 | INFO | Click ( 100, 200) @ OLD',
      day: '2026-10-03',
    );

    expect(ClickTraceAccumulator.dateOf(line), '2026-10-02');
    expect(
      ClickTraceAccumulator.isOnDay(line, DateTime(2026, 10, 3)),
      isFalse,
    );
  });

  test('recognizes Chinese scheduler and task logs without losing task colors',
      () {
    final trace = ClickTraceAccumulator(day: DateTime(2026, 10, 3));
    trace.add(logLine(
      1,
      '2026-10-03 10:00:00 | INFO | 开始运行任务调度：oas',
      day: '2026-10-03',
    ));
    trace.add(logLine(
      2,
      '2026-10-03 10:00:01 | INFO | 开始任务：每日琐事（DailyTrifles）',
      day: '2026-10-03',
    ));
    trace.add(logLine(
      3,
      '2026-10-03 10:00:02 | INFO | Click ( 389,   35) @ NEW',
      day: '2026-10-03',
    ));

    expect(trace.hasRunStart, isTrue);
    expect(trace.entries.single.taskName, 'DailyTrifles');
  });
}
