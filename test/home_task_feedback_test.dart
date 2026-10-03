import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';

class _MemoryStorage implements HomeDashboardStorage {
  @override
  dynamic read(String key) => null;

  @override
  void write(String key, dynamic value) {}
}

void main() {
  testWidgets('任务结果逐条显示，不合并也不覆盖', (tester) async {
    final controller = HomeDashboardController(storage: _MemoryStorage());
    addTearDown(controller.onClose);

    controller.showTaskFeedback('斗技', success: true);
    controller.showTaskFeedback('每日琐事', success: true);
    controller.showTaskFeedback('八岐大蛇', success: false);

    expect(controller.taskFeedback.value?.taskName, '斗技');
    await tester.pump(const Duration(milliseconds: 1800));
    expect(controller.taskFeedback.value?.taskName, '每日琐事');
    await tester.pump(const Duration(milliseconds: 1800));
    expect(controller.taskFeedback.value?.taskName, '八岐大蛇');
    expect(controller.taskFeedback.value?.success, isFalse);
    await tester.pump(const Duration(milliseconds: 3200));
    expect(controller.taskFeedback.value, isNull);
  });
}
