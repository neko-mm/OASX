import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/home/widgets/auto_deploy_overlay.dart';
import 'package:oasx/modules/server/models/deploy_progress.dart';

Widget screen(
  DeployProgress progress, {
  bool reducedMotion = true,
  VoidCallback? viewLogs,
}) => MaterialApp(
  theme: ThemeData.dark().copyWith(
    colorScheme: const ColorScheme.dark(primary: Color(0xFF80D8F3)),
  ),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: Scaffold(
      body: AutoDeployOverlay(
        progress: progress,
        onViewLogs: viewLogs ?? () {},
      ),
    ),
  ),
);

Future<void> revealAll(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 350));
  }
}

void main() {
  testWidgets(
    'no update hides title and log flood; complete logs remain accessible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var opened = 0;
      final progress = DeployProgress()
        ..beginAttempt(0)
        ..checkingUpdate()
        ..noUpdate()
        ..installing();
      await tester.pumpWidget(screen(progress, viewLogs: () => opened++));
      await revealAll(tester);
      expect(find.text('OAS 更新'), findsNothing);
      expect(find.text('OAS 启动'), findsOneWidget);
      expect(find.text('Receiving objects:'), findsNothing);
      await tester.tap(find.text('查看完整日志'));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'update appears on right while fixed deployment link does not move',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final progress = DeployProgress()
        ..beginAttempt(0)
        ..checkingUpdate();
      await tester.pumpWidget(screen(progress));
      await revealAll(tester);
      final before = tester.getRect(
        find.byKey(const ValueKey('go-deploy-page')),
      );
      progress.updateAvailable();
      progress.consume('Receiving objects: 65%');
      await tester.pumpWidget(screen(progress));
      await revealAll(tester);
      expect(
        tester.getRect(find.byKey(const ValueKey('go-deploy-page'))),
        before,
      );
      expect(
        tester.getCenter(find.text('OAS 更新')).dx,
        greaterThan(tester.getCenter(find.text('OAS 启动')).dx),
      );
      expect(find.text('65%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phase rows reveal one at a time instead of appearing in a burst',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final progress = DeployProgress()
        ..beginAttempt(0)
        ..checkingUpdate()
        ..noUpdate()
        ..installing();
      await tester.pumpWidget(screen(progress, reducedMotion: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('读取启动配置'), findsOneWidget);
      expect(find.text('当前已是最新版本'), findsNothing);
      await tester.pump(const Duration(milliseconds: 330));
      expect(find.text('当前已是最新版本'), findsOneWidget);
      await revealAll(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('compact viewport and retry reset have no overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final progress = DeployProgress()
      ..beginAttempt(0)
      ..checkingUpdate()
      ..updateAvailable();
    await tester.pumpWidget(screen(progress));
    await revealAll(tester);
    progress.beginAttempt(1);
    progress.checkingUpdate();
    await tester.pumpWidget(screen(progress));
    await revealAll(tester);
    expect(tester.takeException(), isNull);
  });
}
