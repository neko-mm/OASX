import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/home/models/click_trace_models.dart';
import 'package:oasx/modules/log/log_browser_models.dart';

ScriptLogLine logLine(int lineNo, String text) => ScriptLogLine(
      fileName: 'oas-2026-10-02.log',
      lineNo: lineNo,
      offset: lineNo * 100,
      byteLength: text.length,
      text: text,
      lineTruncated: false,
    );

void main() {
  test('collects actual click coordinates under each task', () {
    final trace = ClickTraceAccumulator();
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
    expect(trace.entries.last.time, '10:00:04');
  });

  test('a new scheduler run drops the previous run and its task label', () {
    final trace = ClickTraceAccumulator();
    trace.add(logLine(1, 'Start scheduler loop: oas'));
    trace.add(logLine(2, 'Scheduler: Start task `TrueOrochi`'));
    trace.add(logLine(3, 'Click ( 100, 200) @ OLD'));
    trace.add(logLine(4, 'Start scheduler loop: oas'));
    trace.add(logLine(5, 'Click ( 300, 400) @ NEW'));

    expect(trace.entries, hasLength(1));
    expect(trace.entries.single.x, 300);
    expect(trace.entries.single.taskName, isEmpty);
  });

  test('ignores lines that are not actual click logs', () {
    final trace = ClickTraceAccumulator();
    final line = logLine(1, '2026-10-02 10:00:02 | INFO | Click image not found');
    expect(ClickTraceAccumulator.isRelevant(line), isFalse);
    expect(trace.add(line), isFalse);
    expect(trace.entries, isEmpty);
  });
}
