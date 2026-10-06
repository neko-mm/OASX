import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/log/log_browser_models.dart';
import 'package:oasx/service/ai_analysis/ai_analysis_service.dart';
import 'package:oasx/service/ai_analysis/ai_log_analysis.dart';
import 'package:oasx/service/ai_analysis/ai_provider.dart';

ScriptLogLine line(int number, String text) => ScriptLogLine(
      fileName: '2026-10-04.log',
      lineNo: number,
      offset: number * 100,
      byteLength: text.length,
      text: text,
      lineTruncated: false,
    );

void main() {
  test('only the latest run is prepared, across history pages', () {
    final draft = AiLogAnalysis.prepare([
      [line(4, '开始任务：每日琐事'), line(5, 'No task pending')],
      [line(1, 'old account data'), line(2, 'Start scheduler loop:'),
       line(3, '开始任务：八岐大蛇')],
    ]);
    expect(draft.partial, isFalse);
    expect(draft.text, contains('八岐大蛇'));
    expect(draft.text, contains('No task pending'));
    expect(draft.text, isNot(contains('old account data')));
  });

  test('missing run start is clearly partial', () {
    final draft = AiLogAnalysis.prepare([[line(1, '战斗结果：胜利')]]);
    expect(draft.partial, isTrue);
    expect(draft.lineCount, 1);
  });

  test('long task keeps start, warning, recovery and end', () {
    final lines = <ScriptLogLine>[
      line(1, '开始运行任务调度：日常'),
      line(2, '开始任务：八岐大蛇'),
      for (var i = 3; i < 500; i++) line(i, '普通点击 $i'),
      line(500, '12:00 WARNING | 页面切换失败'),
      line(501, '重试点击'),
      line(502, 'Page arrived page_main'),
      for (var i = 503; i < 1000; i++) line(i, '普通点击 $i'),
      line(1000, '任务结束：八岐大蛇'),
      line(1001, '当前没有待运行任务，等待下次执行'),
    ];
    final draft = AiLogAnalysis.prepare([lines.sublist(700),
      lines.sublist(0, 700)]);
    expect(draft.partial, isFalse);
    expect(draft.sourceLineCount, 1001);
    expect(draft.lineCount, lessThan(30));
    expect(draft.text, contains('开始任务：八岐大蛇'));
    expect(draft.text, contains('页面切换失败'));
    expect(draft.text, contains('Page arrived page_main'));
    expect(draft.text, contains('任务结束：八岐大蛇'));
  });

  test('idle boundary excludes previous task cycle', () {
    final draft = AiLogAnalysis.prepare([[
      line(1, '开始运行任务调度：日常'),
      line(2, '开始任务：昨天'),
      line(3, '任务结束：昨天'),
      line(4, '当前没有待运行任务，等待下次执行'),
      line(5, '开始任务：今天'),
      line(6, '任务结束：今天'),
    ]]);
    expect(draft.partial, isFalse);
    expect(draft.text, contains('今天'));
    expect(draft.text, isNot(contains('昨天')));
  });

  test('sensitive lines and identifiers are removed before preview', () {
    final draft = AiLogAnalysis.prepare([[
      line(1, 'Start scheduler loop:'),
      line(2, '账号: neko 游戏角色'),
      line(3, 'api_key=sk-secret'),
      line(4, r'WARNING module_path: D:\Users\neko\oas\script.py'),
      line(5, 'WARNING contact neko@example.com at https://example.com'),
      line(6, 'WARNING server 192.168.1.20:8080'),
    ]]);
    expect(draft.text, isNot(contains('游戏角色')));
    expect(draft.text, isNot(contains('sk-secret')));
    expect(draft.text, isNot(contains('neko\\oas')));
    expect(draft.text, isNot(contains('neko@example.com')));
    expect(draft.text, isNot(contains('https://example.com')));
    expect(draft.text, isNot(contains('192.168.1.20')));
    expect(draft.text, contains('[本地路径]'));
    expect(draft.text, contains('[邮箱]'));
  });

  test('local analysis distinguishes normal finish and error', () {
    expect(
      AiLogAnalysis.localSummary('No task pending', partial: false),
      contains('队列已空'),
    );
    expect(
      AiLogAnalysis.localSummary('ERROR timeout\nNo task pending',
          partial: false),
      contains('错误'),
    );
  });

  test('providers have independent endpoints and the request is text only', () {
    expect(AiProvider.values.map((p) => p.endpoint).toSet().length, 3);
    final body = AiAnalysisService.analysisBody('model-a', '脱敏后的日志');
    expect(body['model'], 'model-a');
    expect(body.toString(), contains('脱敏后的日志'));
    expect(body.toString(), isNot(contains('image_url')));
    expect(body.toString(), isNot(contains('tools')));
  });

  test('AI analysis asks for concise evidence-based sections', () {
    final body = AiAnalysisService.analysisBody('model-a', '测试日志');
    final messages = body['messages'] as List<dynamic>;
    final instruction = messages.first['content'] as String;
    expect(instruction, contains('运行结果'));
    expect(instruction, contains('异常与恢复'));
    expect(instruction, contains('需要核实'));
    expect(instruction, contains('页面出现或重复点击不能单独证明'));
    expect(instruction, contains('不要写免责声明'));
  });
}
