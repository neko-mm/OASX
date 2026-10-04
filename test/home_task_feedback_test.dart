import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';

class _MemoryStorage implements HomeDashboardStorage {
  @override
  dynamic read(String key) => null;

  @override
  void write(String key, dynamic value) {}
}

void main() {
  testWidgets('左下角同时显示两条任务结果，其余按顺序排队', (tester) async {
    final controller = HomeDashboardController(storage: _MemoryStorage());
    addTearDown(controller.onClose);

    controller.showTaskFeedback('斗技', success: true);
    controller.showTaskFeedback('每日琐事', success: true);
    controller.showTaskFeedback('八岐大蛇', success: false);
    controller.showTaskFeedback(
      '式神委派',
      success: true,
      resultText: '复制成功',
    );

    expect(controller.taskFeedbacks.map((item) => item.taskName).toList(),
        ['斗技', '每日琐事']);
    await tester.pump(const Duration(milliseconds: 1800));
    expect(controller.taskFeedbacks.map((item) => item.taskName).toList(),
        ['八岐大蛇', '式神委派']);
    expect(controller.taskFeedbacks.last.resultText, '复制成功');
    await tester.pump(const Duration(milliseconds: 1800));
    expect(controller.taskFeedbacks.single.taskName, '八岐大蛇');
    expect(controller.taskFeedbacks.single.success, isFalse);
    await tester.pump(const Duration(milliseconds: 1400));
    expect(controller.taskFeedbacks, isEmpty);
  });
}
