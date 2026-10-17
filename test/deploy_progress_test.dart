import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/server/models/deploy_git_prefetcher.dart';
import 'package:oasx/modules/server/models/deploy_log_archive.dart';
import 'package:oasx/modules/server/models/deploy_progress.dart';

void main() {
  test(
    'no update stays hidden and backend is not marked ready before connection',
    () {
      final progress = DeployProgress()
        ..beginAttempt(0)
        ..checkingUpdate()
        ..noUpdate()
        ..installing()
        ..startingService()
        ..connecting();
      expect(progress.showUpdate, isFalse);
      expect(progress.startup.last.status, DeployStageStatus.active);
      progress.connected();
      expect(progress.startup.last.status, DeployStageStatus.done);
    },
  );

  test(
    'progress is per Git phase, deduplicated, and not whole-update completion',
    () {
      final progress = DeployProgress()
        ..beginAttempt(0)
        ..checkingUpdate()
        ..updateAvailable();
      for (var i = 0; i < 100; i++) {
        progress.consume('INFO: Receiving objects: 65% (65/100)\r');
      }
      expect(
        progress.update
            .where((stage) => stage.id == 'receiving objects')
            .length,
        1,
      );
      expect(progress.update.last.percent, 65);
      progress.consume('Receiving objects: 100%\rResolving deltas: 10%');
      expect(progress.update.last.title, '处理更新文件');
      expect(progress.update.last.percent, 10);
      expect(progress.update.any((stage) => stage.id == 'finished'), isFalse);
      progress.fetched();
      progress.installing();
      expect(progress.update.last.status, DeployStageStatus.active);
      progress.consume('========== SHOW VERSION ==========');
      expect(progress.update.last.title, 'OAS 更新完成');
    },
  );

  test(
    'arbitrary logs do not become stages and unavailable percentages are not fabricated',
    () {
      final progress = DeployProgress()
        ..beginAttempt(0)
        ..checkingUpdate()
        ..updateAvailable();
      for (final line in [
        '[success]',
        'config --local http.version HTTP/1.1',
        'Receiving objects: 999%',
        'INFO: more output',
      ]) {
        expect(progress.consume(line), isFalse);
      }
      expect(progress.update.last.percent, isNull);
    },
  );

  test(
    'network failure expands update pane and retry resets stale progress',
    () {
      final progress = DeployProgress()
        ..beginAttempt(0)
        ..checkingUpdate();
      progress.failed('连接远程仓库失败');
      expect(progress.showUpdate, isTrue);
      progress.retrying(1, const Duration(seconds: 3));
      expect(progress.update.last.detail, contains('1 / 5'));
      progress.beginAttempt(1);
      progress.checkingUpdate();
      expect(progress.update.last.percent, isNull);
      expect(progress.startup.first.detail, contains('1 / 5'));
      progress.noUpdate();
      progress.startingService();
      progress.failed('后台服务提前退出');
      expect(progress.startup.last.status, DeployStageStatus.failed);
    },
  );

  test('dependency stages accept actual uppercase installer headings', () {
    final progress = DeployProgress()
      ..beginAttempt(0)
      ..checkingUpdate()
      ..updateAvailable()
      ..installing();
    progress.consume('========== UPDATE DEPENDENCIES ==========');
    expect(progress.startup.last.title, '检查 OAS 运行环境');
    expect(progress.update.last.status, DeployStageStatus.done);
  });

  test(
    'installer update failure stays visible even if prefetch found no changes',
    () {
      final progress = DeployProgress()
        ..beginAttempt(0)
        ..checkingUpdate()
        ..noUpdate()
        ..installing();
      progress.consume('| UPDATE FAILED |');
      expect(progress.showUpdate, isTrue);
      expect(progress.update.last.status, DeployStageStatus.failed);
    },
  );

  test(
    'remote revision parsing matches exact branch, not an abbreviated name',
    () {
      final hash = 'a' * 40;
      expect(
        DeployGitPrefetcher.parseRemoteRevision(
          '$hash\trefs/heads/mine\r\n',
          'mine',
        ),
        hash,
      );
      expect(
        DeployGitPrefetcher.parseRemoteRevision(
          '$hash\trefs/heads/mine-old',
          'mine',
        ),
        isNull,
      );
    },
  );

  group('prefetch version checks', () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('oasx-git-check-');
      await Directory('${root.path}/config').create();
      await File('${root.path}/config/deploy.yaml').writeAsString(
        'Deploy:\n  Git:\n    Branch: mine\n    AutoUpdate: true\n',
      );
    });
    tearDown(() => root.delete(recursive: true));

    Future<List<String>> runCheck({
      required String head,
      required String remote,
      String? fetched,
      bool networkFails = false,
    }) async {
      final events = <String>[];
      final prefetch = DeployGitPrefetcher(
        rootPath: root.path,
        log: (_) {},
        runShell: (command, {bool allowFailure = false}) async {
          if (command.contains('fetch')) events.add('fetch');
          return true;
        },
        readShell: (command, {bool allowFailure = false}) async {
          if (command.contains('ls-remote')) {
            return networkFails ? null : '$remote\trefs/heads/mine';
          }
          return command.contains('FETCH_HEAD') ? fetched ?? remote : head;
        },
        onAvailable: () => events.add('available'),
        onUnchanged: () => events.add('unchanged'),
        onDisabled: () => events.add('disabled'),
        onFetched: () => events.add('fetched'),
      );
      events.add(await prefetch.prefetchRepository() ? 'success' : 'failure');
      return events;
    }

    test('only known new revision expands before downloading', () async {
      expect(await runCheck(head: 'a' * 40, remote: 'b' * 40), [
        'available',
        'fetch',
        'available',
        'fetched',
        'success',
      ]);
    });
    test('same revision remains hidden', () async {
      expect(await runCheck(head: 'a' * 40, remote: 'a' * 40), [
        'unchanged',
        'fetch',
        'fetched',
        'success',
      ]);
    });
    test('network failure is not reported as no update', () async {
      expect(
        await runCheck(head: 'a' * 40, remote: 'b' * 40, networkFails: true),
        ['failure'],
      );
    });
    test('remote change during check is caught after fetch', () async {
      expect(
        await runCheck(head: 'a' * 40, remote: 'a' * 40, fetched: 'b' * 40),
        ['unchanged', 'fetch', 'available', 'fetched', 'success'],
      );
    });
  });

  test('full logs survive progress replacement and archive closure', () async {
    final root = await Directory.systemTemp.createTemp('oasx-deploy-log-');
    final archive = DeployLogArchive();
    try {
      await archive.open(root.path);
      for (var i = 0; i <= 100; i++) {
        archive.add('Receiving objects: $i%');
      }
      final text = await archive.read();
      expect(text.split('\n').where((line) => line.isNotEmpty).length, 101);
      await archive.close();
      expect(await archive.read(), text);
    } finally {
      await archive.close();
      await root.delete(recursive: true);
    }
  });
}
